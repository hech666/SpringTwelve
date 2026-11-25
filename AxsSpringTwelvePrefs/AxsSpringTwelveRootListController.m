#import "AxsSpringTwelveRootListController.h"
#import "AxsSpringTwelvePreferences.h"
#import "AxsSpringTwelvePaths.h"
#import <dlfcn.h>
#import <string.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>


static BOOL axs_springtwelve_prefsSignature(id target, SEL selector, char result,
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

@interface AxsSpringTwelveRootListController ()
@property(nonatomic) BOOL axs_springtwelve_logoutInFlight;
@end

@implementation AxsSpringTwelveRootListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"注销" style:UIBarButtonItemStylePlain
        target:self action:@selector(axs_springtwelve_requestLogout:)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Reapply after Preferences rebuilds the navigation item on appearance.
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"注销" style:UIBarButtonItemStylePlain
        target:self action:@selector(axs_springtwelve_requestLogout:)];
}

- (void)axs_springtwelve_requestLogout:(id)sender {
    if (self.presentedViewController || self.axs_springtwelve_logoutInFlight) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"注销桌面"
        message:@"将重新启动桌面以应用设置，当前界面会关闭。请先结束通话并保存正在进行的操作。是否继续？"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确认注销" style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *action) {
            AxsSpringTwelveRootListController *controller = weakSelf;
            if (!controller || controller.axs_springtwelve_logoutInFlight ||
                !controller.view.window || controller.navigationController.topViewController != controller ||
                UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            [controller axs_springtwelve_performLogout];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)axs_springtwelve_logoutFailed:(NSString *)message {
    self.axs_springtwelve_logoutInFlight = NO;
    self.navigationItem.rightBarButtonItem.enabled = YES;
    // Let the confirmation alert finish dismissing before presenting an error.
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AxsSpringTwelveRootListController *controller = weakSelf;
        if (!controller.view.window || controller.presentedViewController ||
            UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"注销请求未完成"
            message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [controller presentViewController:alert animated:YES completion:nil];
    });
}

- (void)axs_springtwelve_performLogout {
    self.axs_springtwelve_logoutInFlight = YES;
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
        if (!axs_springtwelve_prefsSignature(serviceClass, shared, '@', @[]) ||
            !axs_springtwelve_prefsSignature(actionClass, create, '@', @[@"@", @(@encode(NSUInteger)), @"@"])) {
            [self axs_springtwelve_logoutFailed:@"当前系统未提供所需的桌面重启接口，未尝试其他操作。"]; return;
        }
        id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, shared);
        if (!axs_springtwelve_prefsSignature(service, send, 'v', @[@"@", @"@"])) {
            [self axs_springtwelve_logoutFailed:@"当前系统未提供所需的桌面重启服务，未尝试其他操作。"]; return;
        }
        id request = ((id (*)(id, SEL, NSString *, NSUInteger, NSURL *))objc_msgSend)
            (actionClass, create, @"RestartRenderServer", (NSUInteger)4, nil);
        if (!request) { [self axs_springtwelve_logoutFailed:@"系统未能创建注销请求。"]; return; }
        __weak typeof(self) weakSelf = self;
        void (^result)(NSError *) = ^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) [weakSelf axs_springtwelve_logoutFailed:
                    [NSString stringWithFormat:@"系统拒绝了注销请求（错误 %ld）。", (long)error.code]];
                // An accepted request is not evidence that the desktop has restarted.
            });
        };
        ((void (*)(id, SEL, NSSet *, void (^)(NSError *)))objc_msgSend)
            (service, send, [NSSet setWithObject:request], result);
    } @catch (__unused NSException *exception) {
        [self axs_springtwelve_logoutFailed:@"调用桌面重启服务时发生异常，未尝试其他操作。"];
    }
}

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"AxsSpringTwelveRoot"
                                                           target:self] mutableCopy];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"关于我们" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self axs_springtwelve_addButton:@"录音列表" action:@selector(axs_springtwelve_openRecordings:) to:items];
        [self axs_springtwelve_addButton:@"打开录音目录" action:@selector(axs_springtwelve_openRecordingsFolder:) to:items];
        [self axs_springtwelve_addButton:@"导出功能诊断" action:@selector(axs_springtwelve_exportDiagnostics:) to:items];
        [self axs_springtwelve_addButton:@"Sileo 越狱源" action:@selector(axs_springtwelve_openRepository:) to:items];
        [self axs_springtwelve_addButton:@"TG分享频道" action:@selector(axs_springtwelve_openTelegram:) to:items];
        [self axs_springtwelve_addButton:@"QQ交流群组" action:@selector(axs_springtwelve_openQQ:) to:items];
        _specifiers = items;
    }
    return _specifiers;
}

