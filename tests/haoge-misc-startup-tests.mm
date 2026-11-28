#import <Foundation/Foundation.h>
#import "HaogeSpringTwelveMiscStartup.h"
#include <cstdio>
#include <cstdlib>

static void check(BOOL condition, const char *message) {
    if (!condition) { std::fprintf(stderr, "FAIL %s\n", message); std::abort(); }
}
int main() {
    @autoreleasepool {
        NSString *i27 = @"ios27StatusBarEnabled";
        NSString *mx = @"motionX120HzRecordingEnabled";
        for (id invalid in @[@NO, @0, @2, @(-1), @0.5, @"1", @"true", NSNull.null, @[], @{}]) {
            check(!haoge_springtwelve_miscPreferenceEnabled(@{i27:invalid}, i27), "invalid/off value enabled");
            check(haoge_springtwelve_miscStartupModules(@{i27:invalid,mx:invalid}, @"TestApp", YES, NO) == 0,
                  "invalid/off value installed module");
        }
        check(!haoge_springtwelve_miscPreferenceEnabled(@{}, i27), "missing key enabled");
        check(!haoge_springtwelve_miscPreferenceEnabled(nil, mx), "missing config enabled");
        check(haoge_springtwelve_miscStartupModules(@{}, @"SpringBoard", YES, NO) == 0, "default not OFF");
        for (NSNumber *status in @[@NO,@YES]) for (NSNumber *motion in @[@NO,@YES]) {
            NSDictionary *values = @{i27:status,mx:motion};
            NSUInteger expected = (status.boolValue ? HaogeSpringTwelveMiscIOS27 : 0) |
                                  (motion.boolValue ? HaogeSpringTwelveMiscMotionX : 0);
            for (NSString *host in @[@"SpringBoard", @"MobilePhone", @"Preferences", @"TestApp"]) {
                check(haoge_springtwelve_miscStartupModules(values, host, YES, NO) == expected, "UI module selection");
                check(haoge_springtwelve_miscStartupModules(values, host, YES, YES) == 0, "extension enabled");
            }
            for (NSString *host in @[@"replayd",@"backboardd"]) {
                check(haoge_springtwelve_miscStartupModules(values, host, NO, NO) ==
                      (motion.boolValue ? HaogeSpringTwelveMiscMotionX : 0), "daemon module selection");
            }
            for (NSString *host in @[@"druid",@"pasted"]) {
                check(haoge_springtwelve_miscStartupModules(values, host, YES, NO) == 0, "legacy daemon enabled");
            }
            check(haoge_springtwelve_miscStartupModules(values, @"Headless", NO, NO) == 0, "headless enabled");
        }
        std::puts("PASS actual shared startup policy: default OFF, strict values, independent keys, UI/daemon/extension isolation (not hook/device tests)");
    }
    return 0;
}
