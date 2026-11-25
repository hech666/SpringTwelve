#import <Foundation/Foundation.h>
#import "AxsSpringTwelveSwitches.h"

// Verified against SystemBox 1.5-8end and the standalone LockButtons test.
// Install independently of the initial preference state so later changes work.
%group AxsSpringTwelveLockButtons
%hook CSQuickActionsViewController
- (BOOL)hasFlashlight {
    return AxsSpringTwelveOn(@"disableFlashlight") ? NO : %orig;
}
- (BOOL)hasCamera {
    return AxsSpringTwelveOn(@"disableCamera") ? NO : %orig;
}
%end
%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        Class cls = NSClassFromString(@"CSQuickActionsViewController");
        if (cls && [cls instancesRespondToSelector:@selector(hasFlashlight)] &&
            [cls instancesRespondToSelector:@selector(hasCamera)]) {
            %init(AxsSpringTwelveLockButtons);
        }
    }
}
