#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreTelephony/CTCallCenter.h>
#import <CoreTelephony/CTCall.h>
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <errno.h>
#import <signal.h>
#import <spawn.h>
#import <stdlib.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>
#import "AxsSpringTwelvePaths.h"
#import "AxsSpringTwelvePreferences.h"
#import "AxsSpringTwelveSwitches.h"

// Capture remains in the original audited MUtoolRecord executable; MP3 encoding
// is isolated in AxsSpringTwelveMP3Mixer. This coordinator owns lifecycle/files.

typedef void (*AxsSpringTwelveCTCallback)(CFNotificationCenterRef, void *, CFStringRef, const void *, CFDictionaryRef);
typedef CFNotificationCenterRef (*AxsSpringTwelveCTGetDefault)(void);
typedef void (*AxsSpringTwelveCTAddObserver)(CFNotificationCenterRef, const void *, AxsSpringTwelveCTCallback,
                                               CFStringRef, const void *, CFNotificationSuspensionBehavior);

// Deprecated public cellular API is retained only as a second event source on
// supported iOS 15/16 devices; this deliberately does not enable VoIP capture.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static void AxsSpringTwelveRecordLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void AxsSpringTwelveRecordLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%@ %@", @"[SpringTwelve:Record]", message);
    @synchronized (NSFileManager.class) {
        NSString *directory = [axs_springtwelve_recordingDirectory() stringByAppendingPathComponent:@"Diagnostics"];
        NSFileManager *manager = NSFileManager.defaultManager;
        if (![manager createDirectoryAtPath:directory withIntermediateDirectories:YES
                                attributes:@{NSFilePosixPermissions: @0700} error:NULL]) return;
        NSString *path = [directory stringByAppendingPathComponent:@"AxsSpringTwelve-recording.log"];
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
static NSString * const AxsSpringTwelveRecordingStateChanged = @"com.axs.springtwelve.call-recording-state";
static CFStringRef AxsSpringTwelveCallStatusNotification;
static CFStringRef AxsSpringTwelveCallIdentificationNotification;

@interface AxsSpringTwelveRecordingIndicator : NSObject
@property(nonatomic, strong) UIWindow *axs_springtwelve_window;
@property(nonatomic, strong) UILabel *axs_springtwelve_label;
@property(nonatomic, strong) NSTimer *axs_springtwelve_hideTimer;
@property(nonatomic) NSUInteger axs_springtwelve_textVersion;
- (void)axs_springtwelve_showRecording;
- (void)axs_springtwelve_showSaved;
- (void)axs_springtwelve_showFailure:(NSString *)reason;
@end

@implementation AxsSpringTwelveRecordingIndicator

- (void)axs_springtwelve_ensureWindow {
    if (self.axs_springtwelve_window) return;
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
    self.axs_springtwelve_window = window;
    self.axs_springtwelve_label = label;
}

- (void)axs_springtwelve_showText:(NSString *)text color:(UIColor *)color hideAfter:(NSTimeInterval)delay {
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf axs_springtwelve_showText:text color:color hideAfter:delay]; });
        return;
    }
    [self.axs_springtwelve_hideTimer invalidate];
    [self axs_springtwelve_ensureWindow];
    NSUInteger textVersion = ++self.axs_springtwelve_textVersion;
    [self.axs_springtwelve_window.layer removeAllAnimations];
    self.axs_springtwelve_label.text = text;
    self.axs_springtwelve_label.backgroundColor = color;
    self.axs_springtwelve_window.hidden = NO;
    self.axs_springtwelve_window.alpha = 1.0;
    if (delay > 0.0) {
        __weak typeof(self) weakSelf = self;
        self.axs_springtwelve_hideTimer = [NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(__unused NSTimer *timer) {
            if (weakSelf.axs_springtwelve_textVersion != textVersion) return;
            [UIView animateWithDuration:0.25 animations:^{ weakSelf.axs_springtwelve_window.alpha = 0.0; }
                             completion:^(__unused BOOL finished) {
                if (weakSelf.axs_springtwelve_textVersion == textVersion) weakSelf.axs_springtwelve_window.hidden = YES;
            }];
        }];
    }
}

