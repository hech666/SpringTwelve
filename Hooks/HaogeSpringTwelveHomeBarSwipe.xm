// Adapted from DisableBottomHomeBarSwipe.xm: preserve the original 64-bit destination.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <string.h>
#import "HaogeSpringTwelveSwitches.h"

static BOOL HaogeSpringTwelveHomeBarSwipeMethodMatches(Class target) {
    if (!target || sizeof(NSInteger) != 8 || sizeof(void *) != 8) return NO;
    Method method = class_getInstanceMethod(target, NSSelectorFromString(@"currentFinalDestination"));
    // Only self and _cmd: never install against an argument-bearing or changed ABI.
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char returnType[8] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    BOOL signed64 = (strcmp(returnType, "q") == 0 && sizeof(long long) == 8) ||
                    (strcmp(returnType, "l") == 0 && sizeof(long) == 8);
    if (!signed64) return NO;
    char selfType[8] = {0}, selectorType[8] = {0};
    method_getArgumentType(method, 0, selfType, sizeof(selfType));
    method_getArgumentType(method, 1, selectorType, sizeof(selectorType));
    return strcmp(selfType, "@") == 0 && strcmp(selectorType, ":") == 0;
}

%group HaogeSpringTwelveHomeBarSwipe
%hook SBHomeGestureFinalDestinationSwitcherModifier

- (NSInteger)currentFinalDestination {
    NSInteger destination = %orig;
    if (HaogeSpringTwelveOn(@"disableBottomHomeBarSwipe") &&
        (destination == 1 || destination == 2)) {
        return 0;
    }
    return destination;
}

%end
%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
            ![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
        Class target = NSClassFromString(@"SBHomeGestureFinalDestinationSwitcherModifier");
        if (!HaogeSpringTwelveHomeBarSwipeMethodMatches(target)) return;
        // Registration is independent of the setting; existing snapshot updates apply per call.
        %init(HaogeSpringTwelveHomeBarSwipe);
    }
}
