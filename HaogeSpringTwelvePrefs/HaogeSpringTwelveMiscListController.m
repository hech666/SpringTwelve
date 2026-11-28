#import "HaogeSpringTwelveRootListController.h"
#import "HaogeSpringTwelveMotionXActivation.h"
#import "HaogeSpringTwelvePaths.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <fcntl.h>
#import <signal.h>
#import <errno.h>
#import <unistd.h>

static BOOL HaogeSpringTwelveMotionXRestartInFlight;

// Existing setuid helper, fixed action and sanitized environment. No shell.
static int haoge_springtwelve_restartMotionXServices(void) {
    NSString *path = haoge_springtwelve_resourcePath(@"/usr/local/libexec/HaogeSpringTwelvePowerHelper");
    struct stat info;
    if (lstat(path.fileSystemRepresentation, &info) != 0 || !S_ISREG(info.st_mode) ||
        info.st_uid != 0 || !(info.st_mode & S_ISUID) || (info.st_mode & (S_IWGRP | S_IWOTH)) ||
        access(path.fileSystemRepresentation, X_OK) != 0) return 77;
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    int error = posix_spawn_file_actions_init(&actions);
    BOOL actionsReady = !error, attributesReady = NO;
    if (!error) { error = posix_spawnattr_init(&attributes); attributesReady = !error; }
    sigset_t mask;
    sigemptyset(&mask);
    if (!error) error = posix_spawnattr_setsigmask(&attributes, &mask);
    if (!error) error = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK);
    if (!error) error = posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    if (!error) error = posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    if (!error) error = posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    char *argv[] = {(char *)path.fileSystemRepresentation, (char *)"restart-motionx-services", NULL};
    char *environment[] = {(char *)"PATH=/usr/bin:/bin:/usr/sbin:/sbin", (char *)"LANG=C", NULL};
    pid_t pid = -1;
    if (!error) error = posix_spawn(&pid, argv[0], &actions, &attributes, argv, environment);
    if (attributesReady) posix_spawnattr_destroy(&attributes);
    if (actionsReady) posix_spawn_file_actions_destroy(&actions);
    if (error) return error;
    int status = 0;
    pid_t result;
    do { result = waitpid(pid, &status, 0); } while (result == -1 && errno == EINTR);
    return result != pid || !WIFEXITED(status) ? 71 : WEXITSTATUS(status);
}

@interface HaogeSpringTwelveMiscListController : HaogeSpringTwelveRootListController
@end

@implementation HaogeSpringTwelveMiscListController
- (NSString *)haoge_springtwelve_specifierPlistName {
    return @"HaogeSpringTwelveMisc";
}

- (void)haoge_springtwelve_didSavePreference:(NSString *)key
                            previousValue:(id)previousValue currentValue:(id)currentValue {
    if (!haoge_springtwelve_motionXNeedsServiceRestart(key, previousValue, currentValue) ||
        HaogeSpringTwelveMotionXRestartInFlight) return;
    HaogeSpringTwelveMotionXRestartInFlight = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            int code = haoge_springtwelve_restartMotionXServices();
            dispatch_async(dispatch_get_main_queue(), ^{
                HaogeSpringTwelveMotionXRestartInFlight = NO;
                HaogeSpringTwelveMiscListController *controller = weakSelf;
                if (!code || !controller.view.window || controller.presentedViewController ||
                    UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置已保存，服务重载未完成"
                    message:[NSString stringWithFormat:@"自动结束录屏服务失败（状态 %d）。请手动重启用户空间后使用。", code]
                    preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [controller presentViewController:alert animated:YES completion:nil];
            });
        }
    });
}
@end
