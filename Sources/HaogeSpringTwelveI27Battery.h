#pragma once

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Install the reconstructed _UIBatteryView hooks, in their original order.
 * Call first from the owning tweak's explicit entry, before the signal hooks.
 * Returns YES when already installed or when registration was performed.
 * Returns NO if UIApplication, _UIBatteryView, or a mandatory method is absent.
 * No implicit startup hook is emitted here; no other reconstruction module is required.
 * Like the original, installation and the shared ivar cache are not synchronized.
 */
FOUNDATION_EXPORT BOOL HaogeSpringTwelveI27InstallBatteryHooks(void);

#ifdef __cplusplus
}
#endif
