#import "HaogeSpringTwelveSwitches.h"

static BOOL haoge_springtwelve_lowPower(id item) {
    return HaogeSpringTwelveOn(@"hideLowBatteryAlert") && [item isKindOfClass:NSClassFromString(@"SBLowPowerAlertItem")];
}
%group HaogeSpringTwelveSpringBoardSystem
%hook SBAlertItemsController
- (void)activateAlertItem:(id)item { if (!haoge_springtwelve_lowPower(item)) %orig; }
- (void)activateAlertItem:(id)item animated:(BOOL)animated { if (!haoge_springtwelve_lowPower(item)) %orig; }
%end
%hook SBLowPowerAlertItem
- (id)_createSystemApertureElement { if (HaogeSpringTwelveOn(@"hideLowBatteryAlert")) return nil; return %orig; }
%end
%hook SBBootDefaults
- (BOOL)dontLockAfterCrash { if (HaogeSpringTwelveOn(@"noLockAfterRespring")) return YES; return %orig; }
%end

%end // HaogeSpringTwelveSpringBoardSystem

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        if (!NSClassFromString(@"SBAlertItemsController") || !NSClassFromString(@"SBLowPowerAlertItem") ||
            !NSClassFromString(@"SBBootDefaults")) return;
        %init(HaogeSpringTwelveSpringBoardSystem);
    }
}
