#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <signal.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
#import <fcntl.h>
#import "HaogeSpringTwelveSwitches.h"
#import "HaogeSpringTwelvePaths.h"
#import "HaogeSpringTwelvePowerActions.h"

// Fixed event names only: no coordinates, identifiers, text, or user content.
static NSMutableDictionary<NSString *, NSDate *> *HaogeSpringTwelvePowerMenuLogTimes;
static void haoge_springtwelve_powerLog(NSString *event) {
    if (![NSThread isMainThread]) return;
    if (!HaogeSpringTwelvePowerMenuLogTimes) HaogeSpringTwelvePowerMenuLogTimes = [NSMutableDictionary dictionary];
    NSDate *now = [NSDate date];
    NSDate *last = HaogeSpringTwelvePowerMenuLogTimes[event];
    if (last && [now timeIntervalSinceDate:last] < 30.0) return;
    HaogeSpringTwelvePowerMenuLogTimes[event] = now;
    @try {
        NSString *directory = @"/var/mobile/Library/Logs/SpringTwelve";
        NSFileManager *manager = NSFileManager.defaultManager;
        [manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:NULL];
        NSString *path = [directory stringByAppendingPathComponent:@"power-menu.log"];
        if ([[manager attributesOfItemAtPath:path error:NULL][NSFileSize] unsignedLongLongValue] > 65536) {
            NSString *previous = [path stringByAppendingString:@".previous"];
            [manager removeItemAtPath:previous error:NULL];
            [manager moveItemAtPath:path toPath:previous error:NULL];
        }
        int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd < 0) return;
        NSString *line = [NSString stringWithFormat:@"%.0f %@\n", now.timeIntervalSince1970, event];
        write(fd, line.UTF8String, strlen(line.UTF8String));
        close(fd);
    } @catch (__unused NSException *exception) {}
}

// SpringBoard-only menu; all backend requests require explicit confirmation.
@class HaogeSpringTwelvePowerMenuController;
static HaogeSpringTwelvePowerMenuController *HaogeSpringTwelvePowerMenuActive;
static char HaogeSpringTwelvePowerMenuTargetKey;

static id haoge_springtwelve_powerShared(NSString *className) {
    Class cls = NSClassFromString(className);
    SEL selector = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [cls methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, selector);
}

static BOOL haoge_springtwelve_powerReadBool(id object, NSString *name, BOOL *value) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2) return NO;
    const char *type = signature.methodReturnType;
    if (strcmp(type, @encode(BOOL)) && strcmp(type, "B") && strcmp(type, "c")) return NO;
    *value = ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    return YES;
}

static BOOL haoge_springtwelve_powerHomeReady(UIView *home, BOOL needsKeyWindow) {
    if (![NSThread isMainThread]) return NO;
    if (!HaogeSpringTwelveOn(@"lsPowerMenuOnDesktop")) { haoge_springtwelve_powerLog(@"disabled"); return NO; }
    UIWindow *window = home.window;
    UIWindowScene *scene = window.windowScene;
    if (!home || !window || window.hidden || window.alpha < 0.99 ||
        window.windowLevel >= UIWindowLevelAlert ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        (scene && scene.activationState != UISceneActivationStateForegroundActive)) {
        haoge_springtwelve_powerLog(@"home-context-rejected"); return NO;
    }
    for (UIView *view = home; view; view = view.superview) {
        if (view.hidden || view.alpha < 0.99 || !view.userInteractionEnabled) return NO;
    }
    // Fail only on a positively confirmed dangerous state. An unknown private
    // selector must not permanently disable the menu: the gesture itself only
    // fires on the home screen, so an unreadable lock/edit state is treated as
    // clear rather than failing closed.
    BOOL locked = NO, editing = NO;
    if (haoge_springtwelve_powerReadBool(haoge_springtwelve_powerShared(@"SBLockScreenManager"),
                                     @"isUILocked", &locked) && locked) return NO;
    if (haoge_springtwelve_powerReadBool(haoge_springtwelve_powerShared(@"SBIconController"),
                                     @"isEditing", &editing) && editing) return NO;
    if (needsKeyWindow && window.rootViewController.presentedViewController) return NO;
    return YES;
}

