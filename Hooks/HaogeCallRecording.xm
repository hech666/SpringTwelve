#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreTelephony/CTCallCenter.h>
#import <CoreTelephony/CTCall.h>
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <signal.h>
#import <spawn.h>
#import <stdlib.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>
#import "HaogeCallRecorderPaths.h"
#import "HaogeSpringTwelvePreferences.h"
#import "HaogeCallRecorderSwitches.h"
#import "HaogeCallRecorderControl.h"
#import "HaogeCallRecorderNamingContext.h"

static int HaogeCallRecorderWriteControl(NSString *readyPath, BOOL aborting) {
    NSString *path = [readyPath.stringByDeletingPathExtension stringByAppendingPathExtension:@"control"];
    int directory = open(path.stringByDeletingLastPathComponent.fileSystemRepresentation, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if (directory < 0) return errno;
    NSString *temporary = [path.lastPathComponent stringByAppendingFormat:@".%@", NSUUID.UUID.UUIDString];
    int code = haoge_control_write(directory, path.lastPathComponent.fileSystemRepresentation, temporary.fileSystemRepresentation, aborting ? HaogeControlAbort : HaogeControlNormal);
    close(directory); return code;
}

// One independent dual-tap realtime PCM -> LAME worker. No CAF/mixer pipeline.

typedef void (*HaogeCallRecorderCTCallback)(CFNotificationCenterRef, void *, CFStringRef, const void *, CFDictionaryRef);
typedef CFNotificationCenterRef (*HaogeCallRecorderCTGetDefault)(void);
typedef void (*HaogeCallRecorderCTAddObserver)(CFNotificationCenterRef, const void *, HaogeCallRecorderCTCallback,
                                               CFStringRef, const void *, CFNotificationSuspensionBehavior);

// Deprecated public cellular API is retained only as a second event source on
// supported iOS 15/16 devices; this deliberately does not enable VoIP capture.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static void HaogeCallRecorderRecordLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void HaogeCallRecorderRecordLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%@ %@", @"[HaogeCallRecorder:Record]", message);
    @synchronized (NSFileManager.class) {
        NSString *directory = [haoge_callrecorder_recordingDirectory() stringByAppendingPathComponent:@"Diagnostics"];
        NSFileManager *manager = NSFileManager.defaultManager;
        if (![manager createDirectoryAtPath:directory withIntermediateDirectories:YES
                                attributes:@{NSFilePosixPermissions: @0700} error:NULL]) return;
        NSString *path = [directory stringByAppendingPathComponent:@"HaogeCallRecorder-recording.log"];
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
        if ([attributes[NSFileSize] unsignedLongLongValue] > 65536) {
            NSString *previous = [path stringByAppendingString:@".previous"];
            [manager removeItemAtPath:previous error:NULL];
            [manager moveItemAtPath:path toPath:previous error:NULL];
        }
        if (![manager fileExistsAtPath:path]) [manager createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions: @0600}];
        NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
        @try {
            [file seekToEndOfFile];
            NSString *line = [NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, message];
            [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [file closeFile];
        } @catch (__unused NSException *exception) { [file closeFile]; }
    }
}

extern char **environ;
static NSString * const HaogeCallRecorderRecordingStateChanged = @"com.haoge.springtwelve.recording.call-recording-state";
static CFStringRef HaogeCallRecorderCallStatusNotification;
static CFStringRef HaogeCallRecorderCallIdentificationNotification;

@interface HaogeCallRecorderRecordingIndicator : NSObject
@property(nonatomic, strong) UIWindow *haoge_callrecorder_window;
@property(nonatomic, strong) UILabel *haoge_callrecorder_label;
@property(nonatomic, strong) NSTimer *haoge_callrecorder_hideTimer;
@property(nonatomic) NSUInteger haoge_callrecorder_textVersion;
- (void)haoge_callrecorder_showRecording;
- (void)haoge_callrecorder_showSaved;
- (void)haoge_callrecorder_showFailure:(NSString *)reason;
@end

@implementation HaogeCallRecorderRecordingIndicator

