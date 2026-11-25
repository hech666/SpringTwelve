#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
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

// The two helper executables are bundled from the audited MUtool build. This
// coordinator only owns lifecycle and files; audio capture remains in MUtool.

typedef void (*AxsSpringTwelveCTCallback)(CFNotificationCenterRef, void *, CFStringRef, const void *, CFDictionaryRef);
typedef CFNotificationCenterRef (*AxsSpringTwelveCTGetDefault)(void);
typedef void (*AxsSpringTwelveCTAddObserver)(CFNotificationCenterRef, const void *, AxsSpringTwelveCTCallback,
                                               CFStringRef, const void *, CFNotificationSuspensionBehavior);

static NSString * const AxsSpringTwelveRecordingDirectory = @"/var/mobile/Documents/CallRecordings";
extern char **environ;
static NSString * const AxsSpringTwelveRecordingStateChanged = @"com.axs.springtwelve.call-recording-state";
static CFStringRef AxsSpringTwelveCallStatusNotification;
static CFStringRef AxsSpringTwelveCallIdentificationNotification;

@interface AxsSpringTwelveRecordingIndicator : NSObject
@property(nonatomic, strong) UIWindow *axs_springtwelve_window;
@property(nonatomic, strong) UILabel *axs_springtwelve_label;
@property(nonatomic, strong) NSTimer *axs_springtwelve_hideTimer;
- (void)axs_springtwelve_showRecording;
- (void)axs_springtwelve_showSaved;
- (void)axs_springtwelve_showFailure:(NSString *)reason;
@end

@implementation AxsSpringTwelveRecordingIndicator

