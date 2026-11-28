#pragma once

// Invoke only after the ARC host has applied its host and default-OFF gates.
// Installation is once per process; runtime uninstall/reconfiguration is not provided.
#ifdef __cplusplus
extern "C" {
#endif
void HaogeSpringTwelveInstallMotionX(void);
#ifdef __cplusplus
}
#endif
