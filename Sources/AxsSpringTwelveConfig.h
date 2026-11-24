#pragma once

#import <Foundation/Foundation.h>

@interface AxsSpringTwelveConfig : NSObject
+ (instancetype)axs_springtwelve_shared;
- (id)axs_springtwelve_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)axs_springtwelve_reload;
@end
