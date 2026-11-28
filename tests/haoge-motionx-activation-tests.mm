#import <Foundation/Foundation.h>
#import "../HaogeSpringTwelvePrefs/HaogeSpringTwelveMotionXActivation.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        NSArray *values = @[@0, @1, @YES, @NO, @2, @(-1), @0.5, @"1", @"true", NSNull.null, @[], @{}];
        NSArray *keys = @[@"motionX120HzRecordingEnabled", @"ios27StatusBarEnabled", @"weTypeVoiceNoJump", @"", @"autoRecordCalls"];
        NSUInteger cases = 0;
        for (NSString *key in keys) for (id old in values) for (id now in values) {
            BOOL oldOn = [old isKindOfClass:NSNumber.class] && [old doubleValue] == 1;
            BOOL newOn = [now isKindOfClass:NSNumber.class] && [now doubleValue] == 1;
            BOOL expected = [key isEqualToString:@"motionX120HzRecordingEnabled"] && !oldOn && newOn;
            assert(haoge_springtwelve_motionXNeedsServiceRestart(key, old, now) == expected);
            cases++;
        }
        assert(haoge_springtwelve_motionXNeedsServiceRestart(@"motionX120HzRecordingEnabled", nil, @YES));
        assert(!haoge_springtwelve_motionXNeedsServiceRestart(nil, nil, @YES));
        assert(!haoge_springtwelve_motionXNeedsServiceRestart(@"motionX120HzRecordingEnabled", @YES, nil));
        printf("PASS actual activation policy: %lu value/key cases plus nil cases; only OFF->ON of 120 key\n", (unsigned long)cases);
    }
    return 0;
}
