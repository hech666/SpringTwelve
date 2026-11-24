#import "AxsSpringTwelveSwitches.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

@interface BluetoothManager : NSObject
- (void)setPowered:(BOOL)powered;
- (void)postNotification:(NSString *)name;
@end

static BOOL WirelessOn(void) { return AxsSpringTwelveOn(@"disconnectWiFiBT"); }

static BOOL WriteState(id manager, NSNumber *state) {
    @try { [manager setValue:state forKey:@"_state"]; return YES; }
    @catch (NSException *exception) { return NO; }
}

%group WirelessBluetooth
%hook BluetoothManager
- (void)bluetoothStateActionWithCompletion:(id)completion {
    BOOL actualOff = NO;
    if (WirelessOn() && [self respondsToSelector:@selector(setPowered:)] &&
        [self respondsToSelector:@selector(postNotification:)]) {
        @try {
            id state = [self valueForKey:@"_state"];
            actualOff = [state isKindOfClass:[NSNumber class]] &&
                        [state isEqualToNumber:@3] && WriteState(self, @99);
        } @catch (NSException *exception) { actualOff = NO; }
    }
    if (!actualOff) { %orig(completion); return; }
    BOOL returned = NO;
    @try { %orig(completion); returned = YES; }
    @finally { if (!returned) WriteState(self, @3); }
    if (!WriteState(self, @1)) { WriteState(self, @3); return; }
    @try { [self setPowered:NO]; }
    @catch (NSException *exception) { WriteState(self, @3); return; }
    @try { [self postNotification:@"BluetoothStateChangedNotification"]; }
    @catch (NSException *exception) { /* Power has already changed. */ }
}
%end
%end

// Count active calls on this monitor, including reentry and overlapping calls.
static char scopeKey;
static void ChangeScope(id monitor, BOOL entering) {
    @synchronized (monitor) {
        NSUInteger n = [objc_getAssociatedObject(monitor, &scopeKey) unsignedIntegerValue];
        NSNumber *next = entering ? @(n + 1) : (n > 1 ? @(n - 1) : nil);
        objc_setAssociatedObject(monitor, &scopeKey, next, OBJC_ASSOCIATION_RETAIN);
    }
}

%group WirelessWiFi
%hook WFControlCenterStateMonitor
- (void)performAction:(id)action {
    if (!WirelessOn()) { %orig(action); return; }
    ChangeScope(self, YES);
    @try { %orig(action); }
    @finally { ChangeScope(self, NO); }
}
- (BOOL)_airplaneModeEnabled {
    if (objc_getAssociatedObject(self, &scopeKey) && WirelessOn()) return YES;
    return %orig;
}
%end
%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_LAZY);
        dlopen("/System/Library/PrivateFrameworks/WiFiKit.framework/WiFiKit", RTLD_LAZY);
        Class bt = NSClassFromString(@"BluetoothManager");
        if (bt && class_getInstanceMethod(bt, @selector(bluetoothStateActionWithCompletion:))) {
            %init(WirelessBluetooth);
        }
        Class wifi = NSClassFromString(@"WFControlCenterStateMonitor");
        if (wifi && class_getInstanceMethod(wifi, @selector(performAction:)) &&
            class_getInstanceMethod(wifi, @selector(_airplaneModeEnabled))) {
            %init(WirelessWiFi);
        }
    }
}
