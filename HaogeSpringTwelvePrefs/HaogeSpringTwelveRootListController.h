#pragma once

#import <Preferences/PSListController.h>

@interface HaogeSpringTwelveRootListController : PSListController
// Child pages share storage and notification; a successful save can be observed.
- (NSString *)haoge_springtwelve_specifierPlistName;
- (void)haoge_springtwelve_didSavePreference:(NSString *)key
                            previousValue:(id)previousValue currentValue:(id)currentValue;
@end
