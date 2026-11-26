#pragma once

#import <Preferences/PSListController.h>

@interface HaogeSpringTwelveRootListController : PSListController
// Child pages override only their resource name; storage and notification stay shared.
- (NSString *)haoge_springtwelve_specifierPlistName;
@end
