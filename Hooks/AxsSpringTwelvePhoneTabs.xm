// PhoneTabsCustomizer-style tab selection filter, scoped to Phone only.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>
#import "AxsSpringTwelveSwitches.h"

// Private Phone class/method are resolved and signature-checked at runtime.
@interface PhoneTabBarController : UITabBarController
- (id)viewControllerForTabViewType:(int)type;
@end

static BOOL AxsSpringTwelvePhoneTabMethodMatches(Class cls) {
    SEL configureSelector = NSSelectorFromString(@"showFavoritesTab:recentsTab:contactsTab:keypadTab:voicemailTab:");
    Method configureMethod = class_getInstanceMethod(cls, configureSelector);
    if (!configureMethod || method_getNumberOfArguments(configureMethod) != 7) return NO;

    char returnType[8] = {0};
    method_getReturnType(configureMethod, returnType, sizeof(returnType));
    if (strcmp(returnType, @encode(void)) != 0) return NO;

    for (unsigned int index = 2; index < 7; index++) {
        char *argumentType = method_copyArgumentType(configureMethod, index);
        BOOL isBoolean = argumentType &&
            (strcmp(argumentType, @encode(BOOL)) == 0 || strcmp(argumentType, "B") == 0 ||
             strcmp(argumentType, "c") == 0);
        free(argumentType);
        if (!isBoolean) return NO;
    }
    return YES;
}

static BOOL AxsSpringTwelvePhoneTabFallbackMatches(Class cls) {
    // The optional fallback must not prevent the main BOOL filter from installing.
    Method switchMethod = class_getInstanceMethod(cls, NSSelectorFromString(@"switchToTab:"));
    Method viewControllerMethod = class_getInstanceMethod(cls, NSSelectorFromString(@"viewControllerForTabViewType:"));
    if (!switchMethod || method_getNumberOfArguments(switchMethod) != 3 ||
        !viewControllerMethod || method_getNumberOfArguments(viewControllerMethod) != 3) return NO;

    char switchReturnType[8] = {0};
    char viewControllerReturnType[8] = {0};
    method_getReturnType(switchMethod, switchReturnType, sizeof(switchReturnType));
    method_getReturnType(viewControllerMethod, viewControllerReturnType, sizeof(viewControllerReturnType));
    if (strcmp(switchReturnType, @encode(void)) != 0 || strcmp(viewControllerReturnType, @encode(id)) != 0) return NO;

    char *switchArgumentType = method_copyArgumentType(switchMethod, 2);
    char *viewControllerArgumentType = method_copyArgumentType(viewControllerMethod, 2);
    BOOL intArguments = switchArgumentType && viewControllerArgumentType &&
        strcmp(switchArgumentType, @encode(int)) == 0 && strcmp(viewControllerArgumentType, @encode(int)) == 0;
    free(switchArgumentType);
    free(viewControllerArgumentType);
    return intArguments;
}

%group AxsSpringTwelvePhoneTabBar
%hook PhoneTabBarController

- (void)showFavoritesTab:(BOOL)favorites
              recentsTab:(BOOL)recents
             contactsTab:(BOOL)contacts
                keypadTab:(BOOL)keypad
            voicemailTab:(BOOL)voicemail {
    BOOL hideFavorites = AxsSpringTwelveOn(@"disablePhoneFavoritesTab");
    BOOL hideContacts = AxsSpringTwelveOn(@"disablePhoneContactsTab");
    BOOL hideVoicemail = AxsSpringTwelveOn(@"disablePhoneVoicemailTab");
    %orig(hideFavorites ? NO : favorites,
          recents,
          hideContacts ? NO : contacts,
          keypad,
          hideVoicemail ? NO : voicemail);
}

%end
%end

%group AxsSpringTwelvePhoneTabFallback
%hook PhoneTabBarController

- (void)switchToTab:(int)tab {
    BOOL hidingTab = AxsSpringTwelveOn(@"disablePhoneFavoritesTab") ||
                     AxsSpringTwelveOn(@"disablePhoneContactsTab") ||
                     AxsSpringTwelveOn(@"disablePhoneVoicemailTab");
    if (hidingTab && ![self viewControllerForTabViewType:tab]) {
        for (int candidate = 1; candidate <= 5; candidate++) {
            if ([self viewControllerForTabViewType:candidate]) {
                tab = candidate;
                break;
            }
        }
    }
    %orig(tab);
}

%end
%end

%ctor {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (![bundleID isEqualToString:@"com.apple.mobilephone"]) return;
        Class target = NSClassFromString(@"PhoneTabBarController");
        if (!target || !AxsSpringTwelvePhoneTabMethodMatches(target)) return;
        %init(AxsSpringTwelvePhoneTabBar);
        if (AxsSpringTwelvePhoneTabFallbackMatches(target)) {
            %init(AxsSpringTwelvePhoneTabFallback);
        }
    }
}
