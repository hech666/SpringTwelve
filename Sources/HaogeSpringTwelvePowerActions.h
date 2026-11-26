#import <Foundation/Foundation.h>

// Request identifiers are independent of Unix signal numbers.
typedef NS_ENUM(NSInteger, HaogeSpringTwelvePowerAction) {
    HaogeSpringTwelvePowerActionQuickRespring = 1,
    HaogeSpringTwelvePowerActionForceRespring,
    // Keep existing operation identifiers stable; the removed action used 3.
    HaogeSpringTwelvePowerActionRespring = 4,
    HaogeSpringTwelvePowerActionUserspaceReboot,
    HaogeSpringTwelvePowerActionReboot,
    HaogeSpringTwelvePowerActionShutdown
};

FOUNDATION_EXPORT NSString *haoge_springtwelve_powerActionTitle(HaogeSpringTwelvePowerAction action);
FOUNDATION_EXPORT NSString *haoge_springtwelve_powerActionWarning(HaogeSpringTwelvePowerAction action);
FOUNDATION_EXPORT BOOL haoge_springtwelve_powerActionAvailable(HaogeSpringTwelvePowerAction action);
// Called only by the explicit confirmation handler on the main thread.
// Completion runs on main; a nil error means a request was dispatched/accepted,
// not that a restart completed. Void system APIs cannot confirm final outcome.
FOUNDATION_EXPORT void haoge_springtwelve_powerActionRequest(HaogeSpringTwelvePowerAction action,
                                        void (^completion)(NSString *error));
