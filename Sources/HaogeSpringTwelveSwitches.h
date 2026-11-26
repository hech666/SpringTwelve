#pragma once

#import <Foundation/Foundation.h>
#import "HaogeSpringTwelveConfig.h"

static inline BOOL HaogeSpringTwelveOn(NSString *key) {
    id value = [[HaogeSpringTwelveConfig haoge_springtwelve_shared]
        haoge_springtwelve_valueForKey:key defaultValue:@NO];
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}
