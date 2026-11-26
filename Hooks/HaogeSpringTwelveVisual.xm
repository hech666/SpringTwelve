#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "HaogeSpringTwelveSwitches.h"
%group HaogeSpringTwelveSpringBoardVisual

@interface SBHomeGrabberView : UIView @end
@interface CSHomeAffordanceView : UIView
- (UIView *)dynamicHomeAffordance;
- (UIView *)staticHomeAffordance;
- (UIView *)alwaysOnHomeAffordance;
@end

// Override presentation only. Removing our animation reveals the system's current opacity.
static void HaogeSpringTwelvePill(UIView *owner, UIView *pill, BOOL hide) {
    if (![pill isKindOfClass:UIView.class] || pill == owner) return;
    NSString *key = @"HaogeSpringTwelve.hideHomeBar";
    if (!hide) { [pill.layer removeAnimationForKey:key]; return; }
    if ([pill.layer animationForKey:key]) return;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = fade.toValue = @0;
    fade.duration = 1;
    fade.repeatCount = HUGE_VALF;
    [pill.layer addAnimation:fade forKey:key];
}

%hook SBHomeGrabberView
- (void)layoutSubviews {
    %orig;
    Ivar ivar = class_getInstanceVariable([self class], "_pillView");
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (type && *type == '@') HaogeSpringTwelvePill(self, object_getIvar(self, ivar), HaogeSpringTwelveOn(@"hideHomeBar"));
}
%end

static void HaogeSpringTwelveAffordanceViews(CSHomeAffordanceView *owner, BOOL hide) {
    if ([owner respondsToSelector:@selector(dynamicHomeAffordance)]) HaogeSpringTwelvePill(owner, owner.dynamicHomeAffordance, hide);
    if ([owner respondsToSelector:@selector(staticHomeAffordance)]) HaogeSpringTwelvePill(owner, owner.staticHomeAffordance, hide);
    if ([owner respondsToSelector:@selector(alwaysOnHomeAffordance)]) HaogeSpringTwelvePill(owner, owner.alwaysOnHomeAffordance, hide);
}

%hook CSHomeAffordanceView
- (void)layoutSubviews {
    %orig;
    HaogeSpringTwelveAffordanceViews(self, HaogeSpringTwelveOn(@"hideHomeBar"));
}
%end

@protocol HaogeSpringTwelveIconModel <NSObject>
- (BOOL)isWidgetIcon;
- (BOOL)isWidgetStackIcon;
- (BOOL)isFolderIcon;
@end
@interface SBIconView : UIView
- (id<HaogeSpringTwelveIconModel>)icon;
@end

static BOOL HaogeSpringTwelveHideLabel(SBIconView *view) {
    if (![view respondsToSelector:@selector(icon)]) return NO;
    id<HaogeSpringTwelveIconModel> icon = [view icon];
    if (([icon respondsToSelector:@selector(isWidgetIcon)] && [icon isWidgetIcon]) ||
        ([icon respondsToSelector:@selector(isWidgetStackIcon)] && [icon isWidgetStackIcon]) ||
        [icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")]) return HaogeSpringTwelveOn(@"hideWidgetLabels");
    if (([icon respondsToSelector:@selector(isFolderIcon)] && [icon isFolderIcon]) ||
        [icon isKindOfClass:NSClassFromString(@"SBFolderIcon")] ||
        [icon isKindOfClass:NSClassFromString(@"SBApplicationIcon")]) return HaogeSpringTwelveOn(@"hideHomeIconLabels");
    return NO;
}

%hook SBIconView
- (BOOL)_shouldShowLabel { return %orig && !HaogeSpringTwelveHideLabel(self); }
%end
%hook SBHIconManager
- (BOOL)iconViewDisplaysLabel:(SBIconView *)view { return %orig && !HaogeSpringTwelveHideLabel(view); }
%end
%hook SBIconController
- (BOOL)iconManager:(id)manager iconViewDisplaysLabel:(SBIconView *)view { return %orig && !HaogeSpringTwelveHideLabel(view); }
%end

%end // HaogeSpringTwelveSpringBoardVisual

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        NSArray<NSString *> *classes = @[@"SBHomeGrabberView", @"CSHomeAffordanceView", @"SBIconView",
            @"SBHIconManager", @"SBIconController"];
        for (NSString *name in classes) if (!NSClassFromString(name)) return;
        %init(HaogeSpringTwelveSpringBoardVisual);
    }
}