static BOOL haoge_springtwelve_powerBlankPath(UIView *leaf, UIView *home) {
    // A hit on the root itself is a valid empty-workspace hit; UIKit can return
    // the root rather than its wallpaper child when no subview handles it.
    if (leaf == home) return YES;
    // The root workspace is the authorization boundary. Reject identifiable
    // icons, widgets, folders, controls, hidden views, and active scrolling; a
    // wallpaper/background hit need not descend through SBIconListView.
    for (UIView *view = leaf; view && view != home; view = view.superview) {
        NSString *name = NSStringFromClass(view.class);
        BOOL list = [name isEqualToString:@"SBIconListView"] ||
                    [name isEqualToString:@"SBRootIconListView"];
        if ([view isKindOfClass:UIControl.class] || view.hidden || view.alpha < 0.99) return NO;
        if (!list && ([name containsString:@"IconView"] ||
                      [name containsString:@"IconLabel"] ||
                      [name containsString:@"Widget"] ||
                      [name containsString:@"FolderView"] ||
                      [name containsString:@"Control"])) return NO;
        if ([view isKindOfClass:UIScrollView.class]) {
            UIScrollView *scroll = (UIScrollView *)view;
            if (scroll.dragging || scroll.decelerating) return NO;
        }
        if (view.superview == home) return YES;
    }
    return NO;
}

static BOOL haoge_springtwelve_powerBlankPoint(UIView *home, CGPoint point) {
    if (!haoge_springtwelve_powerHomeReady(home, YES) ||
        !CGRectContainsPoint(UIEdgeInsetsInsetRect(home.bounds, home.safeAreaInsets), point)) return NO;
    UIWindow *window = home.window;
    UIView *hit = [window hitTest:[home convertPoint:point toView:window] withEvent:nil];
    return haoge_springtwelve_powerBlankPath(hit, home);
}

@interface HaogeSpringTwelvePowerMenuController : UIViewController
@property(nonatomic, weak) UIView *haoge_springtwelve_home;
@property(nonatomic, weak) UIWindow *haoge_springtwelve_homeWindow;
@property(nonatomic, weak) UIWindow *haoge_springtwelve_previousWindow;
@property(nonatomic, strong) UIWindow *haoge_springtwelve_overlay;
@property(nonatomic, strong) UIAlertController *haoge_springtwelve_menu;
@property(nonatomic, copy) NSString *haoge_springtwelve_statusMessage;
@property(nonatomic, strong) NSUUID *haoge_springtwelve_transitionToken;
@property(nonatomic) BOOL haoge_springtwelve_started;
@property(nonatomic) NSInteger haoge_springtwelve_pendingAction;
@property(nonatomic) BOOL haoge_springtwelve_closing;
@property(nonatomic) BOOL haoge_springtwelve_executing;
@property(nonatomic, strong) UIAlertController *haoge_springtwelve_confirmation;
@property(nonatomic, strong) NSUUID *haoge_springtwelve_confirmationToken;
- (void)haoge_springtwelve_close;
- (void)haoge_springtwelve_showMenu;
- (void)haoge_springtwelve_confirmAction:(HaogeSpringTwelvePowerAction)selected;
- (void)haoge_springtwelve_presentConfirmation:(HaogeSpringTwelvePowerAction)selected token:(NSUUID *)token;
@end

@implementation HaogeSpringTwelvePowerMenuController
- (BOOL)haoge_springtwelve_contextValid {
    // Present the system alert from this overlay's root controller. A real
    // key-window loss or background transition still revokes authorization.
    UIWindow *overlay = self.haoge_springtwelve_overlay;
    return !self.haoge_springtwelve_closing && HaogeSpringTwelvePowerMenuActive == self &&
        overlay && !overlay.hidden && overlay.isKeyWindow &&
        self.haoge_springtwelve_home.window == self.haoge_springtwelve_homeWindow &&
        haoge_springtwelve_powerHomeReady(self.haoge_springtwelve_home, NO);
}

