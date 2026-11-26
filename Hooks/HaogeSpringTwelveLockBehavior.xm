#import "HaogeSpringTwelveSwitches.h"
#import <objc/runtime.h>
#import <string.h>

// Selectors supplied by the user; keep these two features independent of
// unrelated SpringBoard classes and never install them in Phone/paste daemons.
%group HaogeSpringTwelveAutoDismissFaceID
%hook CSLockScreenSettings
- (BOOL)autoDismissUnlockedLockScreen {
    return HaogeSpringTwelveOn(@"autoDismissFaceID") ? YES : %orig;
}
%end
%end

%group HaogeSpringTwelveNotificationWakeRequest
%hook SBNCScreenController
- (BOOL)canTurnOnScreenForNotificationRequest:(id)request {
    return HaogeSpringTwelveOn(@"disableNotificationWake") ? NO : %orig;
}
%end
%end

%group HaogeSpringTwelveNotificationWakeScreen
%hook SBNCScreenController
- (void)_turnOnScreen {
    if (!HaogeSpringTwelveOn(@"disableNotificationWake")) { %orig; }
}
%end
%end

static BOOL haoge_springtwelve_lockMethod(Class cls, NSString *name, BOOL boolean, BOOL objectArgument) {
    Method method = cls ? class_getInstanceMethod(cls, NSSelectorFromString(name)) : NULL;
    if (!method || method_getNumberOfArguments(method) != (objectArgument ? 3u : 2u)) return NO;
    char type[16] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (boolean ? (strcmp(type, "B") && strcmp(type, "c")) : strcmp(type, "v")) return NO;
    if (objectArgument) {
        method_getArgumentType(method, 2, type, sizeof(type));
        if (type[0] != '@') return NO;
    }
    return YES;
}

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        Class settings = NSClassFromString(@"CSLockScreenSettings");
        if (haoge_springtwelve_lockMethod(settings, @"autoDismissUnlockedLockScreen", YES, NO)) {
            %init(HaogeSpringTwelveAutoDismissFaceID);
        }
        Class screen = NSClassFromString(@"SBNCScreenController");
        if (haoge_springtwelve_lockMethod(screen, @"canTurnOnScreenForNotificationRequest:", YES, YES)) {
            %init(HaogeSpringTwelveNotificationWakeRequest);
        }
        if (haoge_springtwelve_lockMethod(screen, @"_turnOnScreen", NO, NO)) {
            %init(HaogeSpringTwelveNotificationWakeScreen);
        }
    }
}
