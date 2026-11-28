#pragma once
#import <Foundation/Foundation.h>

// Called only after the shared writer reports success. Match startup's strict
// NSNumber(1) semantics; malformed/string values do not count as enabled.
static inline BOOL haoge_springtwelve_motionXNeedsServiceRestart(
    NSString *key, id previousValue, id currentValue) {
    if (![key isEqualToString:@"motionX120HzRecordingEnabled"]) return NO;
    BOOL wasEnabled = [previousValue isKindOfClass:NSNumber.class] &&
        [previousValue doubleValue] == 1.0;
    BOOL nowEnabled = [currentValue isKindOfClass:NSNumber.class] &&
        [currentValue doubleValue] == 1.0;
    return !wasEnabled && nowEnabled;
}