- (void)haoge_springtwelve_close {
    if (self.haoge_springtwelve_closing) return;
    self.haoge_springtwelve_closing = YES;
    self.haoge_springtwelve_pendingAction = 0;
    self.haoge_springtwelve_confirmationToken = nil;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (HaogeSpringTwelvePowerMenuActive == self) HaogeSpringTwelvePowerMenuActive = nil;
    self.haoge_springtwelve_transitionToken = nil;
    [self dismissViewControllerAnimated:NO completion:nil];
    self.haoge_springtwelve_menu = nil;
    self.haoge_springtwelve_confirmation = nil;
    UIWindow *overlay = self.haoge_springtwelve_overlay;
    BOOL restoreKey = overlay.isKeyWindow;
    overlay.hidden = YES;
    overlay.rootViewController = nil;
    self.haoge_springtwelve_overlay = nil;
    UIWindow *previous = self.haoge_springtwelve_previousWindow;
    if (restoreKey && previous && !previous.hidden &&
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
        (!previous.windowScene || previous.windowScene.activationState == UISceneActivationStateForegroundActive)) {
        [previous makeKeyWindow];
    }
    if (HaogeSpringTwelvePowerMenuActive == self) HaogeSpringTwelvePowerMenuActive = nil;
}

- (void)haoge_springtwelve_invalidate:(NSNotification *)notification {
    haoge_springtwelve_powerLog(@"menu-context-invalidated");
    [self haoge_springtwelve_close];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)loadView {
    UIView *background = [UIView new];
    background.backgroundColor = UIColor.clearColor;
    background.accessibilityViewIsModal = YES;
    self.view = background;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.haoge_springtwelve_started) return;
    self.haoge_springtwelve_started = YES;
    [self haoge_springtwelve_showMenu];
}

// UIAlertAction owns automatic dismissal. Never present its successor inside
// the action handler: wait for UIKit to release the old presentation. This
// bounded, revocable UI-only retry cannot submit a device action.
- (void)haoge_springtwelve_presentWhenReady:(void (^)(void))presentation
                                  ticket:(NSUUID *)ticket attempt:(NSUInteger)attempt {
    if (self.haoge_springtwelve_transitionToken != ticket || self.haoge_springtwelve_closing) return;
    if (![self haoge_springtwelve_contextValid]) { [self haoge_springtwelve_close]; return; }
    if (!self.presentedViewController && !self.transitionCoordinator && self.view.window) {
        self.haoge_springtwelve_transitionToken = nil;
        presentation();
        return;
    }
    if (attempt >= 60) {
        haoge_springtwelve_powerLog(@"system-alert-transition-timeout");
        [self haoge_springtwelve_close];
        return;
    }
    __weak HaogeSpringTwelvePowerMenuController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf haoge_springtwelve_presentWhenReady:presentation ticket:ticket attempt:attempt + 1];
    });
}

- (void)haoge_springtwelve_queuePresentation:(void (^)(void))presentation {
    NSUUID *ticket = NSUUID.UUID;
    self.haoge_springtwelve_transitionToken = ticket;
    __weak HaogeSpringTwelvePowerMenuController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf haoge_springtwelve_presentWhenReady:presentation ticket:ticket attempt:0];
    });
}

