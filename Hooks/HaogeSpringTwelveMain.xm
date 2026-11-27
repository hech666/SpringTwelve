#import "HaogeSpringTwelveConfig.h"

// Load the immutable preference snapshot before Logos hooks run.
%ctor {
    @autoreleasepool {
        [HaogeSpringTwelveConfig haoge_springtwelve_shared];
    }
}