- (void)axs_springtwelve_showRecording {
    [self axs_springtwelve_showText:@"● 录音中" color:[UIColor colorWithRed:0.78 green:0.08 blue:0.08 alpha:0.94] hideAfter:0.0];
}
- (void)axs_springtwelve_showSaved {
    [self axs_springtwelve_showText:@"录音已保存" color:[UIColor colorWithRed:0.10 green:0.48 blue:0.20 alpha:0.94] hideAfter:2.5];
}
- (void)axs_springtwelve_showFailure:(NSString *)reason {
    NSString *text = reason.length ? [NSString stringWithFormat:@"录音失败：%@", reason] : @"录音失败";
    [self axs_springtwelve_showText:text color:[UIColor colorWithRed:0.72 green:0.30 blue:0.04 alpha:0.94] hideAfter:3.0];
}
@end

// Signal and waitpid share one lock, so a reaped PID can never be signalled
// after the kernel has recycled it. Escalation runs even after UI state clears.
@interface AxsSpringTwelveRecordingWorker : NSObject
@property(nonatomic) pid_t axs_springtwelve_pid;
@property(nonatomic) NSTimeInterval axs_springtwelve_stopTime;
- (void)axs_springtwelve_requestStop;
- (int)axs_springtwelve_wait:(pid_t *)result;
@end
@implementation AxsSpringTwelveRecordingWorker
- (void)axs_springtwelve_requestStop {
    @synchronized (self) {
        if (self.axs_springtwelve_pid <= 0 || self.axs_springtwelve_stopTime > 0) return;
        self.axs_springtwelve_stopTime = NSProcessInfo.processInfo.systemUptime;
        kill(self.axs_springtwelve_pid, SIGINT);
    }
}
- (int)axs_springtwelve_wait:(pid_t *)result {
    int status = 0;
    BOOL sentTerm = NO, sentKill = NO;
    for (;;) {
        @synchronized (self) {
            pid_t pid = self.axs_springtwelve_pid;
            pid_t value = waitpid(pid, &status, WNOHANG);
            if (value == pid || (value < 0 && errno != EINTR)) {
                self.axs_springtwelve_pid = 0;
                if (result) *result = value;
                return status;
            }
            NSTimeInterval age = self.axs_springtwelve_stopTime > 0 ? NSProcessInfo.processInfo.systemUptime - self.axs_springtwelve_stopTime : 0;
            if (age > 3.0 && !sentTerm) { kill(pid, SIGTERM); sentTerm = YES; }
            if (age > 5.0 && !sentKill) { kill(pid, SIGKILL); sentKill = YES; }
        }
        usleep(100000);
    }
}
@end

@interface AxsSpringTwelveCallRecorder : NSObject {
@public
    dispatch_queue_t _axs_springtwelve_queue;
    dispatch_group_t _axs_springtwelve_waitGroup;
    AxsSpringTwelveRecordingWorker *_axs_springtwelve_speakerWorker;
    AxsSpringTwelveRecordingWorker *_axs_springtwelve_micWorker;
    NSString *_axs_springtwelve_downstreamPath;
    NSString *_axs_springtwelve_upstreamPath;
    NSString *_axs_springtwelve_outputPath;
    NSUInteger _axs_springtwelve_generation;
    BOOL _axs_springtwelve_active;
    AxsSpringTwelveRecordingIndicator *_axs_springtwelve_indicator;
    CTCallCenter *_axs_springtwelve_cellularCenter;
}
+ (instancetype)axs_springtwelve_shared;
- (void)axs_springtwelve_installTelephonyObserver;
- (void)axs_springtwelve_handleCallStatus:(int)status;
- (void)axs_springtwelve_stopLockedWithReason:(NSString *)reason;
- (void)axs_springtwelve_mixLockedWithHelper:(NSString *)mixer downstream:(NSString *)downstream
                                    upstream:(NSString *)upstream output:(NSString *)output generation:(NSUInteger)generation;
