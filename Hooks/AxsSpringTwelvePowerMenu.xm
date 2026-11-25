#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <signal.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
#import <fcntl.h>
#import "AxsSpringTwelveSwitches.h"
#import "AxsSpringTwelvePaths.h"
#import "AxsSpringTwelvePowerActions.h"

// Fixed event names only: no coordinates, identifiers, text, or user content.
static NSMutableDictionary<NSString *, NSDate *> *AxsSpringTwelvePowerMenuLogTimes;
static void axs_springtwelve_powerLog(NSString *event) {
    if (![NSThread isMainThread]) return;
    if (!AxsSpringTwelvePowerMenuLogTimes) AxsSpringTwelvePowerMenuLogTimes = [NSMutableDictionary dictionary];
    NSDate *now = [NSDate date];
    NSDate *last = AxsSpringTwelvePowerMenuLogTimes[event];
    if (last && [now timeIntervalSinceDate:last] < 30.0) return;
    AxsSpringTwelvePowerMenuLogTimes[event] = now;
    @try {
        NSString *directory = [axs_springtwelve_recordingDirectory() stringByAppendingPathComponent:@"Diagnostics"];
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
@class AxsSpringTwelvePowerMenuController;
static AxsSpringTwelvePowerMenuController *AxsSpringTwelvePowerMenuActive;
static char AxsSpringTwelvePowerMenuTargetKey;

static id axs_springtwelve_powerShared(NSString *className) {
    Class cls = NSClassFromString(className);
    SEL selector = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [cls methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, selector);
}

static BOOL axs_springtwelve_powerReadBool(id object, NSString *name, BOOL *value) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2) return NO;
    const char *type = signature.methodReturnType;
    if (strcmp(type, @encode(BOOL)) && strcmp(type, "B") && strcmp(type, "c")) return NO;
    *value = ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    return YES;
}

static BOOL axs_springtwelve_powerHomeReady(UIView *home, BOOL needsKeyWindow) {
    if (![NSThread isMainThread]) return NO;
    if (!AxsSpringTwelveOn(@"lsPowerMenuOnDesktop")) { axs_springtwelve_powerLog(@"disabled"); return NO; }
    UIWindow *window = home.window;
    UIWindowScene *scene = window.windowScene;
    if (!home || !window || window.hidden || window.alpha < 0.99 ||
        window.windowLevel >= UIWindowLevelAlert ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        (scene && scene.activationState != UISceneActivationStateForegroundActive)) {
        axs_springtwelve_powerLog(@"home-context-rejected"); return NO;
    }
    for (UIView *view = home; view; view = view.superview) {
        if (view.hidden || view.alpha < 0.99 || !view.userInteractionEnabled) return NO;
    }
    // Fail only on a positively confirmed dangerous state. An unknown private
    // selector must not permanently disable the menu: the gesture itself only
    // fires on the home screen, so an unreadable lock/edit state is treated as
    // clear rather than failing closed.
    BOOL locked = NO, editing = NO;
    if (axs_springtwelve_powerReadBool(axs_springtwelve_powerShared(@"SBLockScreenManager"),
                                     @"isUILocked", &locked) && locked) return NO;
    if (axs_springtwelve_powerReadBool(axs_springtwelve_powerShared(@"SBIconController"),
                                     @"isEditing", &editing) && editing) return NO;
    if (needsKeyWindow && window.rootViewController.presentedViewController) return NO;
    return YES;
}

