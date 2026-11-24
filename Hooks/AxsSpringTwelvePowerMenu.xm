#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <signal.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
#import "AxsSpringTwelveSwitches.h"

// Clean-room UI only. No private power service, shell command, or fixed address.
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
    if (![NSThread isMainThread] || !AxsSpringTwelveOn(@"lsPowerMenuOnDesktop")) return NO;
    UIWindow *window = home.window;
    if (!home || !window || !window.windowScene || window.hidden || window.alpha < 0.99 ||
        window.windowLevel != UIWindowLevelNormal ||
        (needsKeyWindow && !window.isKeyWindow) ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        window.windowScene.activationState != UISceneActivationStateForegroundActive) return NO;
    for (UIView *view = home; view; view = view.superview) {
        if (view.hidden || view.alpha < 0.99 || !view.userInteractionEnabled) return NO;
    }
    // Unknown private state is unsupported, never assumed unlocked/non-editing.
    BOOL locked = YES, editing = YES;
    if (!axs_springtwelve_powerReadBool(axs_springtwelve_powerShared(@"SBLockScreenManager"),
                                     @"isUILocked", &locked) || locked) return NO;
    if (!axs_springtwelve_powerReadBool(axs_springtwelve_powerShared(@"SBIconController"),
                                     @"isEditing", &editing) || editing) return NO;
    if (needsKeyWindow && window.rootViewController.presentedViewController) return NO;
    return YES;
}

static BOOL axs_springtwelve_powerBlankPath(UIView *leaf, UIView *home) {
    // Deliberate allowlist: icons, widgets, folders, dock, controls, and unknown
    // hit-test wrappers fail closed. A real icon-list page must be in the path.
    BOOL sawList = NO;
    for (UIView *view = leaf; view && view != home; view = view.superview) {
        NSString *name = NSStringFromClass(view.class);
        BOOL list = [name isEqualToString:@"SBIconListView"] ||
                    [name isEqualToString:@"SBRootIconListView"];
        if (!list && ![name isEqualToString:@"UIView"] &&
            ![name isEqualToString:@"UIScrollView"] &&
            ![name isEqualToString:@"SBIconScrollView"]) return NO;
        if ([view isKindOfClass:UIControl.class] || view.hidden || view.alpha < 0.99) return NO;
        if ([view isKindOfClass:UIScrollView.class]) {
            UIScrollView *scroll = (UIScrollView *)view;
            if (scroll.dragging || scroll.decelerating) return NO;
        }
        sawList |= list;
        if (view.superview == home) return sawList;
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

@interface AxsSpringTwelvePowerMenuController : UIViewController
@property(nonatomic, weak) UIView *axs_springtwelve_home;
@property(nonatomic, weak) UIWindow *axs_springtwelve_previousWindow;
@property(nonatomic, strong) UIWindow *axs_springtwelve_overlay;
@property(nonatomic, strong) UILabel *axs_springtwelve_status;
@property(nonatomic) int axs_springtwelve_pendingSignal;
- (void)axs_springtwelve_close;
- (void)axs_springtwelve_confirm:(UIButton *)sender;
@end

@implementation AxsSpringTwelvePowerMenuController
- (BOOL)axs_springtwelve_contextValid {
    return AxsSpringTwelvePowerMenuActive == self &&
        self.axs_springtwelve_overlay.isKeyWindow &&
        self.axs_springtwelve_home.window == self.axs_springtwelve_previousWindow &&
        axs_springtwelve_powerHomeReady(self.axs_springtwelve_home, NO);
}

- (void)axs_springtwelve_close {
    self.axs_springtwelve_pendingSignal = 0;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    UIWindow *overlay = self.axs_springtwelve_overlay;
    BOOL restoreKey = overlay.isKeyWindow;
    overlay.hidden = YES;
    overlay.rootViewController = nil;
    self.axs_springtwelve_overlay = nil;
    UIWindow *previous = self.axs_springtwelve_previousWindow;
    if (restoreKey && previous && !previous.hidden &&
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
        previous.windowScene.activationState == UISceneActivationStateForegroundActive) {
        [previous makeKeyWindow];
    }
    if (AxsSpringTwelvePowerMenuActive == self) AxsSpringTwelvePowerMenuActive = nil;
}

- (void)axs_springtwelve_invalidate:(NSNotification *)notification {
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
    [background addSubview:panel];
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:scroll];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    UILabel *title = [UILabel new];
    title.text = @"桌面电源菜单";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.numberOfLines = 0;
    title.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:title];
    UILabel *status = [UILabel new];
    status.text = @"Every supported action requires a separate confirmation. Unsupported actions are disabled; no backend is called.";
    status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    status.numberOfLines = 0;
    status.textAlignment = NSTextAlignmentCenter;
    self.axs_springtwelve_status = status;
    [stack addArrangedSubview:status];
    NSArray<NSString *> *titles = @[@"Quick respring (SIGTERM)", @"Force respring (SIGKILL)",
        @"Request safe mode (SIGSEGV)", @"Restart desktop — unsupported",
        @"Reboot userspace — unsupported", @"Reboot — unsupported", @"Shut down — unsupported"];
    const int signals[] = {SIGTERM, SIGKILL, SIGSEGV};
    for (NSUInteger index = 0; index < titles.count; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[index] forState:UIControlStateNormal];
        button.titleLabel.numberOfLines = 0;
        button.titleLabel.textAlignment = NSTextAlignmentCenter;
        button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        button.enabled = index < 3;
        if (index < 3) {
            button.tag = signals[index];
            [button setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
            [button addTarget:self action:@selector(axs_springtwelve_confirm:) forControlEvents:UIControlEventTouchUpInside];
        }
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
        [stack addArrangedSubview:button];
    }
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancel.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [cancel addTarget:self action:@selector(axs_springtwelve_close) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:cancel];
    UILayoutGuide *safe = background.safeAreaLayoutGuide;
    NSLayoutConstraint *preferredHeight = [panel.heightAnchor constraintEqualToConstant:590];
    preferredHeight.priority = UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *preferredWidth = [panel.widthAnchor constraintEqualToConstant:400];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [panel.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [panel.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor], preferredWidth,
        [panel.widthAnchor constraintLessThanOrEqualToAnchor:safe.widthAnchor constant:-32],
        [panel.heightAnchor constraintLessThanOrEqualToAnchor:safe.heightAnchor constant:-24], preferredHeight,
        [scroll.topAnchor constraintEqualToAnchor:panel.topAnchor constant:16],
        [scroll.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-16],
        [scroll.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    background.accessibilityViewIsModal = YES;
}

- (BOOL)accessibilityPerformEscape {
    [self axs_springtwelve_close];
    return YES;
}

- (void)axs_springtwelve_confirm:(UIButton *)sender {
    if (![self axs_springtwelve_contextValid]) { [self axs_springtwelve_close]; return; }
    if (self.presentedViewController || self.axs_springtwelve_pendingSignal) return;
    int selected = (int)sender.tag;
    if (selected != SIGTERM && selected != SIGKILL && selected != SIGSEGV) return;
    NSString *message = selected == SIGSEGV
        ? @"This intentionally crashes SpringBoard with SIGSEGV (11). Safe mode depends on the jailbreak crash handler and is not guaranteed. Unsaved UI state may be lost. Continue?"
        : (selected == SIGKILL
            ? @"Force-terminate SpringBoard with SIGKILL (9)? This may lose unsaved UI state. Its restart depends on the system supervisor."
            : @"Terminate SpringBoard with SIGTERM (15)? Its restart depends on the system supervisor. Unsaved UI state may be lost.");
    UIAlertController *confirmation = [UIAlertController alertControllerWithTitle:@"Confirm desktop action"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    self.axs_springtwelve_pendingSignal = selected;
    __weak AxsSpringTwelvePowerMenuController *weakSelf = self;
    __weak UIAlertController *weakConfirmation = confirmation;
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        weakSelf.axs_springtwelve_pendingSignal = 0;
    }]];
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Confirm" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        AxsSpringTwelvePowerMenuController *controller = weakSelf;
        // The ONLY execution site: explicit destructive confirmation, live context,
        // matching one-shot request, foreground SpringBoard, and self PID only.
        if (!controller || ![NSThread isMainThread]) return;
        BOOL authorized = [controller axs_springtwelve_contextValid] &&
            controller.presentedViewController == weakConfirmation &&
            controller.axs_springtwelve_pendingSignal == selected;
        controller.axs_springtwelve_pendingSignal = 0;
        if (!authorized) { [controller axs_springtwelve_close]; return; }
        if (kill(getpid(), selected) == -1) {
            int error = errno;
            controller.axs_springtwelve_status.text = [NSString stringWithFormat:@"The signal request failed (errno %d). No fallback was attempted.", error];
        } else {
            [controller axs_springtwelve_close];
        }
    }]];
    [self presentViewController:confirmation animated:YES completion:nil];
}
@end

