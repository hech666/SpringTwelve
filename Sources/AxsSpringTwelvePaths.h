#pragma once

#import <Foundation/Foundation.h>

#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#import <roothide.h>
#else
#import <rootless.h>
#endif

static inline NSString *axs_springtwelve_resourcePath(NSString *rootfsPath) {
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
    return jbroot(rootfsPath);
#else
    return ROOT_PATH_NS_VAR(rootfsPath);
#endif
}

static inline NSString *axs_springtwelve_recordingDirectory(void) {
    NSString *path = @"/var/mobile/Documents/CallRecordings";
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
    return jbroot(path);
#else
    return path;
#endif
}

static inline NSString *axs_springtwelve_preferencesPath(void) {
    NSString *path = @"/var/mobile/Library/Preferences/com.axs.springtwelve.plist";
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
    return jbroot(path);
#else
    // Mobile user preferences do not use the rootless installation prefix.
    return path;
#endif
}
