#pragma once
#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, HaogeSpringTwelveMiscModules) {
    HaogeSpringTwelveMiscNone = 0,
    HaogeSpringTwelveMiscIOS27 = 1 << 0,
    HaogeSpringTwelveMiscMotionX = 1 << 1,
};

// Accept a stored boolean/number 1 only. Missing, malformed and string values
// must never install a hook. Reading this policy never creates Config observers.
static inline BOOL haoge_springtwelve_miscPreferenceEnabled(NSDictionary *values, NSString *key) {
    id value = [values isKindOfClass:NSDictionary.class] ? values[key] : nil;
    return [value isKindOfClass:NSNumber.class] && [value doubleValue] == 1.0;
}

static inline HaogeSpringTwelveMiscModules haoge_springtwelve_miscStartupModules(
    NSDictionary *values, NSString *process, BOOL hasUIApplication, BOOL isExtension) {
    if (isExtension || [process isEqualToString:@"druid"] ||
        [process isEqualToString:@"pasted"]) return HaogeSpringTwelveMiscNone;
    BOOL daemon = [process isEqualToString:@"replayd"] || [process isEqualToString:@"backboardd"];
    if (!daemon && !hasUIApplication) return HaogeSpringTwelveMiscNone;
    NSUInteger modules = HaogeSpringTwelveMiscNone;
    if (!daemon && hasUIApplication &&
        haoge_springtwelve_miscPreferenceEnabled(values, @"ios27StatusBarEnabled")) {
        modules |= HaogeSpringTwelveMiscIOS27;
    }
    if (haoge_springtwelve_miscPreferenceEnabled(values, @"motionX120HzRecordingEnabled")) {
        modules |= HaogeSpringTwelveMiscMotionX;
    }
    return (HaogeSpringTwelveMiscModules)modules;
}
