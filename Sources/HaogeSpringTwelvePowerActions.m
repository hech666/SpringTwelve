#import "HaogeSpringTwelvePowerActions.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <signal.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

NSString *haoge_springtwelve_powerActionTitle(HaogeSpringTwelvePowerAction action) {
    switch (action) {
        case HaogeSpringTwelvePowerActionQuickRespring: return @"注销";
        case HaogeSpringTwelvePowerActionForceRespring: return @"强制注销";
        case HaogeSpringTwelvePowerActionRespring: return @"重启桌面";
        case HaogeSpringTwelvePowerActionUserspaceReboot: return @"重启用户空间";
        case HaogeSpringTwelvePowerActionReboot: return @"重启设备";
        case HaogeSpringTwelvePowerActionShutdown: return @"关机";
    }
    return @"未知操作";
}

NSString *haoge_springtwelve_powerActionWarning(HaogeSpringTwelvePowerAction action) {
    switch (action) {
        case HaogeSpringTwelvePowerActionQuickRespring:
            return @"将结束桌面进程（SIGTERM 15），由系统重新拉起桌面。未保存的界面状态可能丢失。是否继续？";
        case HaogeSpringTwelvePowerActionForceRespring:
            return @"将强制结束桌面进程（SIGKILL 9），由系统重新拉起桌面。未保存的界面状态可能丢失。是否继续？";
        case HaogeSpringTwelvePowerActionRespring:
            return @"将通过系统服务重新启动桌面，当前界面会关闭。请先结束通话并保存正在进行的操作。是否继续？";
        case HaogeSpringTwelvePowerActionUserspaceReboot:
            return @"将重新启动用户空间服务，所有应用与当前通话会中断。请先保存数据；不同越狱环境的恢复情况可能不同。是否继续？";
        case HaogeSpringTwelvePowerActionReboot:
            return @"将重新启动整台设备，所有应用与当前通话会中断，开机后可能需要重新激活越狱。请先保存数据。是否继续？";
        case HaogeSpringTwelvePowerActionShutdown:
            return @"将关闭整台设备，所有应用与当前通话会中断，需要手动开机，开机后可能需要重新激活越狱。请先保存数据。是否继续？";
    }
    return @"未知操作，无法执行。";
}

#import "HaogeSpringTwelvePaths.h"
#import <sys/stat.h>
#import <sys/wait.h>
#import <spawn.h>

static BOOL HaogeSpringTwelvePowerHelperInFlight;

static const char *haoge_springtwelve_powerType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL haoge_springtwelve_powerSignature(id target, SEL selector,
                                          char result, NSArray<NSString *> *arguments) {
    if (!target || ![target respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != arguments.count + 2 ||
        haoge_springtwelve_powerType(signature.methodReturnType)[0] != result) return NO;
    for (NSUInteger index = 0; index < arguments.count; index++) {
        const char *actual = haoge_springtwelve_powerType([signature getArgumentTypeAtIndex:index + 2]);
        const char *expected = arguments[index].UTF8String;
        if (expected[0] == '@') {
            if (actual[0] != '@') return NO;
        } else if (strcmp(actual, expected)) return NO;
    }
    return YES;
}

static id haoge_springtwelve_powerService(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW | RTLD_LOCAL);
        dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW | RTLD_LOCAL);
    });
    Class cls = NSClassFromString(@"FBSSystemService");
    SEL selector = NSSelectorFromString(@"sharedService");
    if (!haoge_springtwelve_powerSignature(cls, selector, '@', @[])) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, selector);
}

