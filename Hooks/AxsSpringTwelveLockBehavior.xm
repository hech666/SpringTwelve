#import "AxsSpringTwelveSwitches.h"
#import <objc/runtime.h>
#import <string.h>

// Selectors supplied by the user; keep these two features independent of
// unrelated SpringBoard classes and never install them in Phone/paste daemons.
%group AxsSpringTwelveAutoDismissFaceID
%hook CSLockScreenSettings
- (BOOL)autoDismissUnlockedLockScreen {
    return AxsSpringTwelveOn(@"autoDismissFaceID") ? YES : %orig;
}
%end
%end

%group AxsSpringTwelveNotificationWakeRequest
%hook SBNCScreenController
- (BOOL)canTurnOnScreenForNotificationRequest:(id)request {
    return AxsSpringTwelveOn(@"disableNotificationWake") ? NO : %orig;
}
%end
%end

%group AxsSpringTwelveNotificationWakeScreen
%hook SBNCScreenController
- (void)_turnOnScreen {
    if (!AxsSpringTwelveOn(@"disableNotificationWake")) { %orig; }
}
%end
%end

static BOOL axs_springtwelve_lockMethod(Class cls, NSString *name, BOOL boolean, BOOL objectArgument) {
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
        if (axs_springtwelve_lockMethod(settings, @"autoDismissUnlockedLockScreen", YES, NO)) {
            %init(AxsSpringTwelveAutoDismissFaceID);
        }
        Class screen = NSClassFromString(@"SBNCScreenController");
        if (axs_springtwelve_lockMethod(screen, @"canTurnOnScreenForNotificationRequest:", YES, YES)) {
            %init(AxsSpringTwelveNotificationWakeRequest);
        }
        if (axs_springtwelve_lockMethod(screen, @"_turnOnScreen", NO, NO)) {
            %init(AxsSpringTwelveNotificationWakeScreen);
        }
    }
}