- (void)haoge_springtwelve_showMenu {
    __weak HaogeSpringTwelvePowerMenuController *weakSelf = self;
    [self haoge_springtwelve_queuePresentation:^{
        HaogeSpringTwelvePowerMenuController *controller = weakSelf;
        if (!controller || controller.haoge_springtwelve_pendingAction || controller.haoge_springtwelve_confirmation) return;
        UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"桌面电源菜单"
            message:controller.haoge_springtwelve_statusMessage preferredStyle:UIAlertControllerStyleAlert];
        controller.haoge_springtwelve_menu = menu;
        __weak UIAlertController *weakMenu = menu;
        NSArray<NSNumber *> *selections = @[@(HaogeSpringTwelvePowerActionQuickRespring),
            @(HaogeSpringTwelvePowerActionForceRespring), @(HaogeSpringTwelvePowerActionRespring),
            @(HaogeSpringTwelvePowerActionUserspaceReboot), @(HaogeSpringTwelvePowerActionReboot),
            @(HaogeSpringTwelvePowerActionShutdown)];
        for (NSNumber *selection in selections) {
            HaogeSpringTwelvePowerAction selected = (HaogeSpringTwelvePowerAction)selection.integerValue;
            BOOL available = haoge_springtwelve_powerActionAvailable(selected);
            NSString *title = haoge_springtwelve_powerActionTitle(selected);
            if (!available) title = [title stringByAppendingString:@" — 当前环境不可用"];
            UIAlertAction *item = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDestructive
                handler:^(__unused UIAlertAction *action) {
                HaogeSpringTwelvePowerMenuController *live = weakSelf;
                UIAlertController *activeMenu = weakMenu;
                if (!live || !activeMenu || live.haoge_springtwelve_menu != activeMenu ||
                    live.haoge_springtwelve_pendingAction || live.haoge_springtwelve_executing) return;
                if (![live haoge_springtwelve_contextValid]) { [live haoge_springtwelve_close]; return; }
                live.haoge_springtwelve_menu = nil;
                [live haoge_springtwelve_confirmAction:selected];
            }];
            item.enabled = available && !controller.haoge_springtwelve_executing;
            [menu addAction:item];
        }
        [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel
            handler:^(__unused UIAlertAction *action) {
            HaogeSpringTwelvePowerMenuController *live = weakSelf;
            UIAlertController *activeMenu = weakMenu;
            if (live && activeMenu && !live.haoge_springtwelve_closing &&
                live.haoge_springtwelve_menu == activeMenu) [live haoge_springtwelve_close];
        }]];
        [controller presentViewController:menu animated:YES completion:^{
            HaogeSpringTwelvePowerMenuController *live = weakSelf;
            if (live && ![live haoge_springtwelve_contextValid]) [live haoge_springtwelve_close];
        }];
        haoge_springtwelve_powerLog(@"system-menu-presented");
    }];
}

- (void)haoge_springtwelve_setStatus:(NSString *)message {
    self.haoge_springtwelve_statusMessage = message;
    UIAlertController *menu = self.haoge_springtwelve_menu;
    if (menu && self.presentedViewController == menu) {
        menu.message = message;
        NSArray<NSNumber *> *selections = @[@(HaogeSpringTwelvePowerActionQuickRespring),
            @(HaogeSpringTwelvePowerActionForceRespring), @(HaogeSpringTwelvePowerActionRespring),
            @(HaogeSpringTwelvePowerActionUserspaceReboot), @(HaogeSpringTwelvePowerActionReboot),
            @(HaogeSpringTwelvePowerActionShutdown)];
        for (NSUInteger i = 0; i < selections.count && i < menu.actions.count; i++) {
            menu.actions[i].enabled = !self.haoge_springtwelve_executing &&
                haoge_springtwelve_powerActionAvailable((HaogeSpringTwelvePowerAction)selections[i].integerValue);
        }
    } else if (!self.haoge_springtwelve_pendingAction && !self.haoge_springtwelve_confirmation) {
        [self haoge_springtwelve_showMenu];
    }
    if (message.length) UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
}

- (void)haoge_springtwelve_cancelConfirmation {
    self.haoge_springtwelve_confirmationToken = nil;
    self.haoge_springtwelve_pendingAction = 0;
    UIAlertController *alert = self.haoge_springtwelve_confirmation;
    self.haoge_springtwelve_confirmation = nil;
    [alert dismissViewControllerAnimated:YES completion:nil];
    [self haoge_springtwelve_showMenu];
}