static BOOL haoge_springtwelve_powerIsSpringBoard(void) {
    return [NSThread isMainThread] &&
        [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] &&
        [NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"];
}

static NSString *haoge_springtwelve_powerHelperPath(void) {
    return haoge_springtwelve_resourcePath(@"/usr/local/libexec/HaogeSpringTwelvePowerHelper");
}

BOOL haoge_springtwelve_powerActionAvailable(HaogeSpringTwelvePowerAction action) {
    if (!haoge_springtwelve_powerIsSpringBoard()) return NO;
    @try {
        switch (action) {
            case HaogeSpringTwelvePowerActionQuickRespring:
            case HaogeSpringTwelvePowerActionForceRespring: return YES;
            case HaogeSpringTwelvePowerActionUserspaceReboot: {
                struct stat info;
                NSString *path = haoge_springtwelve_powerHelperPath();
                return !HaogeSpringTwelvePowerHelperInFlight &&
                    lstat(path.fileSystemRepresentation, &info) == 0 &&
                    S_ISREG(info.st_mode) && info.st_uid == 0 &&
                    (info.st_mode & S_ISUID) && !(info.st_mode & (S_IWGRP | S_IWOTH)) &&
                    access(path.fileSystemRepresentation, X_OK) == 0;
            }
            case HaogeSpringTwelvePowerActionRespring: {
                id service = haoge_springtwelve_powerService();
                return haoge_springtwelve_powerSignature(service, NSSelectorFromString(@"sendActions:withResult:"), 'v', @[@"@", @"@"]) &&
                    haoge_springtwelve_powerSignature(NSClassFromString(@"SBSRelaunchAction"),
                        NSSelectorFromString(@"actionWithReason:options:targetURL:"), '@', @[@"@", @(@encode(NSUInteger)), @"@"]);
            }
            case HaogeSpringTwelvePowerActionReboot:
                return haoge_springtwelve_powerSignature(haoge_springtwelve_powerService(), NSSelectorFromString(@"reboot"), 'v', @[]);
            case HaogeSpringTwelvePowerActionShutdown:
                return haoge_springtwelve_powerSignature(haoge_springtwelve_powerService(), NSSelectorFromString(@"shutdown"), 'v', @[]);
        }
    } @catch (__unused NSException *exception) {}
    return NO;
}

static void haoge_springtwelve_powerDeliver(void (^completion)(NSString *), NSString *error) {
    if (!completion) return;
    if (NSThread.isMainThread) completion(error);
    else dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
}

static NSString *haoge_springtwelve_powerHelperError(int code) {
    switch (code) {
        case 64: return @"电源工具拒绝了无效参数，未执行任何操作。";
        case 77: return @"电源工具的提权或桌面进程身份校验失败，请重新安装此包后重试。";
        case 78: return @"当前越狱环境未允许电源工具取得所需权限。";
        case 69: return @"当前系统没有提供用户空间重启接口。";
        case 70: return @"系统拒绝了用户空间重启请求，请导出功能诊断。";
        default: return [NSString stringWithFormat:@"电源工具异常退出（状态 %d），未尝试其他操作。", code];
    }
}

#import <fcntl.h>

static void haoge_springtwelve_powerSpawnUserspace(void (^completion)(NSString *)) {
    HaogeSpringTwelvePowerHelperInFlight = YES;
    NSString *path = haoge_springtwelve_powerHelperPath();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            posix_spawn_file_actions_t actions;
            posix_spawnattr_t attributes;
            int error = posix_spawn_file_actions_init(&actions);
            BOOL actionsReady = error == 0, attributesReady = NO;
            if (!error) { error = posix_spawnattr_init(&attributes); attributesReady = error == 0; }
            sigset_t mask;
            sigemptyset(&mask);
            if (!error) error = posix_spawnattr_setsigmask(&attributes, &mask);
            if (!error) error = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK);
            if (!error) error = posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
            if (!error) error = posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
            if (!error) error = posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
            char *argv[] = {(char *)path.fileSystemRepresentation, (char *)"userspace-reboot", NULL};
            char *environment[] = {(char *)"PATH=/usr/bin:/bin:/usr/sbin:/sbin", (char *)"LANG=C", NULL};
            pid_t pid = -1;
            if (!error) error = posix_spawn(&pid, argv[0], &actions, &attributes, argv, environment);
            if (attributesReady) posix_spawnattr_destroy(&attributes);
            if (actionsReady) posix_spawn_file_actions_destroy(&actions);
            NSString *failure = nil;
            BOOL timedOut = NO;
            if (error) {
                failure = [NSString stringWithFormat:@"无法启动电源工具（错误 %d），请检查安装与签名。", error];
            } else {
                int status = 0;
                pid_t result = 0;
                NSTimeInterval deadline = NSDate.timeIntervalSinceReferenceDate + 10.0;
                do {
                    result = waitpid(pid, &status, WNOHANG);
                    if (result == pid || (result == -1 && errno != EINTR)) break;
                    if (NSDate.timeIntervalSinceReferenceDate >= deadline) { timedOut = YES; break; }
                    usleep(100000);
                } while (YES);
                if (timedOut) failure = @"用户空间重启请求尚未返回，暂不允许重复提交；未改为其他重启方式。";
                else if (result == -1) failure = @"无法读取电源工具的退出状态，未尝试其他操作。";
                else if (!WIFEXITED(status)) failure = @"电源工具被系统终止，请检查越狱签名环境。";
                else if (WEXITSTATUS(status) != 0) failure = haoge_springtwelve_powerHelperError(WEXITSTATUS(status));
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!timedOut) HaogeSpringTwelvePowerHelperInFlight = NO;
                haoge_springtwelve_powerDeliver(completion, failure);
            });
            if (timedOut) {
                // Keep ownership and reap even after reporting a bounded timeout.
                // Never submit a second request while this helper is outstanding.
                int status;
                while (waitpid(pid, &status, 0) == -1 && errno == EINTR) {}
                dispatch_async(dispatch_get_main_queue(), ^{ HaogeSpringTwelvePowerHelperInFlight = NO; });
            }
        }
    });
}

