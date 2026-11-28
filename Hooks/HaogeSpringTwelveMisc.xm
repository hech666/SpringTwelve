#import "HaogeSpringTwelveMiscStartup.h"
#import "HaogeSpringTwelvePreferences.h"

extern "C" void HaogeSpringTwelveInstallIOS27StatusBar(void);
extern "C" void HaogeSpringTwelveInstallMotionX(void);

// New modules are startup-only. Do not register a preferences observer or try
// to undo another hook chain when a setting changes in an already running host.
%ctor {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName;
        BOOL daemon = [process isEqualToString:@"replayd"] || [process isEqualToString:@"backboardd"];
        NSBundle *bundle = NSBundle.mainBundle;
        BOOL extension = [bundle.bundlePath.pathExtension isEqualToString:@"appex"] ||
                         bundle.infoDictionary[@"NSExtension"] != nil;
        BOOL uiHost = NSClassFromString(@"UIApplication") != Nil;
        if (extension || [process isEqualToString:@"druid"] ||
            [process isEqualToString:@"pasted"] || (!daemon && !uiHost)) return;
        NSDictionary *values = haoge_springtwelve_readPreferences();
        HaogeSpringTwelveMiscModules modules =
            haoge_springtwelve_miscStartupModules(values, process, uiHost, extension);
        if (modules & HaogeSpringTwelveMiscIOS27) HaogeSpringTwelveInstallIOS27StatusBar();
        if (modules & HaogeSpringTwelveMiscMotionX) HaogeSpringTwelveInstallMotionX();
    }
}
