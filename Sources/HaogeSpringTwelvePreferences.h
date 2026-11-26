#pragma once

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "HaogeSpringTwelvePaths.h"

static NSString * const HaogeSpringTwelvePreferencesDomain = @"com.haoge.springtwelve";
static NSString * const HaogeSpringTwelvePreferencesChanged = @"com.haoge.springtwelve.preferences-changed";

static inline NSDictionary *haoge_springtwelve_readPreferences(void) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *path = haoge_springtwelve_preferencesPath();
    BOOL hasNewFile = path.length > 0 && [manager fileExistsAtPath:path];
    NSDictionary *values = hasNewFile ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    if ([values isKindOfClass:[NSDictionary class]]) return values;

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:HaogeSpringTwelvePreferencesDomain];
    [defaults synchronize];
    NSDictionary *currentDomain = [defaults persistentDomainForName:HaogeSpringTwelvePreferencesDomain];
    if (hasNewFile) return currentDomain ?: @{}; // Do not mask a malformed new config with old settings.
    if ([currentDomain isKindOfClass:[NSDictionary class]] && currentDomain.count) return currentDomain;

    // One-way read compatibility for users upgrading the old package identity.
    NSString *legacyPath = haoge_springtwelve_legacyPreferencesPath();
    NSDictionary *legacyFile = [NSDictionary dictionaryWithContentsOfFile:legacyPath];
    if ([legacyFile isKindOfClass:[NSDictionary class]]) return legacyFile;
    NSString *legacyDomainName = @"com.axs.springtwelve";
    NSUserDefaults *legacyDefaults = [[NSUserDefaults alloc] initWithSuiteName:legacyDomainName];
    [legacyDefaults synchronize];
    NSDictionary *legacyDomain = [legacyDefaults persistentDomainForName:legacyDomainName];
    if ([legacyDomain isKindOfClass:[NSDictionary class]]) return legacyDomain;
    return @{};
}

// The PreferenceBundle is the only caller allowed to write.
static inline BOOL haoge_springtwelve_writePreference(NSString *key, id value, NSError **error) {
    NSString *path = haoge_springtwelve_preferencesPath();
    if (key.length == 0 || path.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:HaogeSpringTwelvePreferencesDomain code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Invalid preference path or key"}];
        }
        return NO;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableDictionary *values;
    if ([manager fileExistsAtPath:path]) {
        NSData *existing = [NSData dataWithContentsOfFile:path options:0 error:error];
        id decoded = existing ? [NSPropertyListSerialization propertyListWithData:existing
                         options:NSPropertyListMutableContainers format:NULL error:error] : nil;
        if (![decoded isKindOfClass:[NSDictionary class]]) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:HaogeSpringTwelvePreferencesDomain code:2
                                        userInfo:@{NSLocalizedDescriptionKey: @"Preferences are not a dictionary"}];
            }
            return NO;
        }
        values = [decoded mutableCopy];
    } else {
        values = [haoge_springtwelve_readPreferences() mutableCopy];
    }
    if (value) values[key] = value;
    else [values removeObjectForKey:key];
    if (![manager createDirectoryAtPath:[path stringByDeletingLastPathComponent]
            withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:values
                         format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:HaogeSpringTwelvePreferencesDomain];
    // Mirror the whole snapshot so cfprefsd cannot flush stale unrelated keys.
    [defaults setPersistentDomain:values forName:HaogeSpringTwelvePreferencesDomain];
    [defaults synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)HaogeSpringTwelvePreferencesChanged, NULL, NULL, true);
    return YES;
}
