#import "AxsSpringTwelveRootListController.h"
#import "AxsSpringTwelvePreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>


@interface AxsSpringTwelveRootListController ()
@end

@implementation AxsSpringTwelveRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"AxsSpringTwelveRoot"
                                                           target:self] mutableCopy];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"关于我们" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self axs_springtwelve_addButton:@"录音列表" action:@selector(axs_springtwelve_openRecordings:) to:items];
        [self axs_springtwelve_addButton:@"打开录音目录" action:@selector(axs_springtwelve_openRecordingsFolder:) to:items];
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
    NSURL *directoryURL = [NSURL fileURLWithPath:@"/var/mobile/Documents/CallRecordings" isDirectory:YES];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
    picker.directoryURL = directoryURL;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
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