- (void)axs_springtwelve_ensureWindow {
    if (self.axs_springtwelve_window) return;
    CGRect screen = UIScreen.mainScreen.bounds;
    CGFloat width = MIN(142.0, MAX(116.0, screen.size.width - 24.0));
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(screen.size.width - width - 8.0, 5.0, width, 30.0)];
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
    self.axs_springtwelve_label.text = text;
    self.axs_springtwelve_label.backgroundColor = color;
    self.axs_springtwelve_window.hidden = NO;
    self.axs_springtwelve_window.alpha = 1.0;
    if (delay > 0.0) {
        __weak typeof(self) weakSelf = self;
        self.axs_springtwelve_hideTimer = [NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(__unused NSTimer *timer) {
            [UIView animateWithDuration:0.25 animations:^{ weakSelf.axs_springtwelve_window.alpha = 0.0; }
                             completion:^(__unused BOOL finished) { weakSelf.axs_springtwelve_window.hidden = YES; }];
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

@interface AxsSpringTwelveCallRecorder : NSObject {
@public
    dispatch_queue_t _axs_springtwelve_queue;
    dispatch_group_t _axs_springtwelve_waitGroup;
    pid_t _axs_springtwelve_speakerPID;
    pid_t _axs_springtwelve_micPID;
    NSString *_axs_springtwelve_downstreamPath;
    NSString *_axs_springtwelve_upstreamPath;
    NSString *_axs_springtwelve_outputPath;
    NSUInteger _axs_springtwelve_generation;
    BOOL _axs_springtwelve_active;
    AxsSpringTwelveRecordingIndicator *_axs_springtwelve_indicator;
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

static void AxsSpringTwelveRecordChild(AxsSpringTwelveCallRecorder *recorder, pid_t pid,
                                       dispatch_group_t group, NSUInteger generation, NSString *label) {
    dispatch_group_enter(group);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int status = 0;
        pid_t result;
        do { result = waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
        dispatch_group_leave(group);
        dispatch_async(recorder->_axs_springtwelve_queue, ^{
            if (generation != recorder->_axs_springtwelve_generation) return;
            if (pid == recorder->_axs_springtwelve_speakerPID) recorder->_axs_springtwelve_speakerPID = 0;
            if (pid == recorder->_axs_springtwelve_micPID) recorder->_axs_springtwelve_micPID = 0;
            BOOL exitedCleanly = result == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0;
            if (!exitedCleanly) {
                NSLog(@"[SpringTwelve:Record] %@ helper exited unexpectedly", label);
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
    int error = posix_spawn(&pid, path.fileSystemRepresentation, NULL, NULL, argv, environ);
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
        void *handle = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY | RTLD_LOCAL);
        AxsSpringTwelveCTGetDefault getDefault = handle ? (AxsSpringTwelveCTGetDefault)dlsym(handle, "CTTelephonyCenterGetDefault") : NULL;
        AxsSpringTwelveCTAddObserver addObserver = handle ? (AxsSpringTwelveCTAddObserver)dlsym(handle, "CTTelephonyCenterAddObserver") : NULL;
        CFStringRef *statusName = handle ? (CFStringRef *)dlsym(handle, "kCTCallStatusChangeNotification") : NULL;
        CFStringRef *identificationName = handle ? (CFStringRef *)dlsym(handle, "kCTCallIdentificationChangeNotification") : NULL;
        AxsSpringTwelveCallStatusNotification = statusName ? *statusName : NULL;
        AxsSpringTwelveCallIdentificationNotification = identificationName ? *identificationName : NULL;
        if (!getDefault || !addObserver || !AxsSpringTwelveCallStatusNotification) {
            NSLog(@"[SpringTwelve:Record] CoreTelephony observer unavailable");
            return;
        }
        CFNotificationCenterRef center = getDefault();
        addObserver(center, NULL, (AxsSpringTwelveCTCallback)AxsSpringTwelveCallNotification,
                    AxsSpringTwelveCallStatusNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        if (AxsSpringTwelveCallIdentificationNotification)
            addObserver(center, NULL, (AxsSpringTwelveCTCallback)AxsSpringTwelveCallNotification,
                        AxsSpringTwelveCallIdentificationNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        NSLog(@"[SpringTwelve:Record] CoreTelephony observer installed");
    });
}

- (void)axs_springtwelve_handleCallStatus:(int)status {
    dispatch_async(_axs_springtwelve_queue, ^{
        if (status == 1) {
            [self axs_springtwelve_startLocked];
        } else if (status == 2 || status == 5) {
            [self axs_springtwelve_stopLockedWithReason:nil];
        }
    });
}

- (void)axs_springtwelve_startLocked {
    if (_axs_springtwelve_active || !AxsSpringTwelveOn(@"callRecordingEnabled")) return;
    NSString *recordHelper = AxsSpringTwelveResolveHelper(@"MUtoolRecord");
    NSString *mixerHelper = AxsSpringTwelveResolveHelper(@"MUtoolMixer");
    if (!recordHelper || !mixerHelper) {
        NSLog(@"[SpringTwelve:Record] helper missing");
        dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showFailure:@"组件缺失"]; });
        return;
    }
    NSFileManager *manager = NSFileManager.defaultManager;
    if (![manager createDirectoryAtPath:AxsSpringTwelveRecordingDirectory withIntermediateDirectories:YES
                             attributes:@{NSFilePosixPermissions: @0700} error:NULL]) {
        NSLog(@"[SpringTwelve:Record] unable to create recording directory");
        dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showFailure:@"目录不可写"]; });
        return;
    }
    NSString *base = [AxsSpringTwelveRecordingDirectory stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"AxsSpringTwelve-%@", NSUUID.UUID.UUIDString]];
    _axs_springtwelve_downstreamPath = [base stringByAppendingString:@"-downstream.caf"];
    _axs_springtwelve_upstreamPath = [base stringByAppendingString:@"-upstream.caf"];
    _axs_springtwelve_outputPath = [base stringByAppendingString:@".m4a"];
    _axs_springtwelve_generation++;
    NSUInteger generation = _axs_springtwelve_generation;
    _axs_springtwelve_waitGroup = dispatch_group_create();
    int error = 0;
    pid_t speaker = 0, mic = 0;
    BOOL speakerOK = AxsSpringTwelveSpawn(recordHelper, @[@"speaker", _axs_springtwelve_downstreamPath], &speaker, &error);
    if (!speakerOK) {
        NSLog(@"[SpringTwelve:Record] speaker helper spawn failed: %d", error);
        [self axs_springtwelve_failStartLocked];
        return;
    }
    BOOL micOK = AxsSpringTwelveSpawn(recordHelper, @[@"mic", _axs_springtwelve_upstreamPath], &mic, &error);
    if (!micOK) {
        kill(speaker, SIGINT);
        NSLog(@"[SpringTwelve:Record] mic helper spawn failed: %d", error);
        [self axs_springtwelve_failStartLocked];
        return;
    }
    _axs_springtwelve_speakerPID = speaker;
    _axs_springtwelve_micPID = mic;
    _axs_springtwelve_active = YES;
    AxsSpringTwelveRecordChild(self, speaker, _axs_springtwelve_waitGroup, generation, @"speaker");
    AxsSpringTwelveRecordChild(self, mic, _axs_springtwelve_waitGroup, generation, @"mic");
    NSLog(@"[SpringTwelve:Record] recording started");
    dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showRecording]; });
}