void haoge_springtwelve_powerActionRequest(HaogeSpringTwelvePowerAction action,
                                        void (^completion)(NSString *error)) {
    if (!haoge_springtwelve_powerIsSpringBoard() ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        haoge_springtwelve_powerDeliver(completion, @"当前不在前台桌面，已取消电源操作。"); return;
    }
    if (!haoge_springtwelve_powerActionAvailable(action)) {
        haoge_springtwelve_powerDeliver(completion, @"此操作所需的系统接口或已授权电源工具当前不可用。"); return;
    }
    @try {
        switch (action) {
            case HaogeSpringTwelvePowerActionQuickRespring:
            case HaogeSpringTwelvePowerActionForceRespring: {
                int signal = action == HaogeSpringTwelvePowerActionQuickRespring ? SIGTERM : SIGKILL;
                int result = kill(getpid(), signal);
                haoge_springtwelve_powerDeliver(completion, result == -1 ?
                    [NSString stringWithFormat:@"信号请求失败（errno %d），未尝试其他操作。", errno] : nil);
                return;
            }
            case HaogeSpringTwelvePowerActionUserspaceReboot:
                haoge_springtwelve_powerSpawnUserspace(completion); return;
            case HaogeSpringTwelvePowerActionRespring: {
                Class actionClass = NSClassFromString(@"SBSRelaunchAction");
                SEL create = NSSelectorFromString(@"actionWithReason:options:targetURL:");
                // Cephei's actual fade-to-black relaunch request, not guessed flags.
                id request = ((id (*)(id, SEL, NSString *, NSUInteger, NSURL *))objc_msgSend)
                    (actionClass, create, @"RestartRenderServer", (NSUInteger)4, nil);
                if (!request) { haoge_springtwelve_powerDeliver(completion, @"系统未能创建重启桌面请求。"); return; }
                void (^result)(NSError *) = ^(NSError *failure) {
                    haoge_springtwelve_powerDeliver(completion, failure ?
                        [NSString stringWithFormat:@"系统拒绝重启桌面请求（错误 %ld）。", (long)failure.code] : nil);
                };
                ((void (*)(id, SEL, NSSet *, void (^)(NSError *)))objc_msgSend)
                    (haoge_springtwelve_powerService(), NSSelectorFromString(@"sendActions:withResult:"), [NSSet setWithObject:request], result);
                return;
            }
            case HaogeSpringTwelvePowerActionReboot:
            case HaogeSpringTwelvePowerActionShutdown: {
                SEL selector = NSSelectorFromString(action == HaogeSpringTwelvePowerActionReboot ? @"reboot" : @"shutdown");
                ((void (*)(id, SEL))objc_msgSend)(haoge_springtwelve_powerService(), selector);
                haoge_springtwelve_powerDeliver(completion, nil); return;
            }
        }
    } @catch (__unused NSException *exception) {
        haoge_springtwelve_powerDeliver(completion, @"调用系统电源服务时发生异常，未尝试其他操作。"); return;
    }
    haoge_springtwelve_powerDeliver(completion, @"未知电源操作，已拒绝执行。");
}