- (void)haoge_callrecorder_ensureWindow {
    if (self.haoge_callrecorder_window) return;
    CGRect screen = UIScreen.mainScreen.bounds;
    CGFloat width = MIN(142.0, MAX(116.0, screen.size.width - 24.0));
    CGRect frame = CGRectMake(screen.size.width - width - 8.0, 5.0, width, 30.0);
    UIWindowScene *targetScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) {
            targetScene = (UIWindowScene *)scene;
            break;
        }
    }
    UIWindow *window = targetScene ? [[UIWindow alloc] initWithWindowScene:targetScene] : [[UIWindow alloc] initWithFrame:frame];
    window.frame = frame;
    window.windowLevel = UIWindowLevelStatusBar + 2.0;
    window.backgroundColor = [UIColor clearColor];
    window.userInteractionEnabled = NO;
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = [UIColor clearColor];
    window.rootViewController = controller;
    UILabel *label = [[UILabel alloc] initWithFrame:window.bounds];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont boldSystemFontOfSize:12.0];
    label.textColor = UIColor.whiteColor;
    label.layer.cornerRadius = 9.0;
    label.layer.masksToBounds = YES;
    [controller.view addSubview:label];
    self.haoge_callrecorder_window = window;
    self.haoge_callrecorder_label = label;
}

- (void)haoge_callrecorder_showText:(NSString *)text color:(UIColor *)color hideAfter:(NSTimeInterval)delay {
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf haoge_callrecorder_showText:text color:color hideAfter:delay]; });
        return;
    }
    [self.haoge_callrecorder_hideTimer invalidate];
    [self haoge_callrecorder_ensureWindow];
    NSUInteger textVersion = ++self.haoge_callrecorder_textVersion;
    [self.haoge_callrecorder_window.layer removeAllAnimations];
    self.haoge_callrecorder_label.text = text;
    self.haoge_callrecorder_label.backgroundColor = color;
    self.haoge_callrecorder_window.hidden = NO;
    self.haoge_callrecorder_window.alpha = 1.0;
    if (delay > 0.0) {
        __weak typeof(self) weakSelf = self;
        self.haoge_callrecorder_hideTimer = [NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(__unused NSTimer *timer) {
            if (weakSelf.haoge_callrecorder_textVersion != textVersion) return;
            [UIView animateWithDuration:0.25 animations:^{ weakSelf.haoge_callrecorder_window.alpha = 0.0; }
                             completion:^(__unused BOOL finished) {
                if (weakSelf.haoge_callrecorder_textVersion == textVersion) weakSelf.haoge_callrecorder_window.hidden = YES;
            }];
        }];
    }
}

- (void)haoge_callrecorder_showRecording {
    [self haoge_callrecorder_showText:@"● 录音中" color:[UIColor colorWithRed:0.78 green:0.08 blue:0.08 alpha:0.94] hideAfter:0.0];
}
- (void)haoge_callrecorder_showSaved {
    [self haoge_callrecorder_showText:@"录音已保存" color:[UIColor colorWithRed:0.10 green:0.48 blue:0.20 alpha:0.94] hideAfter:2.5];
}
- (void)haoge_callrecorder_showFailure:(NSString *)reason {
    NSString *text = reason.length ? [NSString stringWithFormat:@"录音失败：%@", reason] : @"录音失败";
    [self haoge_callrecorder_showText:text color:[UIColor colorWithRed:0.72 green:0.30 blue:0.04 alpha:0.94] hideAfter:3.0];
}
@end