- (BOOL)accessibilityPerformEscape {
    if (self.haoge_springtwelve_confirmation) [self haoge_springtwelve_cancelConfirmation];
    else [self haoge_springtwelve_close];
    return YES;
}

- (void)haoge_springtwelve_confirmAction:(HaogeSpringTwelvePowerAction)selected {
    if (![self haoge_springtwelve_contextValid]) { [self haoge_springtwelve_close]; return; }
    if (self.haoge_springtwelve_confirmation || self.haoge_springtwelve_pendingAction || self.haoge_springtwelve_executing) return;
    if (!haoge_springtwelve_powerActionAvailable(selected)) {
        [self haoge_springtwelve_setStatus:@"此操作所需的系统接口或提权工具当前不可用，请检查安装后重新打开面板。"];
        return;
    }
    NSUUID *token = NSUUID.UUID;
    self.haoge_springtwelve_confirmationToken = token;
    self.haoge_springtwelve_pendingAction = selected;
    __weak HaogeSpringTwelvePowerMenuController *weakSelf = self;
    [self haoge_springtwelve_queuePresentation:^{
        HaogeSpringTwelvePowerMenuController *controller = weakSelf;
        if (!controller || controller.haoge_springtwelve_confirmationToken != token ||
            controller.haoge_springtwelve_pendingAction != selected) return;
        [controller haoge_springtwelve_presentConfirmation:selected token:token];
    }];
}

- (void)haoge_springtwelve_presentConfirmation:(HaogeSpringTwelvePowerAction)selected token:(NSUUID *)token {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:
        [@"确认：" stringByAppendingString:haoge_springtwelve_powerActionTitle(selected)]
        message:haoge_springtwelve_powerActionWarning(selected) preferredStyle:UIAlertControllerStyleAlert];
    self.haoge_springtwelve_confirmation = alert;
    __weak HaogeSpringTwelvePowerMenuController *weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel
        handler:^(__unused UIAlertAction *action) {
        HaogeSpringTwelvePowerMenuController *controller = weakSelf;
        if (!controller || controller.haoge_springtwelve_closing ||
            controller.haoge_springtwelve_confirmationToken != token ||
            controller.haoge_springtwelve_pendingAction != selected ||
            controller.haoge_springtwelve_confirmation != weakAlert) return;
        controller.haoge_springtwelve_confirmationToken = nil;
        controller.haoge_springtwelve_pendingAction = 0;
        controller.haoge_springtwelve_confirmation = nil;
        haoge_springtwelve_powerLog(@"confirmation-cancelled");
        [controller haoge_springtwelve_showMenu];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确认执行" style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *action) {
        HaogeSpringTwelvePowerMenuController *controller = weakSelf;
        if (!controller || controller.haoge_springtwelve_closing ||
            controller.haoge_springtwelve_confirmationToken != token ||
            controller.haoge_springtwelve_pendingAction != selected) return;
        UIAlertController *activeAlert = weakAlert;
        BOOL authorized = [controller haoge_springtwelve_contextValid] && activeAlert &&
            controller.haoge_springtwelve_confirmation == activeAlert &&
            controller.view.window == controller.haoge_springtwelve_overlay;
        if (!authorized) {
            haoge_springtwelve_powerLog(@"confirmation-rejected");
            [controller haoge_springtwelve_close]; return;
        }
        // Only this one-shot confirmed path may submit a device action.
        controller.haoge_springtwelve_confirmationToken = nil;
        controller.haoge_springtwelve_pendingAction = 0;
        controller.haoge_springtwelve_confirmation = nil;
        controller.haoge_springtwelve_executing = YES;
        [controller haoge_springtwelve_setStatus:@"正在提交操作，请勿重复点击。"];
        NSDictionary<NSNumber *, NSString *> *events = @{
            @(HaogeSpringTwelvePowerActionQuickRespring): @"quick-respring-request",
            @(HaogeSpringTwelvePowerActionForceRespring): @"force-respring-request",
            @(HaogeSpringTwelvePowerActionRespring): @"respring-request",
            @(HaogeSpringTwelvePowerActionUserspaceReboot): @"userspace-reboot-request",
            @(HaogeSpringTwelvePowerActionReboot): @"device-reboot-request",
            @(HaogeSpringTwelvePowerActionShutdown): @"shutdown-request"
        };
        haoge_springtwelve_powerLog(events[@(selected)]);
        haoge_springtwelve_powerActionRequest(selected, ^(NSString *error) {
            HaogeSpringTwelvePowerMenuController *live = weakSelf;
            if (!live || live.haoge_springtwelve_closing || HaogeSpringTwelvePowerMenuActive != live) return;
            if (error) {
                live.haoge_springtwelve_executing = NO;
                [live haoge_springtwelve_setStatus:error];
                haoge_springtwelve_powerLog(@"action-request-error");
            } else {
                [live haoge_springtwelve_setStatus:@"操作请求已提交。若设备未响应，请关闭面板并导出功能诊断；提交不代表重启已经完成。"];
                haoge_springtwelve_powerLog(@"action-request-submitted");
            }
        });
    }]];
    [self presentViewController:alert animated:YES completion:^{
        HaogeSpringTwelvePowerMenuController *controller = weakSelf;
        if (controller.haoge_springtwelve_confirmationToken == token &&
            ![controller haoge_springtwelve_contextValid]) [controller haoge_springtwelve_close];
    }];
    haoge_springtwelve_powerLog(@"system-confirmation-presented");
}