static BOOL axs_springtwelve_powerBlankPath(UIView *leaf, UIView *home) {
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

static BOOL axs_springtwelve_powerBlankPoint(UIView *home, CGPoint point) {
    if (!axs_springtwelve_powerHomeReady(home, YES) ||
        !CGRectContainsPoint(UIEdgeInsetsInsetRect(home.bounds, home.safeAreaInsets), point)) return NO;
    UIWindow *window = home.window;
    UIView *hit = [window hitTest:[home convertPoint:point toView:window] withEvent:nil];
    return axs_springtwelve_powerBlankPath(hit, home);
}

// Scale the previous effective size (including small-screen caps), not only
// its preferred constants. Both cards share the exact on-screen center.
static NSArray<NSLayoutConstraint *> *axs_springtwelve_powerCardConstraints(UIView *card, UIView *background, CGFloat originalHeight) {
    const CGFloat widthScale = 2.0 / 3.0, heightScale = 3.0 / 4.0;
    UILayoutGuide *safe = background.safeAreaLayoutGuide;
    NSLayoutConstraint *width = [card.widthAnchor constraintEqualToConstant:400.0 * widthScale];
    NSLayoutConstraint *height = [card.heightAnchor constraintEqualToConstant:originalHeight * heightScale];
    width.priority = height.priority = UILayoutPriorityDefaultHigh;
    return @[
        [card.centerXAnchor constraintEqualToAnchor:background.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:background.centerYAnchor], width, height,
        [card.widthAnchor constraintLessThanOrEqualToAnchor:safe.widthAnchor multiplier:widthScale constant:-32.0 * widthScale],
        [card.heightAnchor constraintLessThanOrEqualToAnchor:safe.heightAnchor multiplier:heightScale constant:-24.0 * heightScale]
    ];
}

@interface AxsSpringTwelvePowerMenuController : UIViewController
@property(nonatomic, weak) UIView *axs_springtwelve_home;
@property(nonatomic, weak) UIWindow *axs_springtwelve_homeWindow;
@property(nonatomic, weak) UIWindow *axs_springtwelve_previousWindow;
@property(nonatomic, strong) UIWindow *axs_springtwelve_overlay;
@property(nonatomic, strong) UIView *axs_springtwelve_menuPanel;
@property(nonatomic, strong) UILabel *axs_springtwelve_status;
@property(nonatomic) NSInteger axs_springtwelve_pendingAction;
@property(nonatomic) BOOL axs_springtwelve_closing;
@property(nonatomic) BOOL axs_springtwelve_executing;
@property(nonatomic, strong) UIView *axs_springtwelve_confirmation;
@property(nonatomic, strong) NSUUID *axs_springtwelve_confirmationToken;
- (void)axs_springtwelve_close;
- (void)axs_springtwelve_confirm:(UIButton *)sender;
@end

@implementation AxsSpringTwelvePowerMenuController
- (BOOL)axs_springtwelve_contextValid {
    // The confirmation card stays inside this window: no modal/key transition
    // is part of authorization. Any actual key loss invalidates the request.
    UIWindow *overlay = self.axs_springtwelve_overlay;
    return !self.axs_springtwelve_closing && AxsSpringTwelvePowerMenuActive == self &&
        overlay && !overlay.hidden && overlay.isKeyWindow &&
        self.axs_springtwelve_home.window == self.axs_springtwelve_homeWindow &&
        axs_springtwelve_powerHomeReady(self.axs_springtwelve_home, NO);
}

- (void)axs_springtwelve_close {
    if (self.axs_springtwelve_closing) return;
    self.axs_springtwelve_closing = YES;
    self.axs_springtwelve_pendingAction = 0;
    self.axs_springtwelve_confirmationToken = nil;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (AxsSpringTwelvePowerMenuActive == self) AxsSpringTwelvePowerMenuActive = nil;
    [self.axs_springtwelve_confirmation removeFromSuperview];
    self.axs_springtwelve_confirmation = nil;
    UIWindow *overlay = self.axs_springtwelve_overlay;
    BOOL restoreKey = overlay.isKeyWindow;
    overlay.hidden = YES;
    overlay.rootViewController = nil;
    self.axs_springtwelve_overlay = nil;
    UIWindow *previous = self.axs_springtwelve_previousWindow;
    if (restoreKey && previous && !previous.hidden &&
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
        (!previous.windowScene || previous.windowScene.activationState == UISceneActivationStateForegroundActive)) {
        [previous makeKeyWindow];
    }
    if (AxsSpringTwelvePowerMenuActive == self) AxsSpringTwelvePowerMenuActive = nil;
}

- (void)axs_springtwelve_invalidate:(NSNotification *)notification {
    axs_springtwelve_powerLog(@"menu-context-invalidated");
    [self axs_springtwelve_close];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)loadView {
    UIView *background = [UIView new];
    background.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    self.view = background;
    UIView *panel = [UIView new];
    panel.backgroundColor = UIColor.secondarySystemBackgroundColor;
    panel.layer.cornerRadius = 18.0;
    panel.clipsToBounds = YES;
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    self.axs_springtwelve_menuPanel = panel;
    [background addSubview:panel];
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:scroll];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    UILabel *title = [UILabel new];
    title.text = @"桌面电源菜单";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.adjustsFontForContentSizeCategory = YES;
    title.numberOfLines = 0;
    title.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:title];
    UILabel *status = [UILabel new];
    // No introductory text or reserved blank space. Reveal only live results.
    status.hidden = YES;
    status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    status.adjustsFontForContentSizeCategory = YES;
    status.numberOfLines = 0;
    status.textAlignment = NSTextAlignmentCenter;
    self.axs_springtwelve_status = status;
    [stack addArrangedSubview:status];
    UIStackView *actions = [UIStackView new];
    actions.axis = UILayoutConstraintAxisVertical;
    actions.distribution = UIStackViewDistributionFillEqually;
    [actions setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [stack addArrangedSubview:actions];
    NSArray<NSNumber *> *selections = @[@(AxsSpringTwelvePowerActionQuickRespring),
        @(AxsSpringTwelvePowerActionForceRespring), @(AxsSpringTwelvePowerActionRespring),
        @(AxsSpringTwelvePowerActionUserspaceReboot), @(AxsSpringTwelvePowerActionReboot),
        @(AxsSpringTwelvePowerActionShutdown)];
    for (NSNumber *selection in selections) {
        AxsSpringTwelvePowerAction action = (AxsSpringTwelvePowerAction)selection.integerValue;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        BOOL available = axs_springtwelve_powerActionAvailable(action);
        NSString *title = axs_springtwelve_powerActionTitle(action);
        if (!available) title = [title stringByAppendingString:@" — 当前环境不可用"];
        [button setTitle:title forState:UIControlStateNormal];
        button.titleLabel.numberOfLines = 0;
        button.titleLabel.textAlignment = NSTextAlignmentCenter;
        button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        button.titleLabel.adjustsFontForContentSizeCategory = YES;
        button.enabled = available;
        button.tag = action;
        [button setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
        [button addTarget:self action:@selector(axs_springtwelve_confirm:) forControlEvents:UIControlEventTouchUpInside];
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
        [actions addArrangedSubview:button];
        UIView *divider = [UIView new];
        divider.backgroundColor = UIColor.separatorColor;
        divider.userInteractionEnabled = NO;
        divider.isAccessibilityElement = NO;
        divider.translatesAutoresizingMaskIntoConstraints = NO;
        [button addSubview:divider];
        [NSLayoutConstraint activateConstraints:@[
            [divider.heightAnchor constraintEqualToConstant:0.5],
            [divider.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:4],
            [divider.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-4],
            [divider.bottomAnchor constraintEqualToAnchor:button.bottomAnchor]
        ]];
    }
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"取消" forState:UIControlStateNormal];
    cancel.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    cancel.titleLabel.adjustsFontForContentSizeCategory = YES;
    [cancel.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [cancel addTarget:self action:@selector(axs_springtwelve_close) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:cancel];
    [NSLayoutConstraint activateConstraints:axs_springtwelve_powerCardConstraints(panel, background, 590.0)];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:panel.topAnchor constant:16],
        [scroll.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-16],
        [scroll.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [stack.heightAnchor constraintGreaterThanOrEqualToAnchor:scroll.frameLayoutGuide.heightAnchor]
    ]];
    background.accessibilityViewIsModal = YES;
}