- (void)axs_springtwelve_failStartLocked {
    _axs_springtwelve_active = NO;
    _axs_springtwelve_speakerPID = 0;
    _axs_springtwelve_micPID = 0;
    _axs_springtwelve_waitGroup = nil;
    _axs_springtwelve_downstreamPath = nil;
    _axs_springtwelve_upstreamPath = nil;
    _axs_springtwelve_outputPath = nil;
    dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showFailure:@"无法启动"]; });
}

- (void)axs_springtwelve_stopLockedWithReason:(NSString *)reason {
    if (!_axs_springtwelve_active) return;
    _axs_springtwelve_active = NO;
    pid_t speaker = _axs_springtwelve_speakerPID;
    pid_t mic = _axs_springtwelve_micPID;
    _axs_springtwelve_speakerPID = 0;
    _axs_springtwelve_micPID = 0;
    NSString *downstream = [_axs_springtwelve_downstreamPath copy];
    NSString *upstream = [_axs_springtwelve_upstreamPath copy];
    NSString *output = [_axs_springtwelve_outputPath copy];
    NSString *mixer = AxsSpringTwelveResolveHelper(@"MUtoolMixer");
    dispatch_group_t group = _axs_springtwelve_waitGroup;
    NSUInteger generation = _axs_springtwelve_generation;
    if (speaker > 0) kill(speaker, SIGINT);
    if (mic > 0) kill(mic, SIGINT);
    NSLog(@"[SpringTwelve:Record] recording stopped%@", reason.length ? [@" (" stringByAppendingFormat:@"%@)", reason] : @"");
    dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showText:@"正在整理录音" color:[UIColor colorWithWhite:0.12 alpha:0.94] hideAfter:0.0]; });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        long waitResult = group ? dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) : 0;
        if (waitResult != 0) {
            if (output.length) unlink(output.fileSystemRepresentation);
            NSLog(@"[SpringTwelve:Record] capture workers did not stop in time");
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
        NSLog(@"[SpringTwelve:Record] mixer spawn failed: %d", error);
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
                unlink(downstream.fileSystemRepresentation);
                unlink(upstream.fileSystemRepresentation);
                NSLog(@"[SpringTwelve:Record] recording saved");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->_axs_springtwelve_indicator axs_springtwelve_showSaved];
                    [[NSNotificationCenter defaultCenter] postNotificationName:AxsSpringTwelveRecordingStateChanged object:nil];
                });
            } else {
                unlink(output.fileSystemRepresentation);
                NSLog(@"[SpringTwelve:Record] mixer produced no valid output");
                [self axs_springtwelve_finishFailure:@"未生成有效文件" generation:generation];
            }
        });
    });
}

- (void)axs_springtwelve_abortLockedWithReason:(NSString *)reason generation:(NSUInteger)generation {
    if (generation != _axs_springtwelve_generation || !_axs_springtwelve_active) return;
    _axs_springtwelve_active = NO;
    _axs_springtwelve_generation++;
    pid_t speaker = _axs_springtwelve_speakerPID;
    pid_t mic = _axs_springtwelve_micPID;
    _axs_springtwelve_speakerPID = 0;
    _axs_springtwelve_micPID = 0;
    dispatch_group_t group = _axs_springtwelve_waitGroup;
    _axs_springtwelve_waitGroup = nil;
    NSString *downstream = [_axs_springtwelve_downstreamPath copy];
    NSString *upstream = [_axs_springtwelve_upstreamPath copy];
    NSString *output = [_axs_springtwelve_outputPath copy];
    if (speaker > 0) kill(speaker, SIGINT);
    if (mic > 0) kill(mic, SIGINT);
    NSLog(@"[SpringTwelve:Record] capture aborted: %@", reason);
    dispatch_async(dispatch_get_main_queue(), ^{ [self->_axs_springtwelve_indicator axs_springtwelve_showFailure:reason]; });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (group) dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));
        if (downstream.length) unlink(downstream.fileSystemRepresentation);
        if (upstream.length) unlink(upstream.fileSystemRepresentation);
        if (output.length) unlink(output.fileSystemRepresentation);
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
            [[AxsSpringTwelveCallRecorder axs_springtwelve_shared] axs_springtwelve_installTelephonyObserver];
    }
}
