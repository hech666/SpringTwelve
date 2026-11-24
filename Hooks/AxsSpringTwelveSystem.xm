#import "AxsSpringTwelveSwitches.h"

static BOOL axs_springtwelve_lowPower(id item) {
    return AxsSpringTwelveOn(@"hideLowBatteryAlert") && [item isKindOfClass:NSClassFromString(@"SBLowPowerAlertItem")];
}
%hook SBAlertItemsController
- (void)activateAlertItem:(id)item { if (!axs_springtwelve_lowPower(item)) %orig; }
- (void)activateAlertItem:(id)item animated:(BOOL)animated { if (!axs_springtwelve_lowPower(item)) %orig; }
%end
%hook SBLowPowerAlertItem
- (id)_createSystemApertureElement { if (AxsSpringTwelveOn(@"hideLowBatteryAlert")) return nil; return %orig; }
%end
%hook SBBootDefaults
- (BOOL)dontLockAfterCrash { if (AxsSpringTwelveOn(@"noLockAfterRespring")) return YES; return %orig; }
%end