- (void)axs_springtwelve_setStatus:(NSString *)message {
    self.axs_springtwelve_status.text = message;
    self.axs_springtwelve_status.hidden = message.length == 0;
}

- (void)axs_springtwelve_cancelConfirmation {
    self.axs_springtwelve_confirmationToken = nil;
    self.axs_springtwelve_pendingAction = 0;
    [self.axs_springtwelve_confirmation removeFromSuperview];
    self.axs_springtwelve_confirmation = nil;
    self.axs_springtwelve_menuPanel.hidden = NO;
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.axs_springtwelve_menuPanel);
}

- (BOOL)accessibilityPerformEscape {
    if (self.axs_springtwelve_confirmation) [self axs_springtwelve_cancelConfirmation];
    else [self axs_springtwelve_close];
    return YES;
}

- (void)axs_springtwelve_confirm:(UIButton *)sender {
    if (![self axs_springtwelve_contextValid]) { [self axs_springtwelve_close]; return; }
    if (self.axs_springtwelve_confirmation || self.axs_springtwelve_pendingAction || self.axs_springtwelve_executing) return;
    AxsSpringTwelvePowerAction selected = (AxsSpringTwelvePowerAction)sender.tag;
    if (!axs_springtwelve_powerActionAvailable(selected)) {
        [self axs_springtwelve_setStatus:@"此操作所需的系统接口或提权工具当前不可用，请检查安装后重新打开面板。"];
        return;
    }
    NSUUID *token = NSUUID.UUID;
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 18.0;
    card.clipsToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    self.axs_springtwelve_confirmation = card;
    self.axs_springtwelve_confirmationToken = token;
    self.axs_springtwelve_pendingAction = selected;
    self.axs_springtwelve_menuPanel.hidden = YES;
    [self.view addSubview:card];
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:scroll];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    UILabel *heading = [UILabel new];
    heading.text = [@"确认：" stringByAppendingString:axs_springtwelve_powerActionTitle(selected)];
    heading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    heading.adjustsFontForContentSizeCategory = YES;
    heading.numberOfLines = 0;
    heading.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:heading];
    UILabel *message = [UILabel new];
    message.text = axs_springtwelve_powerActionWarning(selected);
    message.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    message.adjustsFontForContentSizeCategory = YES;
    message.numberOfLines = 0;
    [stack addArrangedSubview:message];
    __weak AxsSpringTwelvePowerMenuController *weakSelf = self;
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"取消" forState:UIControlStateNormal];
    [cancel addAction:[UIAction actionWithHandler:^(__unused UIAction *event) {
        AxsSpringTwelvePowerMenuController *controller = weakSelf;
        if (!controller || controller.axs_springtwelve_closing ||
            controller.axs_springtwelve_confirmationToken != token ||
            controller.axs_springtwelve_pendingAction != selected) return;
        [controller axs_springtwelve_cancelConfirmation];
        axs_springtwelve_powerLog(@"confirmation-cancelled");
    }] forControlEvents:UIControlEventTouchUpInside];
    UIButton *confirm = [UIButton buttonWithType:UIButtonTypeSystem];
    [confirm setTitle:@"确认执行" forState:UIControlStateNormal];
    [confirm setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    [confirm addAction:[UIAction actionWithHandler:^(__unused UIAction *event) {
        AxsSpringTwelvePowerMenuController *controller = weakSelf;
        // A stale event must not clear or close a newer request.
        if (!controller || controller.axs_springtwelve_closing ||
            controller.axs_springtwelve_confirmationToken != token ||
            controller.axs_springtwelve_pendingAction != selected) return;
        BOOL authorized = [controller axs_springtwelve_contextValid] &&
            controller.axs_springtwelve_confirmation.superview == controller.view &&
            !controller.axs_springtwelve_confirmation.hidden;
        [controller axs_springtwelve_cancelConfirmation];
        if (!authorized) {
            axs_springtwelve_powerLog(@"confirmation-rejected");
            [controller axs_springtwelve_close]; return;
        }
        controller.axs_springtwelve_executing = YES;
        [controller axs_springtwelve_setStatus:@"正在提交操作，请勿重复点击。"];
        NSDictionary<NSNumber *, NSString *> *events = @{
            @(AxsSpringTwelvePowerActionQuickRespring): @"quick-respring-request",
            @(AxsSpringTwelvePowerActionForceRespring): @"force-respring-request",
            @(AxsSpringTwelvePowerActionRespring): @"respring-request",
            @(AxsSpringTwelvePowerActionUserspaceReboot): @"userspace-reboot-request",
            @(AxsSpringTwelvePowerActionReboot): @"device-reboot-request",
            @(AxsSpringTwelvePowerActionShutdown): @"shutdown-request"
        };
        axs_springtwelve_powerLog(events[@(selected)]);
        axs_springtwelve_powerActionRequest(selected, ^(NSString *error) {
            AxsSpringTwelvePowerMenuController *live = weakSelf;
            if (!live || live.axs_springtwelve_closing || AxsSpringTwelvePowerMenuActive != live) return;
            if (error) {
                live.axs_springtwelve_executing = NO;
                [live axs_springtwelve_setStatus:error];
                axs_springtwelve_powerLog(@"action-request-error");
            } else {
                [live axs_springtwelve_setStatus:@"操作请求已提交。若设备未响应，请关闭面板并导出功能诊断；提交不代表重启已经完成。"];
                axs_springtwelve_powerLog(@"action-request-submitted");
            }
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, live.axs_springtwelve_status.text);
        });
    }] forControlEvents:UIControlEventTouchUpInside];
    for (UIButton *button in @[confirm, cancel]) {
        button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        button.titleLabel.adjustsFontForContentSizeCategory = YES;
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
        [stack addArrangedSubview:button];
    }
    [NSLayoutConstraint activateConstraints:axs_springtwelve_powerCardConstraints(card, self.view, 360.0)];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [scroll.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [scroll.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    axs_springtwelve_powerLog(@"confirmation-presented");
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, heading);
}

