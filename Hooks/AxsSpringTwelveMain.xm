#import <UIKit/UIKit.h>
#import "AxsSpringTwelveConfig.h"
#import "AxsSpringTwelvePrivate.h"

// Load the immutable preference snapshot before Logos hooks run.
%ctor {
    @autoreleasepool {
        [AxsSpringTwelveConfig axs_springtwelve_shared];
    }
}
