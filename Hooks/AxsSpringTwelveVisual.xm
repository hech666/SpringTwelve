#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "AxsSpringTwelveSwitches.h"

@interface SBHomeGrabberView : UIView @end
@interface CSHomeAffordanceView : UIView
- (UIView *)dynamicHomeAffordance;
- (UIView *)staticHomeAffordance;
- (UIView *)alwaysOnHomeAffordance;
@end

// Override presentation only. Removing our animation reveals the system's current opacity.
static void AxsSpringTwelvePill(UIView *owner, UIView *pill, BOOL hide) {
    if (![pill isKindOfClass:UIView.class] || pill == owner) return;
    NSString *key = @"AxsSpringTwelve.hideHomeBar";
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
    if (type && *type == '@') AxsSpringTwelvePill(self, object_getIvar(self, ivar), AxsSpringTwelveOn(@"hideHomeBar"));
}
%end

static void AxsSpringTwelveAffordanceViews(CSHomeAffordanceView *owner, BOOL hide) {
    if ([owner respondsToSelector:@selector(dynamicHomeAffordance)]) AxsSpringTwelvePill(owner, owner.dynamicHomeAffordance, hide);
    if ([owner respondsToSelector:@selector(staticHomeAffordance)]) AxsSpringTwelvePill(owner, owner.staticHomeAffordance, hide);
    if ([owner respondsToSelector:@selector(alwaysOnHomeAffordance)]) AxsSpringTwelvePill(owner, owner.alwaysOnHomeAffordance, hide);
}

%hook CSHomeAffordanceView
- (void)layoutSubviews {
    %orig;
    AxsSpringTwelveAffordanceViews(self, AxsSpringTwelveOn(@"hideHomeBar"));
}
%end

@protocol AxsSpringTwelveIconModel <NSObject>
- (BOOL)isWidgetIcon;
- (BOOL)isWidgetStackIcon;
- (BOOL)isFolderIcon;
@end
@interface SBIconView : UIView
- (id<AxsSpringTwelveIconModel>)icon;
@end

static BOOL AxsSpringTwelveHideLabel(SBIconView *view) {
    if (![view respondsToSelector:@selector(icon)]) return NO;
    id<AxsSpringTwelveIconModel> icon = [view icon];
    if (([icon respondsToSelector:@selector(isWidgetIcon)] && [icon isWidgetIcon]) ||
        ([icon respondsToSelector:@selector(isWidgetStackIcon)] && [icon isWidgetStackIcon]) ||
        [icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")]) return AxsSpringTwelveOn(@"hideWidgetLabels");
    if (([icon respondsToSelector:@selector(isFolderIcon)] && [icon isFolderIcon]) ||
        [icon isKindOfClass:NSClassFromString(@"SBFolderIcon")] ||
        [icon isKindOfClass:NSClassFromString(@"SBApplicationIcon")]) return AxsSpringTwelveOn(@"hideHomeIconLabels");
    return NO;
}

%hook SBIconView
- (BOOL)_shouldShowLabel { return %orig && !AxsSpringTwelveHideLabel(self); }
%end
%hook SBHIconManager
- (BOOL)iconViewDisplaysLabel:(SBIconView *)view { return %orig && !AxsSpringTwelveHideLabel(view); }
%end
%hook SBIconController
- (BOOL)iconManager:(id)manager iconViewDisplaysLabel:(SBIconView *)view { return %orig && !AxsSpringTwelveHideLabel(view); }
%end