- (void)axs_springtwelve_finishFailure:(NSString *)reason generation:(NSUInteger)generation;
- (void)axs_springtwelve_abortLockedWithReason:(NSString *)reason generation:(NSUInteger)generation;
@end

static void AxsSpringTwelveCallNotification(CFNotificationCenterRef center, void *observer,
                                             CFStringRef name, const void *object, CFDictionaryRef userInfo);

static void AxsSpringTwelveRecordChild(AxsSpringTwelveCallRecorder *recorder, AxsSpringTwelveRecordingWorker *worker,
                                       dispatch_group_t group, NSUInteger generation, NSString *label) {
    dispatch_group_enter(group);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        pid_t originalPID = worker.axs_springtwelve_pid;
        pid_t result = 0;
        int status = [worker axs_springtwelve_wait:&result];
        dispatch_group_leave(group);
        dispatch_async(recorder->_axs_springtwelve_queue, ^{
            if (generation != recorder->_axs_springtwelve_generation) return;
            BOOL exitedCleanly = result == originalPID && WIFEXITED(status) && WEXITSTATUS(status) == 0;
            if (!exitedCleanly || recorder->_axs_springtwelve_active) {
                AxsSpringTwelveRecordLog(@"%@ worker result=%d exit=%d signal=%d active=%d", label,
                    (int)result, WIFEXITED(status) ? WEXITSTATUS(status) : -1,
                    WIFSIGNALED(status) ? WTERMSIG(status) : 0, recorder->_axs_springtwelve_active);
                [recorder axs_springtwelve_abortLockedWithReason:@"采集进程异常" generation:generation];
            }
        });
    });
}

static NSString *AxsSpringTwelveResolveHelper(NSString *name) {
    NSString *path = axs_springtwelve_resourcePath([@"/usr/local/bin/" stringByAppendingString:name]);
    if (path.length && access(path.fileSystemRepresentation, X_OK) == 0) return path;
    return nil;
}

static BOOL AxsSpringTwelveSpawn(NSString *path, NSArray<NSString *> *arguments, pid_t *pidOut, int *errorOut) {
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
    int error = posix_spawn(&pid, path.fileSystemRepresentation, NULL, NULL, argv, NULL);
    free(argv);
    if (errorOut) *errorOut = error;
    if (error != 0) return NO;
    *pidOut = pid;
    return YES;
}

@implementation AxsSpringTwelveCallRecorder

+ (instancetype)axs_springtwelve_shared {
    static AxsSpringTwelveCallRecorder *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [self new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _axs_springtwelve_queue = dispatch_queue_create("com.axs.springtwelve.call-recording", DISPATCH_QUEUE_SERIAL);
        _axs_springtwelve_indicator = [AxsSpringTwelveRecordingIndicator new];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(axs_springtwelve_preferencesChanged:)
            name:AxsSpringTwelvePreferencesChanged object:nil];
    }
    return self;
}

- (void)axs_springtwelve_preferencesChanged:(NSNotification *)notification {
    dispatch_async(_axs_springtwelve_queue, ^{
        if (!AxsSpringTwelveOn(@"callRecordingEnabled") && self->_axs_springtwelve_active)
            [self axs_springtwelve_stopLockedWithReason:@"设置已关闭"];
    });
}