@end

@interface AxsSpringTwelvePowerMenuTarget : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView *axs_springtwelve_home;
@end

@implementation AxsSpringTwelvePowerMenuTarget
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *home = self.axs_springtwelve_home;
    if (AxsSpringTwelvePowerMenuActive || touch.type != UITouchTypeDirect) return NO;
    BOOL blankPath = axs_springtwelve_powerBlankPath(touch.view, home);
    if (!blankPath) { axs_springtwelve_powerLog(@"touch-not-blank"); return NO; }
    BOOL blankPoint = axs_springtwelve_powerBlankPoint(home, [touch locationInView:home]);
    if (!blankPoint) axs_springtwelve_powerLog(@"touch-context-or-point-rejected");
    return blankPoint;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (AxsSpringTwelvePowerMenuActive) return NO;
    BOOL accepted = axs_springtwelve_powerBlankPoint(self.axs_springtwelve_home,
        [recognizer locationInView:self.axs_springtwelve_home]);
    if (!accepted) axs_springtwelve_powerLog(@"gesture-should-begin-rejected");
    return accepted;
}

- (void)axs_springtwelve_longPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan || AxsSpringTwelvePowerMenuActive) return;
    UIView *home = self.axs_springtwelve_home;
    if (!axs_springtwelve_powerBlankPoint(home, [recognizer locationInView:home])) {
        axs_springtwelve_powerLog(@"long-press-rejected-at-begin"); return;
    }
    axs_springtwelve_powerLog(@"menu-present-request");
    AxsSpringTwelvePowerMenuController *controller = [AxsSpringTwelvePowerMenuController new];
    controller.axs_springtwelve_home = home;
    controller.axs_springtwelve_homeWindow = home.window;
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
    controller.axs_springtwelve_previousWindow = originalKey ?: home.window;
    UIWindowScene *scene = home.window.windowScene;
    UIWindow *overlay = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:home.window.bounds];
    overlay.frame = home.window.bounds;
    overlay.windowLevel = UIWindowLevelNormal + 1.0; // Never an alert/lock-screen level.
    overlay.backgroundColor = UIColor.clearColor;
    overlay.rootViewController = controller;
    controller.axs_springtwelve_overlay = overlay;
    AxsSpringTwelvePowerMenuActive = controller;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:controller selector:@selector(axs_springtwelve_invalidate:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:controller selector:@selector(axs_springtwelve_invalidate:)
        name:UISceneWillDeactivateNotification object:home.window.windowScene];
    [center addObserver:controller selector:@selector(axs_springtwelve_invalidate:)
        name:UIWindowDidResignKeyNotification object:overlay];
    [center addObserver:controller selector:@selector(axs_springtwelve_invalidate:)
        name:UIWindowDidBecomeHiddenNotification object:home.window];
    [overlay makeKeyAndVisible];
}
@end