// Signal and waitpid share one lock, so a reaped PID can never be signalled
// after the kernel has recycled it. Escalation runs even after UI state clears.
@interface HaogeCallRecorderRecordingWorker : NSObject
@property(nonatomic) pid_t haoge_callrecorder_pid;
@property(nonatomic, copy) NSString *haoge_callrecorder_readyPath;
@property(nonatomic) BOOL haoge_callrecorder_stopSent;
@property(nonatomic) BOOL haoge_callrecorder_abortRequested;
@property(nonatomic) NSTimeInterval haoge_callrecorder_stopTime;
- (void)haoge_callrecorder_requestStop;
- (void)haoge_callrecorder_requestAbort;
- (int)haoge_callrecorder_wait:(pid_t *)result;
@end
@implementation HaogeCallRecorderRecordingWorker
- (void)haoge_callrecorder_requestStop {
    @synchronized (self) {
        if (self.haoge_callrecorder_pid <= 0 || self.haoge_callrecorder_stopTime > 0) return;
        self.haoge_callrecorder_stopTime = NSProcessInfo.processInfo.systemUptime;
        int code=HaogeCallRecorderWriteControl(self.haoge_callrecorder_readyPath, NO);
        self.haoge_callrecorder_stopSent=code==0;
        BOOL ready=[NSFileManager.defaultManager fileExistsAtPath:self.haoge_callrecorder_readyPath];
        HaogeCallRecorderRecordLog(@"normal-stop control errno=%d ready=%d",code,ready);
        // SIGINT is fallback only; a successful file handshake does not depend on signal disposition.
        if(code && ready){errno=0;int rc=kill(self.haoge_callrecorder_pid,SIGINT);int e=rc?errno:0;HaogeCallRecorderRecordLog(@"stop fallback SIGINT rc=%d errno=%d",rc,e);}
    }
}
- (void)haoge_callrecorder_requestAbort {
    @synchronized(self) {
        if(self.haoge_callrecorder_pid<=0)return;
        self.haoge_callrecorder_stopTime=NSProcessInfo.processInfo.systemUptime;
        self.haoge_callrecorder_abortRequested=YES;
        int code=HaogeCallRecorderWriteControl(self.haoge_callrecorder_readyPath, YES);
        self.haoge_callrecorder_stopSent=code==0;
        errno=0;int rc=kill(self.haoge_callrecorder_pid,SIGTERM);int e=rc?errno:0;
        HaogeCallRecorderRecordLog(@"abort control errno=%d SIGTERM rc=%d errno=%d",code,rc,e);
    }
}
- (int)haoge_callrecorder_wait:(pid_t *)result {
    int status = 0;
    BOOL sentTerm = NO, sentKill = NO;
    for (;;) {
        @synchronized (self) {
            pid_t pid = self.haoge_callrecorder_pid;
            pid_t value = waitpid(pid, &status, WNOHANG);
            if (value == pid || (value < 0 && errno != EINTR)) {
                self.haoge_callrecorder_pid = 0;
                if (result) *result = value;
                return status;
            }
            NSTimeInterval age = self.haoge_callrecorder_stopTime > 0 ? NSProcessInfo.processInfo.systemUptime - self.haoge_callrecorder_stopTime : 0;
            if(self.haoge_callrecorder_stopTime>0 && !self.haoge_callrecorder_stopSent){
                int code=HaogeCallRecorderWriteControl(self.haoge_callrecorder_readyPath,self.haoge_callrecorder_abortRequested);
                self.haoge_callrecorder_stopSent=code==0;
            }
            if (age > 60.0 && !sentTerm) { self.haoge_callrecorder_abortRequested=YES;self.haoge_callrecorder_stopSent=HaogeCallRecorderWriteControl(self.haoge_callrecorder_readyPath,YES)==0;errno=0;int rc=kill(pid,SIGTERM);HaogeCallRecorderRecordLog(@"escalate SIGTERM rc=%d errno=%d",rc,rc?errno:0);sentTerm=YES; }
            if (age > 65.0 && !sentKill) { errno=0;int rc=kill(pid,SIGKILL);HaogeCallRecorderRecordLog(@"escalate SIGKILL rc=%d errno=%d",rc,rc?errno:0);sentKill=YES; }
        }
        usleep(100000);
    }
}
@end