- (void)axs_springtwelve_installTelephonyObserver {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _axs_springtwelve_cellularCenter = [CTCallCenter new];
        __weak typeof(self) weakSelf = self;
        _axs_springtwelve_cellularCenter.callEventHandler = ^(CTCall *call) {
            AxsSpringTwelveCallRecorder *recorder = weakSelf;
            if (!recorder) return;
            NSString *state = call.callState;
            // No callID, phone number, address or contact details are logged.
            BOOL connected = [state isEqualToString:CTCallStateConnected];
            BOOL ended = [state isEqualToString:CTCallStateDisconnected];
            AxsSpringTwelveRecordLog(@"cellular event connected=%d ended=%d", connected, ended);
            if (connected) [recorder axs_springtwelve_handleCallStatus:1];
            else if (ended) {
                BOOL otherConnected = NO;
                for (CTCall *current in recorder->_axs_springtwelve_cellularCenter.currentCalls) {
                    if ([current.callState isEqualToString:CTCallStateConnected]) { otherConnected = YES; break; }
                }
                if (!otherConnected) [recorder axs_springtwelve_handleCallStatus:5];
            }
        };
        AxsSpringTwelveRecordLog(@"module loaded; cellular fallback installed; enabled=%d", AxsSpringTwelveOn(@"callRecordingEnabled"));
        void *handle = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY | RTLD_LOCAL);
        AxsSpringTwelveCTGetDefault getDefault = handle ? (AxsSpringTwelveCTGetDefault)dlsym(handle, "CTTelephonyCenterGetDefault") : NULL;
        AxsSpringTwelveCTAddObserver addObserver = handle ? (AxsSpringTwelveCTAddObserver)dlsym(handle, "CTTelephonyCenterAddObserver") : NULL;
        CFStringRef *statusName = handle ? (CFStringRef *)dlsym(handle, "kCTCallStatusChangeNotification") : NULL;
        CFStringRef *identificationName = handle ? (CFStringRef *)dlsym(handle, "kCTCallIdentificationChangeNotification") : NULL;
        AxsSpringTwelveCallStatusNotification = statusName ? *statusName : NULL;
        AxsSpringTwelveCallIdentificationNotification = identificationName ? *identificationName : NULL;
        if (!getDefault || !addObserver || !AxsSpringTwelveCallStatusNotification) {
            AxsSpringTwelveRecordLog(@"CoreTelephony observer unavailable");
            return;
        }
        CFNotificationCenterRef center = getDefault();
        addObserver(center, NULL, (AxsSpringTwelveCTCallback)AxsSpringTwelveCallNotification,
                    AxsSpringTwelveCallStatusNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        if (AxsSpringTwelveCallIdentificationNotification)
            addObserver(center, NULL, (AxsSpringTwelveCTCallback)AxsSpringTwelveCallNotification,
                        AxsSpringTwelveCallIdentificationNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        AxsSpringTwelveRecordLog(@"CoreTelephony observer installed");
    });
}

- (void)axs_springtwelve_handleCallStatus:(int)status {
    AxsSpringTwelveRecordLog(@"telephony status=%d", status);
    dispatch_async(_axs_springtwelve_queue, ^{
        if (status == 1) {
            [self axs_springtwelve_startLocked];
        } else if (status == 2 || status == 5) {
            // A rejected second call must not stop an already connected call.
            for (CTCall *current in self->_axs_springtwelve_cellularCenter.currentCalls) {
                if ([current.callState isEqualToString:CTCallStateConnected]) {
                    AxsSpringTwelveRecordLog(@"end deferred: cellular call still connected");
                    return;
                }
            }
            [self axs_springtwelve_stopLockedWithReason:nil];
        }
    });
}

