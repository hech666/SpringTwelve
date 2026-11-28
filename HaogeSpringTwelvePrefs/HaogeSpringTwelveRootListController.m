#import "HaogeSpringTwelveRootListController.h"
#import "HaogeSpringTwelvePreferences.h"
#import <dlfcn.h>
#import <string.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>


static BOOL haoge_springtwelve_prefsSignature(id target, SEL selector, char result,
                                           NSArray<NSString *> *arguments) {
    if (!target || ![target respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != arguments.count + 2) return NO;
    const char *type = signature.methodReturnType;
    while (*type && strchr("rnNoORV", *type)) type++;
    if (*type != result) return NO;
    for (NSUInteger i = 0; i < arguments.count; i++) {
        const char *actual = [signature getArgumentTypeAtIndex:i + 2];
        while (*actual && strchr("rnNoORV", *actual)) actual++;
        const char *expected = arguments[i].UTF8String;
        if (expected[0] == '@' ? actual[0] != '@' : strcmp(actual, expected) != 0) return NO;
    }
    return YES;
}

@interface HaogeSpringTwelveRootListController ()
@property(nonatomic) BOOL haoge_springtwelve_logoutInFlight;
@end

@implementation HaogeSpringTwelveRootListController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Reapply after Preferences rebuilds the navigation item on appearance.
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"注销" style:UIBarButtonItemStylePlain
        target:self action:@selector(haoge_springtwelve_requestLogout:)];
}

- (void)haoge_springtwelve_requestLogout:(id)sender {
    if (self.presentedViewController || self.haoge_springtwelve_logoutInFlight) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"注销桌面"
        message:@"将重新启动桌面以应用设置，当前界面会关闭。请先结束通话并保存正在进行的操作。是否继续？"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确认注销" style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *action) {
            HaogeSpringTwelveRootListController *controller = weakSelf;
            if (!controller || controller.haoge_springtwelve_logoutInFlight ||
                !controller.view.window || controller.navigationController.topViewController != controller ||
                UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            [controller haoge_springtwelve_performLogout];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)haoge_springtwelve_logoutFailed:(NSString *)message {
    self.haoge_springtwelve_logoutInFlight = NO;
    self.navigationItem.rightBarButtonItem.enabled = YES;
    // Let the confirmation alert finish dismissing before presenting an error.
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        HaogeSpringTwelveRootListController *controller = weakSelf;
        if (!controller.view.window || controller.presentedViewController ||
            UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"注销请求未完成"
            message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [controller presentViewController:alert animated:YES completion:nil];
    });
}

- (void)haoge_springtwelve_performLogout {
    self.haoge_springtwelve_logoutInFlight = YES;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    @try {
        // Same verified native fade-to-black request as the desktop menu.
        // Settings cannot use kill(getpid()): that would kill Settings, not SpringBoard.
        dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW | RTLD_LOCAL);
        dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW | RTLD_LOCAL);
        Class serviceClass = NSClassFromString(@"FBSSystemService");
        Class actionClass = NSClassFromString(@"SBSRelaunchAction");
        SEL shared = NSSelectorFromString(@"sharedService");
        SEL create = NSSelectorFromString(@"actionWithReason:options:targetURL:");
        SEL send = NSSelectorFromString(@"sendActions:withResult:");
        if (!haoge_springtwelve_prefsSignature(serviceClass, shared, '@', @[]) ||
            !haoge_springtwelve_prefsSignature(actionClass, create, '@', @[@"@", @(@encode(NSUInteger)), @"@"])) {
            [self haoge_springtwelve_logoutFailed:@"当前系统未提供所需的桌面重启接口，未尝试其他操作。"]; return;
        }
        id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, shared);
        if (!haoge_springtwelve_prefsSignature(service, send, 'v', @[@"@", @"@"])) {
            [self haoge_springtwelve_logoutFailed:@"当前系统未提供所需的桌面重启服务，未尝试其他操作。"]; return;
        }
        id request = ((id (*)(id, SEL, NSString *, NSUInteger, NSURL *))objc_msgSend)
            (actionClass, create, @"RestartRenderServer", (NSUInteger)4, nil);
        if (!request) { [self haoge_springtwelve_logoutFailed:@"系统未能创建注销请求。"]; return; }
        __weak typeof(self) weakSelf = self;
        void (^result)(NSError *) = ^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) [weakSelf haoge_springtwelve_logoutFailed:
                    [NSString stringWithFormat:@"系统拒绝了注销请求（错误 %ld）。", (long)error.code]];
                // An accepted request is not evidence that the desktop has restarted.
            });
        };
        ((void (*)(id, SEL, NSSet *, void (^)(NSError *)))objc_msgSend)
            (service, send, [NSSet setWithObject:request], result);
    } @catch (__unused NSException *exception) {
        [self haoge_springtwelve_logoutFailed:@"调用桌面重启服务时发生异常，未尝试其他操作。"];
    }
}

- (NSString *)haoge_springtwelve_specifierPlistName {
    return @"HaogeSpringTwelveRoot";
}

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:[self haoge_springtwelve_specifierPlistName]
                                               target:self] mutableCopy];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return nil;
    return haoge_springtwelve_readPreferences()[key] ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    id previousValue = [self readPreferenceValue:specifier];
    NSError *error = nil;
    if (!haoge_springtwelve_writePreference(key, value, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
            message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
        return;
    }
    // The atomic file write and notification have completed before side effects.
    [self haoge_springtwelve_didSavePreference:key previousValue:previousValue
        currentValue:haoge_springtwelve_readPreferences()[key]];
}

- (void)haoge_springtwelve_didSavePreference:(__unused NSString *)key
                            previousValue:(__unused id)previousValue
                             currentValue:(__unused id)currentValue {
    // No side effects for the existing pages or unrelated switches.
}

@end
