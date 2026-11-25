#pragma once

#import <Preferences/PSListController.h>

@interface AxsSpringTwelveRootListController : PSListController
// Child pages override only their resource name; storage and notification stay shared.
- (NSString *)axs_springtwelve_specifierPlistName;
@end
