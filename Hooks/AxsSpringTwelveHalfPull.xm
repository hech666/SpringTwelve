#import "AxsSpringTwelveSwitches.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>

@interface SBRootFolderView : UIView @end

@interface AxsSpringTwelveHalfPullTarget : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *homeView;
@property (nonatomic) NSInteger selectedSide; // 1 = left/Notification Center, 2 = right/Control Center
@property (nonatomic) CGFloat initialTranslationY;
@property (nonatomic) BOOL didPresent;
- (void)axs_springtwelve_handlePan:(UIPanGestureRecognizer *)recognizer;
@end

@implementation AxsSpringTwelveHalfPullTarget

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *homeView = self.homeView;
    UIView *hitView = touch.view;
    if (!homeView || !hitView || (hitView != homeView && ![hitView isDescendantOfView:homeView])) return NO;

    // Only accept blank home-screen space; never steal taps/drags from icons, widgets, controls, or the dock.
    for (UIView *view = hitView; view && view != homeView; view = view.superview) {
        if ([view isKindOfClass:UIControl.class]) return NO;
        NSString *name = NSStringFromClass(view.class);
        if ([name hasPrefix:@"SBIconView"] || [name hasPrefix:@"SBFolderIconView"] ||
            [name hasPrefix:@"SBIconLabel"] || [name hasPrefix:@"SBIconImage"] ||
            [name hasPrefix:@"SBWidget"] || [name hasPrefix:@"WGWidget"] ||
            [name hasPrefix:@"NCWidget"] || [name hasPrefix:@"SBDock"] ||
            [name hasPrefix:@"SBSearch"]) return NO;
    }

    CGPoint point = [touch locationInView:homeView];
    CGFloat width = CGRectGetWidth(homeView.bounds);
    if (width <= 1.0 || point.x < 0 || point.x > width) return NO;

    if (point.x < width * 0.5) {
        if (!AxsSpringTwelveOn(@"homeLeftPullDownNotificationCenter")) return NO;
        self.selectedSide = 1;
    } else {
        if (!AxsSpringTwelveOn(@"homeRightPullDownControlCenter")) return NO;
        self.selectedSide = 2;
    }
    self.didPresent = NO;
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (self.selectedSide == 1 && !AxsSpringTwelveOn(@"homeLeftPullDownNotificationCenter")) return NO;
    if (self.selectedSide == 2 && !AxsSpringTwelveOn(@"homeRightPullDownControlCenter")) return NO;
    if (self.selectedSide == 0 || ![recognizer isKindOfClass:UIPanGestureRecognizer.class]) return NO;

    CGPoint velocity = [(UIPanGestureRecognizer *)recognizer velocityInView:recognizer.view];
    return velocity.y > 125.0 && fabs(velocity.y) > fabs(velocity.x) * 1.25;
}

- (void)axs_springtwelve_presentControlCenter {
    Class controllerClass = NSClassFromString(@"SBControlCenterController");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    SEL presentWithCompletion = NSSelectorFromString(@"presentAnimated:completion:");
    SEL presentAnimated = NSSelectorFromString(@"presentAnimated:");
    if (!controllerClass || ![controllerClass respondsToSelector:shared]) return;
    id controller = ((id (*)(id, SEL))objc_msgSend)(controllerClass, shared);
    if ([controller respondsToSelector:presentWithCompletion]) {
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(controller, presentWithCompletion, YES, nil);
    } else if ([controller respondsToSelector:presentAnimated]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, presentAnimated, YES);
    }
}

- (void)axs_springtwelve_presentNotificationCenter {
    Class controllerClass = NSClassFromString(@"SBCoverSheetPresentationManager");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    SEL present = NSSelectorFromString(@"setCoverSheetPresented:animated:withCompletion:");
    if (!controllerClass || ![controllerClass respondsToSelector:shared]) return;
    id controller = ((id (*)(id, SEL))objc_msgSend)(controllerClass, shared);
    if (![controller respondsToSelector:present]) return;
    SEL shown = NSSelectorFromString(@"isPresented");
    if ([controller respondsToSelector:shown] && ((BOOL (*)(id, SEL))objc_msgSend)(controller, shown)) return;
    ((void (*)(id, SEL, BOOL, BOOL, id))objc_msgSend)(controller, present, YES, YES, nil);
}

- (void)axs_springtwelve_handlePan:(UIPanGestureRecognizer *)recognizer {
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
            self.didPresent = NO;
            self.initialTranslationY = [recognizer translationInView:recognizer.view].y;
            break;
        case UIGestureRecognizerStateChanged: {
            if (self.didPresent) break;
            CGFloat distance = [recognizer translationInView:recognizer.view].y - self.initialTranslationY;
            if (distance < 60.0) break;
            self.didPresent = YES;
            if (self.selectedSide == 1 && AxsSpringTwelveOn(@"homeLeftPullDownNotificationCenter")) {
                [self axs_springtwelve_presentNotificationCenter];
            } else if (self.selectedSide == 2 && AxsSpringTwelveOn(@"homeRightPullDownControlCenter")) {
                [self axs_springtwelve_presentControlCenter];
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            self.selectedSide = 0;
            self.didPresent = NO;
            break;
        default:
            break;
    }
}

@end

static const void *AxsSpringTwelveHalfPullTargetKey = &AxsSpringTwelveHalfPullTargetKey;

%group AxsSpringTwelveSpringBoardHalfPull
%hook SBRootFolderView
- (void)didMoveToWindow {
    %orig;
    if (!self.window || objc_getAssociatedObject(self, AxsSpringTwelveHalfPullTargetKey)) return;

    AxsSpringTwelveHalfPullTarget *target = [AxsSpringTwelveHalfPullTarget new];
    target.homeView = self;
    UIPanGestureRecognizer *recognizer = [[UIPanGestureRecognizer alloc]
        initWithTarget:target action:@selector(axs_springtwelve_handlePan:)];
    recognizer.maximumNumberOfTouches = 1;
    recognizer.delegate = target;
    recognizer.cancelsTouchesInView = NO;
    recognizer.delaysTouchesBegan = NO;
    recognizer.delaysTouchesEnded = NO;
    [self addGestureRecognizer:recognizer];
    objc_setAssociatedObject(self, AxsSpringTwelveHalfPullTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%end // AxsSpringTwelveSpringBoardHalfPull

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        Class rootView = NSClassFromString(@"SBRootFolderView");
        if (!rootView || ![rootView isSubclassOfClass:UIView.class] ||
            !class_getInstanceMethod(rootView, @selector(didMoveToWindow))) return;
        %init(AxsSpringTwelveSpringBoardHalfPull);
    }
}
