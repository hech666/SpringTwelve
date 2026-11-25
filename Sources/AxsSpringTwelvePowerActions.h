#import <Foundation/Foundation.h>

// Request identifiers are independent of Unix signal numbers.
typedef NS_ENUM(NSInteger, AxsSpringTwelvePowerAction) {
    AxsSpringTwelvePowerActionQuickRespring = 1,
    AxsSpringTwelvePowerActionForceRespring,
    AxsSpringTwelvePowerActionSafeMode,
    AxsSpringTwelvePowerActionRespring,
    AxsSpringTwelvePowerActionUserspaceReboot,
    AxsSpringTwelvePowerActionReboot,
    AxsSpringTwelvePowerActionShutdown
};

FOUNDATION_EXPORT NSString *axs_springtwelve_powerActionTitle(AxsSpringTwelvePowerAction action);
FOUNDATION_EXPORT NSString *axs_springtwelve_powerActionWarning(AxsSpringTwelvePowerAction action);
FOUNDATION_EXPORT BOOL axs_springtwelve_powerActionAvailable(AxsSpringTwelvePowerAction action);
// Called only by the explicit confirmation handler on the main thread.
// Completion runs on main; a nil error means a request was dispatched/accepted,
// not that a restart completed. Void system APIs cannot confirm final outcome.
FOUNDATION_EXPORT void axs_springtwelve_powerActionRequest(AxsSpringTwelvePowerAction action,
                                        void (^completion)(NSString *error));