@interface HaogeCallRecorderCallRecorder : NSObject {
@public
    dispatch_queue_t _haoge_callrecorder_queue;
    HaogeCallRecorderRecordingWorker *_haoge_callrecorder_worker;
    NSString *_haoge_callrecorder_outputPath;
    NSString *_haoge_callrecorder_statusPath;
    NSUInteger _haoge_callrecorder_generation;
    BOOL _haoge_callrecorder_active, _haoge_callrecorder_finishing, _haoge_callrecorder_failed;
    NSTimeInterval _haoge_callrecorder_startedAt;
    HaogeCallRecorderRecordingIndicator *_haoge_callrecorder_indicator;
    CTCallCenter *_haoge_callrecorder_cellularCenter;
    HaogeCallRecorderNamingContext *_haoge_callrecorder_namingContext;
}
+ (instancetype)haoge_callrecorder_shared;
- (void)haoge_callrecorder_installTelephonyObserver;
- (void)haoge_callrecorder_handleCallStatus:(int)status;
- (void)haoge_callrecorder_stopLockedWithReason:(NSString *)reason;
@end

static void HaogeCallRecorderCallNotification(CFNotificationCenterRef center, void *observer,
                                             CFStringRef name, const void *object, CFDictionaryRef userInfo);

static NSString *HaogeCallRecorderResolveHelper(NSString *name) {
    NSString *path = haoge_callrecorder_resourcePath([@"/usr/local/bin/" stringByAppendingString:name]);
    if (path.length && access(path.fileSystemRepresentation, X_OK) == 0) return path;
    return nil;
}

static BOOL HaogeCallRecorderSpawn(NSString *path, NSArray<NSString *> *arguments, pid_t *pidOut, int *errorOut) {
    if (!path.length || !pidOut || arguments.count == 0) {
        if (errorOut) *errorOut = EINVAL;
        return NO;
    }
    NSMutableArray<NSString *> *argvStrings = [NSMutableArray arrayWithObject:path];
    [argvStrings addObjectsFromArray:arguments];
    char **argv = (char **)calloc(argvStrings.count + 1, sizeof(char *));
    if (!argv) {
        if (errorOut) *errorOut = ENOMEM;
        return NO;
    }
    for (NSUInteger i = 0; i < argvStrings.count; i++) argv[i] = (char *)argvStrings[i].fileSystemRepresentation;
    pid_t pid = 0;
    // Match the original coordinator: do not inherit SpringBoard's injection
    // environment into the entitled standalone audio worker.
    posix_spawn_file_actions_t actions;
    int actionError = posix_spawn_file_actions_init(&actions);
    BOOL actionsInitialized = actionError == 0;
    NSString *diagnostics = [haoge_callrecorder_recordingDirectory() stringByAppendingPathComponent:@"Diagnostics"];
    [NSFileManager.defaultManager createDirectoryAtPath:diagnostics withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];
    NSString *log = [diagnostics stringByAppendingPathComponent:@"HaogeCallRecorder-helpers.log"];
    int logFD = open(log.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (!actionError && logFD >= 0) actionError = posix_spawn_file_actions_adddup2(&actions, logFD, STDERR_FILENO);
    int error = actionError ? actionError : posix_spawn(&pid, path.fileSystemRepresentation, &actions, NULL, argv, NULL);
    if (actionsInitialized) posix_spawn_file_actions_destroy(&actions);
    if (logFD >= 0) close(logFD);
    free(argv);
    if (errorOut) *errorOut = error;
    if (error != 0) return NO;
    *pidOut = pid;
    return YES;
}

@implementation HaogeCallRecorderCallRecorder

+ (instancetype)haoge_callrecorder_shared {
    static HaogeCallRecorderCallRecorder *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [self new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _haoge_callrecorder_queue = dispatch_queue_create("com.haoge.springtwelve.recording.call-recording", DISPATCH_QUEUE_SERIAL);
        _haoge_callrecorder_indicator = [HaogeCallRecorderRecordingIndicator new];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(haoge_callrecorder_preferencesChanged:)
            name:HaogeSpringTwelvePreferencesChanged object:nil];
    }
    return self;
}

- (void)haoge_callrecorder_preferencesChanged:(NSNotification *)notification {
    dispatch_async(_haoge_callrecorder_queue, ^{
        if (!HaogeCallRecorderOn(@"callRecordingEnabled") && self->_haoge_callrecorder_active)
            [self haoge_callrecorder_stopLockedWithReason:@"设置已关闭"];
    });
}