- (void)axs_springtwelve_startLocked {
    if (_axs_springtwelve_active) return;
    if (!AxsSpringTwelveOn(@"callRecordingEnabled")) {
        AxsSpringTwelveRecordLog(@"start skipped: switch disabled");
        return;
    }
    AxsSpringTwelveRecordLog(@"start requested");
    NSString *recordHelper = AxsSpringTwelveResolveHelper(@"MUtoolRecord");
    NSString *mixerHelper = AxsSpringTwelveResolveHelper(@"AxsSpringTwelveMP3Mixer");
    if (!recordHelper || !mixerHelper) {
        AxsSpringTwelveRecordLog(@"helper missing");
        dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showFailure:@"组件缺失"]; });
        return;
    }
    NSFileManager *manager = NSFileManager.defaultManager;
    if (![manager createDirectoryAtPath:axs_springtwelve_recordingDirectory() withIntermediateDirectories:YES
                             attributes:@{NSFilePosixPermissions: @0700} error:NULL]) {
        AxsSpringTwelveRecordLog(@"unable to create recording directory");
        dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showFailure:@"目录不可写"]; });
        return;
    }
    NSString *identifier = [NSString stringWithFormat:@"AxsSpringTwelve-%@", NSUUID.UUID.UUIDString];
    // CAF is a capture intermediate, never a second user-facing recording.
    NSString *workDirectory = [axs_springtwelve_recordingDirectory() stringByAppendingPathComponent:@".work"];
    if (![manager createDirectoryAtPath:workDirectory withIntermediateDirectories:YES
                             attributes:@{NSFilePosixPermissions: @0700} error:NULL]) {
        AxsSpringTwelveRecordLog(@"unable to create recording work directory");
        dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showFailure:@"临时目录不可写"]; });
        return;
    }
    NSString *base = [workDirectory stringByAppendingPathComponent:identifier];
    _axs_springtwelve_downstreamPath = [base stringByAppendingString:@"-downstream.caf"];
    _axs_springtwelve_upstreamPath = [base stringByAppendingString:@"-upstream.caf"];
    _axs_springtwelve_outputPath = [[axs_springtwelve_recordingDirectory() stringByAppendingPathComponent:identifier]
                                  stringByAppendingString:@".mp3"];
    _axs_springtwelve_generation++;
    NSUInteger generation = _axs_springtwelve_generation;
    _axs_springtwelve_waitGroup = dispatch_group_create();
    int error = 0;
    pid_t speaker = 0, mic = 0;
    BOOL speakerOK = AxsSpringTwelveSpawn(recordHelper, @[@"speaker", _axs_springtwelve_downstreamPath], &speaker, &error);
    if (!speakerOK) {
        AxsSpringTwelveRecordLog(@"speaker helper spawn failed: %d", error);
        [self axs_springtwelve_failStartLocked];
        return;
    }
    _axs_springtwelve_speakerWorker = [AxsSpringTwelveRecordingWorker new];
    _axs_springtwelve_speakerWorker.axs_springtwelve_pid = speaker;
    AxsSpringTwelveRecordChild(self, _axs_springtwelve_speakerWorker, _axs_springtwelve_waitGroup, generation, @"speaker");
    BOOL micOK = AxsSpringTwelveSpawn(recordHelper, @[@"mic", _axs_springtwelve_upstreamPath], &mic, &error);
    if (!micOK) {
        [_axs_springtwelve_speakerWorker axs_springtwelve_requestStop];
        AxsSpringTwelveRecordLog(@"mic helper spawn failed: %d", error);
        [self axs_springtwelve_failStartLocked];
        return;
    }
    _axs_springtwelve_micWorker = [AxsSpringTwelveRecordingWorker new];
    _axs_springtwelve_micWorker.axs_springtwelve_pid = mic;
    _axs_springtwelve_active = YES;
    AxsSpringTwelveRecordChild(self, _axs_springtwelve_micWorker, _axs_springtwelve_waitGroup, generation, @"mic");
    AxsSpringTwelveRecordLog(@"capture workers spawned");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_axs_springtwelve_indicator axs_springtwelve_showText:@"正在启动录音" color:[UIColor colorWithWhite:0.12 alpha:0.94] hideAfter:0.0];
    });
    // Spawn success alone is not evidence of audio capture. Require data in
    // both channel files before showing the recording indicator.
    for (NSUInteger attempt = 1; attempt <= 3; attempt++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(attempt * 2 * NSEC_PER_SEC)), _axs_springtwelve_queue, ^{
            if (generation != self->_axs_springtwelve_generation || !self->_axs_springtwelve_active) return;
            struct stat down = {}, up = {};
            BOOL hasData = stat(self->_axs_springtwelve_downstreamPath.fileSystemRepresentation, &down) == 0 &&
                           stat(self->_axs_springtwelve_upstreamPath.fileSystemRepresentation, &up) == 0 &&
                           down.st_size > 128 && up.st_size > 128;
            AxsSpringTwelveRecordLog(@"capture probe=%lu downBytes=%lld upBytes=%lld", (unsigned long)attempt,
                                    (long long)down.st_size, (long long)up.st_size);
            if (hasData) {
                dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showRecording]; });
            } else if (attempt == 3) {
                [self axs_springtwelve_abortLockedWithReason:@"未采集到音频" generation:generation];
            }
        });
    }
}