static void axs_springtwelve_powerInstall(UIView *home) {
    if (![NSThread isMainThread]) return;
    if (!home.window) {
        if (AxsSpringTwelvePowerMenuActive.axs_springtwelve_home == home)
            [AxsSpringTwelvePowerMenuActive axs_springtwelve_close];
        return;
    }
    if (objc_getAssociatedObject(home, &AxsSpringTwelvePowerMenuTargetKey)) return;
    AxsSpringTwelvePowerMenuTarget *target = [AxsSpringTwelvePowerMenuTarget new];
    target.axs_springtwelve_home = home;
    UILongPressGestureRecognizer *recognizer = [[UILongPressGestureRecognizer alloc]
        initWithTarget:target action:@selector(axs_springtwelve_longPress:)];
    recognizer.minimumPressDuration = 0.45;
    recognizer.allowableMovement = 8.0;
    recognizer.numberOfTouchesRequired = 1;
    recognizer.cancelsTouchesInView = YES;
    recognizer.delaysTouchesBegan = NO;
    recognizer.delaysTouchesEnded = NO;
    recognizer.delegate = target;
    objc_setAssociatedObject(home, &AxsSpringTwelvePowerMenuTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [home addGestureRecognizer:recognizer];
    axs_springtwelve_powerLog(@"gesture-installed");
}

%group AxsSpringTwelvePowerMenuHooks
%hook AxsSpringTwelvePowerMenuHomeView
- (void)didMoveToWindow {
    %orig;
    axs_springtwelve_powerInstall((UIView *)self);
}
%end
%end

static void axs_springtwelve_powerCollectHomeViews(UIView *view, Class homeClass, NSMutableArray *found) {
    if (!view) return;
    if ([view isKindOfClass:homeClass]) [found addObject:view];
    for (UIView *sub in view.subviews) axs_springtwelve_powerCollectHomeViews(sub, homeClass, found);
}

static void axs_springtwelve_powerInstallExisting(Class homeClass) {
    if (![NSThread isMainThread]) return;
    NSMutableArray *found = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            axs_springtwelve_powerCollectHomeViews(window.rootViewController.view, homeClass, found);
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // SpringBoard also has legacy windows that do not belong to a UIWindowScene.
    for (UIWindow *window in UIApplication.sharedApplication.windows)
        axs_springtwelve_powerCollectHomeViews(window, homeClass, found);
#pragma clang diagnostic pop
    for (UIView *home in found) axs_springtwelve_powerInstall(home);
}

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
            ![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
        Class homeClass = NSClassFromString(@"SBRootFolderView");
        if (!homeClass || ![homeClass isSubclassOfClass:UIView.class] ||
            !class_getInstanceMethod(homeClass, @selector(didMoveToWindow))) {
            axs_springtwelve_powerLog(@"home-class-or-hook-method-missing"); return;
        }
        %init(AxsSpringTwelvePowerMenuHooks, AxsSpringTwelvePowerMenuHomeView = homeClass);
        axs_springtwelve_powerLog(@"hook-initialized");
        // Retroactive install: if the root folder view already moved to a window
        // before this tweak loaded, the didMoveToWindow hook never fires.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            axs_springtwelve_powerInstallExisting(homeClass);
        });
    }
}
