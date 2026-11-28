#import "HaogeSpringTwelveConfig.h"

// Only preload the shared observer in the original hosts. Misc modules use a
// separate read-only startup snapshot, independent of constructor ordering.
%ctor {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName;
        if (![process isEqualToString:@"SpringBoard"] &&
            ![process isEqualToString:@"MobilePhone"] &&
            ![process isEqualToString:@"druid"] &&
            ![process isEqualToString:@"pasted"]) return;
        [HaogeSpringTwelveConfig haoge_springtwelve_shared];
    }
}