- (void)haoge_callrecorder_installTelephonyObserver {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _haoge_callrecorder_cellularCenter = [CTCallCenter new];
        __weak typeof(self) weakSelf = self;
        _haoge_callrecorder_cellularCenter.callEventHandler = ^(CTCall *call) {
            HaogeCallRecorderCallRecorder *recorder = weakSelf;
            if (!recorder) return;
            NSString *state = [call.callState copy];
            NSString *namingID = [call.callID copy];
            BOOL namingMultiple = recorder->_haoge_callrecorder_cellularCenter.currentCalls.count > 1;
            dispatch_async(recorder->_haoge_callrecorder_queue, ^{
                [recorder->_haoge_callrecorder_namingContext haoge_callrecorder_observeID:namingID state:state multiple:namingMultiple];
                [recorder->_haoge_callrecorder_namingContext haoge_callrecorder_sample:recorder->_haoge_callrecorder_cellularCenter];
            });
            // No callID, phone number, address or contact details are logged.
            BOOL connected = [state isEqualToString:CTCallStateConnected];
            BOOL ended = [state isEqualToString:CTCallStateDisconnected];
            HaogeCallRecorderRecordLog(@"cellular event connected=%d ended=%d", connected, ended);
            if (connected) [recorder haoge_callrecorder_handleCallStatus:1];
            else if (ended) {
                BOOL otherConnected = NO;
                for (CTCall *current in recorder->_haoge_callrecorder_cellularCenter.currentCalls) {
                    if ([current.callState isEqualToString:CTCallStateConnected]) { otherConnected = YES; break; }
                }
                if (!otherConnected) [recorder haoge_callrecorder_handleCallStatus:5];
            }
        };
        HaogeCallRecorderRecordLog(@"module loaded; cellular fallback installed; enabled=%d", HaogeCallRecorderOn(@"callRecordingEnabled"));
        void *handle = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY | RTLD_LOCAL);
        HaogeCallRecorderCTGetDefault getDefault = handle ? (HaogeCallRecorderCTGetDefault)dlsym(handle, "CTTelephonyCenterGetDefault") : NULL;
        HaogeCallRecorderCTAddObserver addObserver = handle ? (HaogeCallRecorderCTAddObserver)dlsym(handle, "CTTelephonyCenterAddObserver") : NULL;
        CFStringRef *statusName = handle ? (CFStringRef *)dlsym(handle, "kCTCallStatusChangeNotification") : NULL;
        CFStringRef *identificationName = handle ? (CFStringRef *)dlsym(handle, "kCTCallIdentificationChangeNotification") : NULL;
        HaogeCallRecorderCallStatusNotification = statusName ? *statusName : NULL;
        HaogeCallRecorderCallIdentificationNotification = identificationName ? *identificationName : NULL;
        if (!getDefault || !addObserver || !HaogeCallRecorderCallStatusNotification) {
            HaogeCallRecorderRecordLog(@"CoreTelephony observer unavailable");
            return;
        }
        CFNotificationCenterRef center = getDefault();
        addObserver(center, NULL, (HaogeCallRecorderCTCallback)HaogeCallRecorderCallNotification,
                    HaogeCallRecorderCallStatusNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        if (HaogeCallRecorderCallIdentificationNotification)
            addObserver(center, NULL, (HaogeCallRecorderCTCallback)HaogeCallRecorderCallNotification,
                        HaogeCallRecorderCallIdentificationNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        HaogeCallRecorderRecordLog(@"CoreTelephony observer installed");
    });
}

- (void)haoge_callrecorder_handleCallStatus:(int)status {
    HaogeCallRecorderRecordLog(@"telephony status=%d", status);
    dispatch_async(_haoge_callrecorder_queue, ^{
        if (status == 1) {
            [self haoge_callrecorder_startLocked];
            [self->_haoge_callrecorder_namingContext haoge_callrecorder_sample:self->_haoge_callrecorder_cellularCenter];
        } else if (status == 2 || status == 5) {
            // A rejected second call must not stop an already connected call.
            for (CTCall *current in self->_haoge_callrecorder_cellularCenter.currentCalls) {
                if ([current.callState isEqualToString:CTCallStateConnected]) {
                    HaogeCallRecorderRecordLog(@"end deferred: cellular call still connected");
                    return;
                }
            }
            [self haoge_callrecorder_stopLockedWithReason:nil];
        }
    });
}