- (void)axs_springtwelve_addButton:(NSString *)title action:(SEL)action to:(NSMutableArray *)items {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:title target:self
                          set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    item.buttonAction = action;
    [items addObject:item];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return nil;
    return axs_springtwelve_readPreferences()[key] ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    NSError *error = nil;
    if (!axs_springtwelve_writePreference(key, value, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
            message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
    }
}

- (void)axs_springtwelve_openRecordings:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"通话录音"
        message:@"录音列表入口会在电话 App 中由启用的 SpringTwelve 模块提供。自动录音由“蜂窝通话接通自动录音”开关控制，默认关闭。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"打开录音目录" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) { [self axs_springtwelve_openRecordingsFolder:sender]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)axs_springtwelve_openRecordingsFolder:(id)sender {
    NSURL *directoryURL = [NSURL fileURLWithPath:axs_springtwelve_recordingDirectory() isDirectory:YES];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
    picker.directoryURL = directoryURL;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)axs_springtwelve_exportDiagnostics:(id)sender {
    NSString *directory = [axs_springtwelve_recordingDirectory() stringByAppendingPathComponent:@"Diagnostics"];
    NSMutableString *report = [NSMutableString stringWithString:@"SpringTwelve diagnostics (event states only; no audio or contact fields)\n"];
    BOOL found = NO;
    for (NSString *name in @[@"AxsSpringTwelve-recording.log.previous", @"AxsSpringTwelve-recording.log", @"power-menu.log.previous", @"power-menu.log"]) {
        NSString *text = [NSString stringWithContentsOfFile:[directory stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:NULL];
        if (!text.length) continue;
        found = YES;
        [report appendFormat:@"\n=== %@ ===\n%@", name, text];
    }
    if (!found) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"暂无诊断日志"
            message:@"请安装新版本并注销桌面，然后分别测试长按和蜂窝通话。如果仍没有日志，可能是模块未注入或日志目录不可写。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    // Share a text snapshot, never the recording directory or any audio file.
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[report] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:share animated:YES completion:nil];
}

- (void)axs_springtwelve_openURL:(NSURL *)url fallback:(NSURL *)fallback {
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (success) return;
        if (fallback) {
            [self axs_springtwelve_openURL:fallback fallback:nil];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开链接"
                message:@"请确认已安装对应应用。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

- (void)axs_springtwelve_openRepository:(id)sender {
    NSString *source = @"https://axs66.github.io/pro";
    // Encode the entire URL as a path component, including its own delimiters.
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *encoded = [source stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    NSURL *primary = [NSURL URLWithString:[@"sileo://source/" stringByAppendingString:encoded]];
    [self axs_springtwelve_openURL:primary fallback:[NSURL URLWithString:source]];
}

- (void)axs_springtwelve_openTelegram:(id)sender {
    [self axs_springtwelve_openURL:[NSURL URLWithString:@"tg://resolve?domain=wxfx8"]
                   fallback:[NSURL URLWithString:@"https://t.me/wxfx8"]];
}

- (void)axs_springtwelve_openQQ:(id)sender {
    [self axs_springtwelve_openURL:[NSURL URLWithString:@"mqqapi://card/show_pslcard?src_type=internal&version=1&uin=678055716&card_type=group&source=qrcode"] fallback:nil];
}


@end