- (void)axs_springtwelve_failStartLocked {
    // Wait for any partially started capture worker before removing its files.
    dispatch_group_t group = _axs_springtwelve_waitGroup;
    NSString *downstream = [_axs_springtwelve_downstreamPath copy];
    NSString *upstream = [_axs_springtwelve_upstreamPath copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (group && dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) != 0) return;
        if (downstream.length) unlink(downstream.fileSystemRepresentation);
        if (upstream.length) unlink(upstream.fileSystemRepresentation);
    });
    _axs_springtwelve_active = NO;
    _axs_springtwelve_speakerWorker = nil;
    _axs_springtwelve_micWorker = nil;
    _axs_springtwelve_waitGroup = nil;
    _axs_springtwelve_downstreamPath = nil;
    _axs_springtwelve_upstreamPath = nil;
    _axs_springtwelve_outputPath = nil;
    dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showFailure:@"无法启动"]; });
}

- (void)axs_springtwelve_stopLockedWithReason:(NSString *)reason {
    if (!_axs_springtwelve_active) return;
    _axs_springtwelve_active = NO;
    AxsSpringTwelveRecordingWorker *speaker = _axs_springtwelve_speakerWorker;
    AxsSpringTwelveRecordingWorker *mic = _axs_springtwelve_micWorker;
    _axs_springtwelve_speakerWorker = nil;
    _axs_springtwelve_micWorker = nil;
    NSString *downstream = [_axs_springtwelve_downstreamPath copy];
    NSString *upstream = [_axs_springtwelve_upstreamPath copy];
    NSString *output = [_axs_springtwelve_outputPath copy];
    NSString *mixer = AxsSpringTwelveResolveHelper(@"AxsSpringTwelveMP3Mixer");
    dispatch_group_t group = _axs_springtwelve_waitGroup;
    NSUInteger generation = _axs_springtwelve_generation;
    [speaker axs_springtwelve_requestStop];
    [mic axs_springtwelve_requestStop];
    AxsSpringTwelveRecordLog(@"recording stopped%@", reason.length ? [@" (" stringByAppendingFormat:@"%@)", reason] : @"");
    dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showText:@"正在整理录音" color:[UIColor colorWithWhite:0.12 alpha:0.94] hideAfter:0.0]; });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        long waitResult = group ? dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) : 0;
        if (waitResult != 0) {
            // The encoder publishes only after success; do not remove a final-name collision.
            AxsSpringTwelveRecordLog(@"capture workers did not stop in time");
            dispatch_async(self->_axs_springtwelve_queue, ^{
                [self axs_springtwelve_finishFailure:@"结束超时" generation:generation];
            });
            return;
        }
        dispatch_async(self->_axs_springtwelve_queue, ^{
            [self axs_springtwelve_mixLockedWithHelper:mixer downstream:downstream upstream:upstream output:output generation:generation];
        });
    });
}