@end

@interface HaogeSpringTwelvePowerMenuTarget : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView *haoge_springtwelve_home;
@end

@implementation HaogeSpringTwelvePowerMenuTarget
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *home = self.haoge_springtwelve_home;
    if (HaogeSpringTwelvePowerMenuActive || touch.type != UITouchTypeDirect) return NO;
    BOOL blankPath = haoge_springtwelve_powerBlankPath(touch.view, home);
    if (!blankPath) { haoge_springtwelve_powerLog(@"touch-not-blank"); return NO; }
    BOOL blankPoint = haoge_springtwelve_powerBlankPoint(home, [touch locationInView:home]);
    if (!blankPoint) haoge_springtwelve_powerLog(@"touch-context-or-point-rejected");
    return blankPoint;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (HaogeSpringTwelvePowerMenuActive) return NO;
    BOOL accepted = haoge_springtwelve_powerBlankPoint(self.haoge_springtwelve_home,
        [recognizer locationInView:self.haoge_springtwelve_home]);
    if (!accepted) haoge_springtwelve_powerLog(@"gesture-should-begin-rejected");
    return accepted;
}

- (void)haoge_springtwelve_longPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan || HaogeSpringTwelvePowerMenuActive) return;
    UIView *home = self.haoge_springtwelve_home;
    if (!haoge_springtwelve_powerBlankPoint(home, [recognizer locationInView:home])) {
        haoge_springtwelve_powerLog(@"long-press-rejected-at-begin"); return;
    }
    haoge_springtwelve_powerLog(@"menu-present-request");
    HaogeSpringTwelvePowerMenuController *controller = [HaogeSpringTwelvePowerMenuController new];
    controller.haoge_springtwelve_home = home;
    controller.haoge_springtwelve_homeWindow = home.window;
    UIWindow *originalKey = nil;
    for (UIWindow *candidate in home.window.windowScene.windows) {
        if (candidate.isKeyWindow) { originalKey = candidate; break; }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (!originalKey) for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
        if (candidate.isKeyWindow && candidate.windowScene == home.window.windowScene) { originalKey = candidate; break; }
    }