- (void)haoge_callrecorder_probeGeneration:(NSUInteger)generation {
    if (generation != _haoge_callrecorder_generation || !_haoge_callrecorder_active) return;
    [_haoge_callrecorder_namingContext haoge_callrecorder_sample:_haoge_callrecorder_cellularCenter];
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:_haoge_callrecorder_statusPath error:NULL];
    NSString *value=[NSString stringWithContentsOfFile:_haoge_callrecorder_statusPath encoding:NSUTF8StringEncoding error:NULL];
    BOOL progress=value.longLongValue>0;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSDate *date=attributes[NSFileModificationDate];
    if (progress && date && now-date.timeIntervalSince1970<5.) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self->_haoge_callrecorder_indicator haoge_callrecorder_showRecording]; });
    } else if (now-_haoge_callrecorder_startedAt>6.) {
        _haoge_callrecorder_failed=YES;
        HaogeCallRecorderRecordLog(@"realtime helper has no recent paired PCM progress; aborting");
        [_haoge_callrecorder_worker haoge_callrecorder_requestAbort];
        _haoge_callrecorder_active=NO;_haoge_callrecorder_finishing=YES;
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),_haoge_callrecorder_queue, ^{ [self haoge_callrecorder_probeGeneration:generation]; });
}
- (void)haoge_callrecorder_startLocked {
    if (_haoge_callrecorder_active || _haoge_callrecorder_finishing || !HaogeCallRecorderOn(@"callRecordingEnabled")) return;
    NSString *helper=HaogeCallRecorderResolveHelper(@"HaogeCallRecorderRealtime");
    NSString *directory=haoge_callrecorder_recordingDirectory();
    if (!helper || ![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL]) {
        HaogeCallRecorderRecordLog(@"realtime helper unavailable or data directory unwritable");
        dispatch_async(dispatch_get_main_queue(), ^{ [self->_haoge_callrecorder_indicator haoge_callrecorder_showFailure:@"组件或目录不可用"]; });return;
    }
    NSString *name=[NSString stringWithFormat:@"HaogeSpringTwelve-%@.mp3",NSUUID.UUID.UUIDString];
    NSString *output=[directory stringByAppendingPathComponent:name];
    _haoge_callrecorder_outputPath=output;
    _haoge_callrecorder_statusPath=[[directory stringByAppendingPathComponent:@"Diagnostics"] stringByAppendingPathComponent:[name stringByAppendingString:@".status"]];
    pid_t pid=0;int error=0;
    if (!HaogeCallRecorderSpawn(helper,@[output],&pid,&error)) {
        HaogeCallRecorderRecordLog(@"realtime spawn failed errno=%d",error);
        dispatch_async(dispatch_get_main_queue(), ^{ [self->_haoge_callrecorder_indicator haoge_callrecorder_showFailure:@"无法启动采集"]; });return;
    }
    HaogeCallRecorderRecordingWorker *worker=[HaogeCallRecorderRecordingWorker new];worker.haoge_callrecorder_pid=pid;
    worker.haoge_callrecorder_readyPath=[[directory stringByAppendingPathComponent:@"Diagnostics"] stringByAppendingPathComponent:[name stringByAppendingString:@".ready"]];
    _haoge_callrecorder_worker=worker;_haoge_callrecorder_active=YES;_haoge_callrecorder_failed=NO;
    _haoge_callrecorder_startedAt=NSDate.date.timeIntervalSince1970;
    HaogeCallRecorderNamingContext *namingContext=[HaogeCallRecorderNamingContext new];
    _haoge_callrecorder_namingContext=namingContext;
    [namingContext haoge_callrecorder_sample:_haoge_callrecorder_cellularCenter];
    NSUInteger generation=++_haoge_callrecorder_generation;
    dispatch_async(dispatch_get_main_queue(), ^{ [self->_haoge_callrecorder_indicator haoge_callrecorder_showText:@"正在启动实时录音" color:[UIColor colorWithWhite:.12 alpha:.94] hideAfter:0.]; });
    [self haoge_callrecorder_probeGeneration:generation];
    HaogeCallRecorderRecordLog(@"one realtime helper spawned pid=%d",pid);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        pid_t waited=0;int status=[worker haoge_callrecorder_wait:&waited];
        dispatch_async(self->_haoge_callrecorder_queue, ^{
            if (generation!=self->_haoge_callrecorder_generation) return;
            BOOL stoppedNormally=!self->_haoge_callrecorder_active && !self->_haoge_callrecorder_failed;
            BOOL valid=stoppedNormally && waited==pid && WIFEXITED(status) && WEXITSTATUS(status)==0;
            struct stat info={};valid=valid && lstat(output.fileSystemRepresentation,&info)==0 && S_ISREG(info.st_mode) && info.st_size>0;
            if(valid){AVAudioFile *audio=[[AVAudioFile alloc]initForReading:[NSURL fileURLWithPath:output] error:NULL];valid=audio&&audio.length>0;}
            HaogeCallRecorderRecordLog(@"realtime waited=%d exit=%d signal=%d valid=%d",waited,WIFEXITED(status)?WEXITSTATUS(status):-1,WIFSIGNALED(status)?WTERMSIG(status):0,valid);
            NSDictionary *naming=[namingContext haoge_callrecorder_finish];
            if(valid) {
                @try {
                    self->_haoge_callrecorder_outputPath=HaogeCallRecorderPublishReadableRecording(output,naming[@"number"],naming[@"contact"]);
                } @catch (__unused NSException *namingException) {
                    // Name enrichment must never turn a valid recording into a failure.
                    HaogeCallRecorderRecordLog(@"readable naming unavailable; original recording retained");
                }
            }
            self->_haoge_callrecorder_namingContext=nil;
            self->_haoge_callrecorder_worker=nil;self->_haoge_callrecorder_active=NO;self->_haoge_callrecorder_finishing=NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                if(valid){[self->_haoge_callrecorder_indicator haoge_callrecorder_showSaved];[[NSNotificationCenter defaultCenter]postNotificationName:HaogeCallRecorderRecordingStateChanged object:nil];}
                else [self->_haoge_callrecorder_indicator haoge_callrecorder_showFailure:@"实时采集未完成，请查诊断"];
            });
        });
    });
}
- (void)haoge_callrecorder_stopLockedWithReason:(NSString *)reason {
    if (!_haoge_callrecorder_active) return;
    _haoge_callrecorder_active=NO;_haoge_callrecorder_finishing=YES;
    [_haoge_callrecorder_namingContext haoge_callrecorder_finish];
    [_haoge_callrecorder_worker haoge_callrecorder_requestStop];
    HaogeCallRecorderRecordLog(@"normal-stop control finalize requested %@",reason?:@"");
    dispatch_async(dispatch_get_main_queue(), ^{ [self->_haoge_callrecorder_indicator haoge_callrecorder_showText:@"正在完成MP3" color:[UIColor colorWithWhite:.12 alpha:.94] hideAfter:0.]; });
}

@end

static void HaogeCallRecorderCallNotification(CFNotificationCenterRef center, void *observer,
                                             CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (!userInfo || !HaogeCallRecorderCallStatusNotification ||
        !CFEqual(name, HaogeCallRecorderCallStatusNotification)) return;
    CFTypeRef value = CFDictionaryGetValue(userInfo, CFSTR("kCTCallStatus"));
    if (!value) return;
    int status = [(__bridge id)value intValue];
    [[HaogeCallRecorderCallRecorder haoge_callrecorder_shared] haoge_callrecorder_handleCallStatus:status];
}

%ctor {
    @autoreleasepool {
        if ([NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"])
            dispatch_async(dispatch_get_main_queue(), ^{
                [[HaogeCallRecorderCallRecorder haoge_callrecorder_shared] haoge_callrecorder_installTelephonyObserver];
            });
    }
}
#pragma clang diagnostic pop
