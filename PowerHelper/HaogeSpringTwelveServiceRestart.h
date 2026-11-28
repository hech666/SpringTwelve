#ifndef HAOGE_SPRING_TWELVE_SERVICE_RESTART_H
#define HAOGE_SPRING_TWELVE_SERVICE_RESTART_H

#ifdef __cplusplus
extern "C" {
#endif

enum HaogeSpringTwelvePowerHelperExitCode {
    HaogeSpringTwelvePowerHelperSubmitted = 0,
    HaogeSpringTwelvePowerHelperUsage = 64,
    HaogeSpringTwelvePowerHelperUnavailable = 69,
    HaogeSpringTwelvePowerHelperRebootError = 70,
    HaogeSpringTwelvePowerHelperMotionXError = 71,
    HaogeSpringTwelvePowerHelperPermission = 77,
    HaogeSpringTwelvePowerHelperElevation = 78
};

/* The production dispatcher; tests call this directly with mocked OS APIs. */
int haoge_springtwelve_powerHelperMain(int argc, char *argv[]);

#ifdef __cplusplus
}
#endif

#endif /* HAOGE_SPRING_TWELVE_SERVICE_RESTART_H */