@interface AxsSpringTwelvePowerMenuTarget : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView *axs_springtwelve_home;
@end

@implementation AxsSpringTwelvePowerMenuTarget
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *home = self.axs_springtwelve_home;
    return !AxsSpringTwelvePowerMenuActive && touch.type == UITouchTypeDirect &&
        axs_springtwelve_powerBlankPath(touch.view, home) &&
        axs_springtwelve_powerBlankPoint(home, [touch locationInView:home]);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    return !AxsSpringTwelvePowerMenuActive &&
        axs_springtwelve_powerBlankPoint(self.axs_springtwelve_home,
            [recognizer locationInView:self.axs_springtwelve_home]);
}

- (void)axs_springtwelve_longPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan || AxsSpringTwelvePowerMenuActive) return;
    UIView *home = self.axs_springtwelve_home;
    if (!axs_springtwelve_powerBlankPoint(home, [recognizer locationInView:home])) return;
    AxsSpringTwelvePowerMenuController *controller = [AxsSpringTwelvePowerMenuController new];
    controller.axs_springtwelve_home = home;
    controller.axs_springtwelve_previousWindow = home.window;
    UIWindow *overlay = [[UIWindow alloc] initWithWindowScene:home.window.windowScene];
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
}

%group AxsSpringTwelvePowerMenuHooks
%hook AxsSpringTwelvePowerMenuHomeView
- (void)didMoveToWindow {
    %orig;
    axs_springtwelve_powerInstall((UIView *)self);
}
%end
%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
            ![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
        Class homeClass = NSClassFromString(@"SBRootFolderView");
        if (!homeClass || ![homeClass isSubclassOfClass:UIView.class] ||
            !class_getInstanceMethod(homeClass, @selector(didMoveToWindow))) return;
        %init(AxsSpringTwelvePowerMenuHooks, AxsSpringTwelvePowerMenuHomeView = homeClass);
    }
}
