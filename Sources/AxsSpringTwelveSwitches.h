#pragma once

#import <Foundation/Foundation.h>
#import "AxsSpringTwelveConfig.h"

static inline BOOL AxsSpringTwelveOn(NSString *key) {
    id value = [[AxsSpringTwelveConfig axs_springtwelve_shared]
        axs_springtwelve_valueForKey:key defaultValue:@NO];
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}