- (void)axs_springtwelve_mixLockedWithHelper:(NSString *)mixer downstream:(NSString *)downstream
                                    upstream:(NSString *)upstream output:(NSString *)output generation:(NSUInteger)generation {
    if (!mixer.length || !downstream.length || !upstream.length || !output.length) {
        [self axs_springtwelve_finishFailure:@"参数无效" generation:generation];
        return;
    }
    int error = 0;
    pid_t mixerPID = 0;
    if (!AxsSpringTwelveSpawn(mixer, @[downstream, upstream, output], &mixerPID, &error)) {
        AxsSpringTwelveRecordLog(@"mixer spawn failed: %d", error);
        [self axs_springtwelve_finishFailure:@"合并失败" generation:generation];
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int status = 0;
        pid_t result;
        do { result = waitpid(mixerPID, &status, 0); } while (result < 0 && errno == EINTR);
        dispatch_async(self->_axs_springtwelve_queue, ^{
            struct stat info = {};
            BOOL valid = result == mixerPID && WIFEXITED(status) && WEXITSTATUS(status) == 0 &&
                         stat(output.fileSystemRepresentation, &info) == 0 && info.st_size > 0;
            if (valid) {
                AVAudioFile *audio = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:output] error:NULL];
                valid = audio && audio.length > 0 && audio.processingFormat.sampleRate > 0;
            }
            AxsSpringTwelveRecordLog(@"mixer result=%d exit=%d signal=%d valid=%d", (int)result,
                WIFEXITED(status) ? WEXITSTATUS(status) : -1, WIFSIGNALED(status) ? WTERMSIG(status) : 0, valid);
            if (valid) {
                unlink(downstream.fileSystemRepresentation);
                unlink(upstream.fileSystemRepresentation);
                AxsSpringTwelveRecordLog(@"recording saved");
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (generation == self->_axs_springtwelve_generation && !self->_axs_springtwelve_active)
                        [self->_axs_springtwelve_indicator axs_springtwelve_showSaved];
                    [[NSNotificationCenter defaultCenter] postNotificationName:AxsSpringTwelveRecordingStateChanged object:nil];
                });
            } else {
                // Failure retains both recovery inputs and any pre-existing final file.
                AxsSpringTwelveRecordLog(@"mixer failed; CAF inputs retained in .work");
                [self axs_springtwelve_finishFailure:@"未生成有效文件" generation:generation];
            }
        });
    });
}

- (void)axs_springtwelve_abortLockedWithReason:(NSString *)reason generation:(NSUInteger)generation {
    if (generation != _axs_springtwelve_generation || !_axs_springtwelve_active) return;
    _axs_springtwelve_active = NO;
    _axs_springtwelve_generation++;
    AxsSpringTwelveRecordingWorker *speaker = _axs_springtwelve_speakerWorker;
    AxsSpringTwelveRecordingWorker *mic = _axs_springtwelve_micWorker;
    _axs_springtwelve_speakerWorker = nil;
    _axs_springtwelve_micWorker = nil;
    dispatch_group_t group = _axs_springtwelve_waitGroup;
    _axs_springtwelve_waitGroup = nil;
    NSString *downstream = [_axs_springtwelve_downstreamPath copy];
    NSString *upstream = [_axs_springtwelve_upstreamPath copy];
    [speaker axs_springtwelve_requestStop];
    [mic axs_springtwelve_requestStop];
    AxsSpringTwelveRecordLog(@"capture aborted: %@", reason);
    dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showFailure:reason]; });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (group && dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) != 0) return;
        // Keep non-empty failed capture inputs available for recovery, never list them.
        struct stat info = {};
        for (NSString *path in @[downstream ?: @"", upstream ?: @""]) {
            if (path.length && stat(path.fileSystemRepresentation, &info) == 0 && info.st_size <= 128)
                unlink(path.fileSystemRepresentation);
        }
        // No encoder ran on this abort path, so there is no final output to remove.
    });
}

- (void)axs_springtwelve_finishFailure:(NSString *)reason generation:(NSUInteger)generation {
    if (generation == _axs_springtwelve_generation)
        dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showFailure:reason]; });
}

@end

static void AxsSpringTwelveCallNotification(CFNotificationCenterRef center, void *observer,
                                             CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (!userInfo || !AxsSpringTwelveCallStatusNotification ||
        !CFEqual(name, AxsSpringTwelveCallStatusNotification)) return;
    CFTypeRef value = CFDictionaryGetValue(userInfo, CFSTR("kCTCallStatus"));
    if (!value) return;
    int status = [(__bridge id)value intValue];
    [[AxsSpringTwelveCallRecorder axs_springtwelve_shared] axs_springtwelve_handleCallStatus:status];
}

%ctor {
    @autoreleasepool {
        if ([NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"])
            dispatch_async(dispatch_get_main_queue(), ^{
                [[AxsSpringTwelveCallRecorder axs_springtwelve_shared] axs_springtwelve_installTelephonyObserver];
            });
    }
}
#pragma clang diagnostic pop
