#pragma once

#import <Foundation/Foundation.h>

@interface HaogeSpringTwelveConfig : NSObject
+ (instancetype)haoge_springtwelve_shared;
- (id)haoge_springtwelve_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)haoge_springtwelve_reload;
@end