#pragma clang diagnostic pop
    controller.haoge_springtwelve_previousWindow = originalKey ?: home.window;
    UIWindowScene *scene = home.window.windowScene;
    UIWindow *overlay = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:home.window.bounds];
    overlay.frame = home.window.bounds;
    overlay.windowLevel = UIWindowLevelNormal + 1.0; // Never an alert/lock-screen level.
    overlay.backgroundColor = UIColor.clearColor;
    overlay.rootViewController = controller;
    controller.haoge_springtwelve_overlay = overlay;
    HaogeSpringTwelvePowerMenuActive = controller;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:controller selector:@selector(haoge_springtwelve_invalidate:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:controller selector:@selector(haoge_springtwelve_invalidate:)
        name:UISceneWillDeactivateNotification object:home.window.windowScene];
    [center addObserver:controller selector:@selector(haoge_springtwelve_invalidate:)
        name:UIWindowDidResignKeyNotification object:overlay];
    [center addObserver:controller selector:@selector(haoge_springtwelve_invalidate:)
        name:UIWindowDidBecomeHiddenNotification object:home.window];
    [overlay makeKeyAndVisible];
}
@end

static void haoge_springtwelve_powerInstall(UIView *home) {
    if (![NSThread isMainThread]) return;
    if (!home.window) {
        if (HaogeSpringTwelvePowerMenuActive.haoge_springtwelve_home == home)
            [HaogeSpringTwelvePowerMenuActive haoge_springtwelve_close];
        return;
    }
    if (objc_getAssociatedObject(home, &HaogeSpringTwelvePowerMenuTargetKey)) return;
    HaogeSpringTwelvePowerMenuTarget *target = [HaogeSpringTwelvePowerMenuTarget new];
    target.haoge_springtwelve_home = home;
    UILongPressGestureRecognizer *recognizer = [[UILongPressGestureRecognizer alloc]
        initWithTarget:target action:@selector(haoge_springtwelve_longPress:)];
    recognizer.minimumPressDuration = 0.45;
    recognizer.allowableMovement = 8.0;
    recognizer.numberOfTouchesRequired = 1;
    recognizer.cancelsTouchesInView = YES;
    recognizer.delaysTouchesBegan = NO;
    recognizer.delaysTouchesEnded = NO;
    recognizer.delegate = target;
    objc_setAssociatedObject(home, &HaogeSpringTwelvePowerMenuTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [home addGestureRecognizer:recognizer];
    haoge_springtwelve_powerLog(@"gesture-installed");
}

%group HaogeSpringTwelvePowerMenuHooks
%hook HaogeSpringTwelvePowerMenuHomeView
- (void)didMoveToWindow {
    %orig;
    haoge_springtwelve_powerInstall((UIView *)self);
}
%end
%end

static void haoge_springtwelve_powerCollectHomeViews(UIView *view, Class homeClass, NSMutableArray *found) {
    if (!view) return;
    if ([view isKindOfClass:homeClass]) [found addObject:view];
    for (UIView *sub in view.subviews) haoge_springtwelve_powerCollectHomeViews(sub, homeClass, found);
}

static void haoge_springtwelve_powerInstallExisting(Class homeClass) {
    if (![NSThread isMainThread]) return;
    NSMutableArray *found = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            haoge_springtwelve_powerCollectHomeViews(window.rootViewController.view, homeClass, found);
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // SpringBoard also has legacy windows that do not belong to a UIWindowScene.
    for (UIWindow *window in UIApplication.sharedApplication.windows)
        haoge_springtwelve_powerCollectHomeViews(window, homeClass, found);
#pragma clang diagnostic pop
    for (UIView *home in found) haoge_springtwelve_powerInstall(home);
}

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
            ![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
        Class homeClass = NSClassFromString(@"SBRootFolderView");
        if (!homeClass || ![homeClass isSubclassOfClass:UIView.class] ||
            !class_getInstanceMethod(homeClass, @selector(didMoveToWindow))) {
            haoge_springtwelve_powerLog(@"home-class-or-hook-method-missing"); return;
        }
        %init(HaogeSpringTwelvePowerMenuHooks, HaogeSpringTwelvePowerMenuHomeView = homeClass);
        haoge_springtwelve_powerLog(@"hook-initialized");
        // Retroactive install: if the root folder view already moved to a window
        // before this tweak loaded, the didMoveToWindow hook never fires.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            haoge_springtwelve_powerInstallExisting(homeClass);
        });
    }
}
