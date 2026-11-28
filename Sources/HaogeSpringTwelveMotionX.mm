// MRC-only port of MotionX.mm at 01c4cd6cbf38bf62238254d835afe3ff4a1a82d0.
// The ARC caller owns host/default-OFF gating; this unit never reads configuration.
#if __has_feature(objc_arc)
#error "HaogeSpringTwelveMotionX.mm requires -fno-objc-arc."
#endif
#import "HaogeSpringTwelveMotionX.h"

// HaogeSpringTwelveMotionX 2.2 semantic reconstruction from supplied binary; names are reconstructed.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <pthread.h>
#include <dlfcn.h>
#include <math.h>
#include <string.h>
#include <stdint.h>
extern "C" void MSHookMessageEx(Class, SEL, IMP, IMP *);
extern "C" const char *getprogname(void);

// 0x6968
static bool HaogeSpringTwelveMotionXProcess(const char *name) {
    const char *p = getprogname(); return p && name && strcmp(p, name) == 0;
}
// 0x6a08 and 0x6f28
static void HaogeSpringTwelveMotionXHook(const char *name, SEL s, IMP replacement, IMP *original, bool meta = false) {
    Class c = objc_getClass(name);
    if (!c) return;
    if (meta) {
        if (!class_getClassMethod(c, s)) return;
        c = object_getClass(c);
    } else if (!class_getInstanceMethod(c, s)) return;
    MSHookMessageEx(c, s, replacement, original);
}
// 0x7590: runtime lookup, rather than respondsToSelector:, is intentional.
static bool HaogeSpringTwelveMotionXHas(id obj, SEL s) {
    if (!obj || !s) return false;
    Class c = object_getClass(obj);
    return c && class_getInstanceMethod(c, s);
}
static pthread_once_t HaogeSpringTwelveMotionXOnce = PTHREAD_ONCE_INIT;
static pthread_key_t HaogeSpringTwelveMotionXCaptureKey, HaogeSpringTwelveMotionXWriterKey;
// 0x71bc; original ignores pthread error returns, keys have no destructors.
static void HaogeSpringTwelveMotionXKeys(void) {
    pthread_key_create(&HaogeSpringTwelveMotionXCaptureKey, NULL);
    pthread_key_create(&HaogeSpringTwelveMotionXWriterKey, NULL);
}
static void HaogeSpringTwelveMotionXEnsureKeys(void) { pthread_once(&HaogeSpringTwelveMotionXOnce, HaogeSpringTwelveMotionXKeys); }
static void (*HaogeSpringTwelveMotionXOrigSession)(id, SEL, int, CGSize, BOOL, id, id, id);
// 0x6a74. Blocks are forwarded opaquely; there are no block invoke bodies in this dylib.
static void HaogeSpringTwelveMotionXSession(id obj, SEL cmd, int pid, CGSize size, BOOL system, id contexts, id output, id started) {
    uintptr_t active = HaogeSpringTwelveMotionXProcess("replayd") & (unsigned)system;
    HaogeSpringTwelveMotionXEnsureKeys();
    void *saved = pthread_getspecific(HaogeSpringTwelveMotionXCaptureKey);
    pthread_setspecific(HaogeSpringTwelveMotionXCaptureKey, (void *)active);
    @try {
        if (HaogeSpringTwelveMotionXOrigSession) HaogeSpringTwelveMotionXOrigSession(obj, cmd, pid, size, system, contexts, output, started);
    } @finally { pthread_setspecific(HaogeSpringTwelveMotionXCaptureKey, saved); }
}
static void (*HaogeSpringTwelveMotionXOrigWriter)(id, SEL, id);
// 0x6bc8
static void HaogeSpringTwelveMotionXWriter(id obj, SEL cmd, id handler) {
    uintptr_t active = 0;
    SEL s = sel_registerName("systemRecording");
    if (HaogeSpringTwelveMotionXProcess("replayd") && HaogeSpringTwelveMotionXHas(obj, s))
        active = ((BOOL (*)(id, SEL))objc_msgSend)(obj, s);
    HaogeSpringTwelveMotionXEnsureKeys();
    void *saved = pthread_getspecific(HaogeSpringTwelveMotionXWriterKey);
    pthread_setspecific(HaogeSpringTwelveMotionXWriterKey, (void *)active);
    @try { if (HaogeSpringTwelveMotionXOrigWriter) HaogeSpringTwelveMotionXOrigWriter(obj, cmd, handler); }
    @finally { pthread_setspecific(HaogeSpringTwelveMotionXWriterKey, saved); }
}
static id (*HaogeSpringTwelveMotionXOrigInput)(id, SEL, id, id);
// 0x6d20. Manual retain/release matches the original's non-ARC ownership.
static id HaogeSpringTwelveMotionXInput(id obj, SEL cmd, id mediaType, id settings) {
    if (HaogeSpringTwelveMotionXProcess("replayd")) {
        HaogeSpringTwelveMotionXEnsureKeys();
        if (pthread_getspecific(HaogeSpringTwelveMotionXWriterKey) && [mediaType isEqualToString:AVMediaTypeVideo] && settings) {
            NSMutableDictionary *copy = [settings mutableCopy];
            if (copy) {
                id old = [copy objectForKey:AVVideoCompressionPropertiesKey];
                NSMutableDictionary *compression = [old isKindOfClass:[NSDictionary class]] ?
                    [old mutableCopy] : [[NSMutableDictionary alloc] init];
                [compression setObject:[NSNumber numberWithInt:120] forKey:AVVideoExpectedSourceFrameRateKey];
                [compression setObject:[NSNumber numberWithInt:120] forKey:AVVideoMaxKeyFrameIntervalKey];
                [copy setObject:compression forKey:AVVideoCompressionPropertiesKey];
                [compression release];
                settings = [copy autorelease];
            }
        }
    }
    return HaogeSpringTwelveMotionXOrigInput ? HaogeSpringTwelveMotionXOrigInput(obj, cmd, mediaType, settings) : nil;
}
static id (*HaogeSpringTwelveMotionXOrigCapture)(id, SEL, CGSize, CMTime);
// 0x6f9c. CMTime is passed by value (indirect in the arm64 ABI).
static id HaogeSpringTwelveMotionXCapture(id obj, SEL cmd, CGSize size, CMTime interval) {
    bool changed = false;
    if (HaogeSpringTwelveMotionXProcess("replayd")) {
        HaogeSpringTwelveMotionXEnsureKeys();
        if (pthread_getspecific(HaogeSpringTwelveMotionXCaptureKey) &&
            (interval.flags & 0x1d) == 1 && interval.value >= 1 && interval.timescale >= 1) {
            double seconds = CMTimeGetSeconds(interval);
            if (isfinite(seconds) && seconds > 0.015 && seconds < 0.0185) {
                interval = CMTimeMake(1, 120); changed = true;
            }
        }
    }
    id result = HaogeSpringTwelveMotionXOrigCapture ? HaogeSpringTwelveMotionXOrigCapture(obj, cmd, size, interval) : nil;
    if (changed && result) {
        @try {
            SEL s = sel_registerName("setFigVirtualDisplayOption:forKey:");
            if ([result respondsToSelector:s]) {
                CFStringRef *symbol = (CFStringRef *)dlsym(RTLD_DEFAULT, "kFigVirtualDisplaySinkOption_VSyncRate");
                if (symbol && *symbol)
                    ((void (*)(id, SEL, id, id))objc_msgSend)(result, s, [NSNumber numberWithInt:120], (id)*symbol);
            }
        } @catch (NSException *exception) { (void)exception; }
    }
    return result;
}

// 0x71fc
static bool HaogeSpringTwelveMotionXSystemProcess(void) {
    return HaogeSpringTwelveMotionXProcess("SpringBoard") || HaogeSpringTwelveMotionXProcess("replayd") || HaogeSpringTwelveMotionXProcess("backboardd");
}
static void (*HaogeSpringTwelveMotionXOrigReasons)(id, SEL, const int *, NSUInteger);
// 0x7248
static void HaogeSpringTwelveMotionXReasons(id obj, SEL cmd, const int *reasons, NSUInteger count) {
    int one = 1;
    bool system = HaogeSpringTwelveMotionXSystemProcess();
    if (HaogeSpringTwelveMotionXOrigReasons) HaogeSpringTwelveMotionXOrigReasons(obj, cmd, system ? &one : reasons, system ? 1 : count);
}
// 0x72b8
static NSInteger HaogeSpringTwelveMotionXMaximumFPS(id obj, SEL cmd) { return 120; }
static void (*HaogeSpringTwelveMotionXOrigFPS)(id, SEL, NSInteger);
static void (*HaogeSpringTwelveMotionXOrigInterval)(id, SEL, NSInteger);
static void (*HaogeSpringTwelveMotionXOrigLinkRange)(id, SEL, CAFrameRateRange);
static void (*HaogeSpringTwelveMotionXOrigAnimationRange)(id, SEL, CAFrameRateRange);
static void (*HaogeSpringTwelveMotionXOrigSourceRange)(id, SEL, CAFrameRateRange);
// 0x72c0, 0x72d8
static void HaogeSpringTwelveMotionXFPS(id obj, SEL cmd, NSInteger value) {
    if (HaogeSpringTwelveMotionXOrigFPS) HaogeSpringTwelveMotionXOrigFPS(obj, cmd, 120);
}
static void HaogeSpringTwelveMotionXInterval(id obj, SEL cmd, NSInteger value) {
    if (HaogeSpringTwelveMotionXOrigInterval) HaogeSpringTwelveMotionXOrigInterval(obj, cmd, 1);
}
// 0x72f0, 0x7314, 0x7338
static CAFrameRateRange HaogeSpringTwelveMotionXRange(void) { return (CAFrameRateRange){120, 120, 120}; }
static void HaogeSpringTwelveMotionXLinkRange(id obj, SEL cmd, CAFrameRateRange range) {
    if (HaogeSpringTwelveMotionXOrigLinkRange) HaogeSpringTwelveMotionXOrigLinkRange(obj, cmd, HaogeSpringTwelveMotionXRange());
}
static void HaogeSpringTwelveMotionXAnimationRange(id obj, SEL cmd, CAFrameRateRange range) {
    if (HaogeSpringTwelveMotionXOrigAnimationRange) HaogeSpringTwelveMotionXOrigAnimationRange(obj, cmd, HaogeSpringTwelveMotionXRange());
}
static void HaogeSpringTwelveMotionXSourceRange(id obj, SEL cmd, CAFrameRateRange range) {
    if (HaogeSpringTwelveMotionXOrigSourceRange) HaogeSpringTwelveMotionXOrigSourceRange(obj, cmd, HaogeSpringTwelveMotionXRange());
}
// 0x74b0
static void HaogeSpringTwelveMotionXBoost(id obj) {
    if (!obj) return;
    SEL single = sel_registerName("setHighFrameRateReason:");
    SEL multiple = sel_registerName("setHighFrameRateReasons:count:");
    SEL range = sel_registerName("setPreferredFrameRateRange:");
    int one = 1;
    if (HaogeSpringTwelveMotionXHas(obj, single)) ((void (*)(id, SEL, int))objc_msgSend)(obj, single, 1);
    if (HaogeSpringTwelveMotionXHas(obj, multiple)) ((void (*)(id, SEL, const int *, NSUInteger))objc_msgSend)(obj, multiple, &one, 1);
    if (HaogeSpringTwelveMotionXHas(obj, range)) ((void (*)(id, SEL, CAFrameRateRange))objc_msgSend)(obj, range, HaogeSpringTwelveMotionXRange());
}
static double HaogeSpringTwelveMotionXLastBoost;
static id HaogeSpringTwelveMotionXSource;
// 0x75dc: retains init result for process lifetime, retries missing classes on later calls.
static void HaogeSpringTwelveMotionXBoostSpringBoard(void) {
    if (!HaogeSpringTwelveMotionXProcess("SpringBoard") || !pthread_main_np()) return;
    double now = CFAbsoluteTimeGetCurrent();
    if (HaogeSpringTwelveMotionXLastBoost > 0 && now - HaogeSpringTwelveMotionXLastBoost < 0.2) return;
    if (!HaogeSpringTwelveMotionXSource) {
        Class displayClass = objc_getClass("CADisplay");
        Class sourceClass = objc_getClass("CADynamicFrameRateSource");
        SEL mainDisplay = sel_registerName("mainDisplay");
        SEL initializer = sel_registerName("initWithDisplay:");
        if (!displayClass || !sourceClass || !class_getClassMethod(displayClass, mainDisplay) ||
            !class_getInstanceMethod(sourceClass, initializer)) { HaogeSpringTwelveMotionXSource = nil; return; }
        id display = ((id (*)(id, SEL))objc_msgSend)((id)displayClass, mainDisplay);
        if (!display) { HaogeSpringTwelveMotionXSource = nil; return; }
        id allocated = ((id (*)(id, SEL))objc_msgSend)((id)sourceClass, sel_registerName("alloc"));
        if (!allocated) { HaogeSpringTwelveMotionXSource = nil; return; }
        HaogeSpringTwelveMotionXSource = ((id (*)(id, SEL, id))objc_msgSend)(allocated, initializer, display);
        if (!HaogeSpringTwelveMotionXSource) return;
    }
    HaogeSpringTwelveMotionXLastBoost = now;
    HaogeSpringTwelveMotionXBoost(HaogeSpringTwelveMotionXSource);
}
static id (*HaogeSpringTwelveMotionXOrigDisplayLink)(id, SEL, id, SEL);
// 0x735c
static id HaogeSpringTwelveMotionXDisplayLink(id obj, SEL cmd, id target, SEL action) {
    id link = HaogeSpringTwelveMotionXOrigDisplayLink ? HaogeSpringTwelveMotionXOrigDisplayLink(obj, cmd, target, action) : nil;
    if (link) HaogeSpringTwelveMotionXBoost(link);
    return link;
}
static void (*HaogeSpringTwelveMotionXOrigOffset)(id, SEL, CGPoint);
static void (*HaogeSpringTwelveMotionXOrigAnimatedOffset)(id, SEL, CGPoint, BOOL);
static void (*HaogeSpringTwelveMotionXOrigMoved)(id, SEL);
// 0x73a4, 0x740c, 0x7488
static void HaogeSpringTwelveMotionXOffset(id obj, SEL cmd, CGPoint point) {
    HaogeSpringTwelveMotionXBoostSpringBoard(); if (HaogeSpringTwelveMotionXOrigOffset) HaogeSpringTwelveMotionXOrigOffset(obj, cmd, point);
}
static void HaogeSpringTwelveMotionXAnimatedOffset(id obj, SEL cmd, CGPoint point, BOOL animated) {
    HaogeSpringTwelveMotionXBoostSpringBoard(); if (HaogeSpringTwelveMotionXOrigAnimatedOffset) HaogeSpringTwelveMotionXOrigAnimatedOffset(obj, cmd, point, animated);
}
static void HaogeSpringTwelveMotionXMoved(id obj, SEL cmd) {
    if (HaogeSpringTwelveMotionXOrigMoved) HaogeSpringTwelveMotionXOrigMoved(obj, cmd); HaogeSpringTwelveMotionXBoostSpringBoard();
}
// 0x7734..0x776c: separate originals are kept even though constant hooks never call them.
static NSInteger HaogeSpringTwelveMotionXPolicyMaximum(id obj, SEL cmd) { return 120; }
static double HaogeSpringTwelveMotionXEffectiveMaximum(id obj, SEL cmd) { return 120.0; }
static double HaogeSpringTwelveMotionXPolicyRate(id obj, SEL cmd) { return 120.0; }
static BOOL HaogeSpringTwelveMotionXLimitEnabled(id obj, SEL cmd) { return NO; }
static BOOL HaogeSpringTwelveMotionXShouldLimit(id obj, SEL cmd) { return NO; }
static NSInteger HaogeSpringTwelveMotionXControllerMaximum(id obj, SEL cmd) { return 120; }
static IMP HaogeSpringTwelveMotionXUnusedOriginals[7];
// 0x69b0
static void HaogeSpringTwelveMotionXInstallReasons(void) {
    if (HaogeSpringTwelveMotionXSystemProcess()) HaogeSpringTwelveMotionXHook("CADynamicFrameRateSource", sel_registerName("setHighFrameRateReasons:count:"),
                                         (IMP)HaogeSpringTwelveMotionXReasons, (IMP *)&HaogeSpringTwelveMotionXOrigReasons);
}
#define haoge_springtwelve_motionx_hook(cls, sel, fn, orig) HaogeSpringTwelveMotionXHook(cls, sel_registerName(sel), (IMP)fn, (IMP *)&orig)
// 0x64fc; original branch order and early returns mirror the binary.
static void HaogeSpringTwelveMotionXInitialize(void) {
    if (HaogeSpringTwelveMotionXProcess("replayd")) {
        if (!HaogeSpringTwelveMotionXProcess("replayd")) return;
        HaogeSpringTwelveMotionXEnsureKeys();
        dlopen("/System/Library/Frameworks/ReplayKit.framework/ReplayKit", 5);
        dlopen("/System/Library/Frameworks/MediaToolbox.framework/MediaToolbox", 5);
        SEL session = sel_registerName("startSessionWithPID:windowSize:systemRecording:contextIDs:outputHandler:didStartHandler:");
        Class manager = objc_getClass("RPScreenCaptureManagerIOS");
        Method method = manager ? class_getInstanceMethod(manager, session) : NULL;
        if (method && method_getNumberOfArguments(method) == 8)
            HaogeSpringTwelveMotionXHook("RPScreenCaptureManagerIOS", session, (IMP)HaogeSpringTwelveMotionXSession, (IMP *)&HaogeSpringTwelveMotionXOrigSession);
        haoge_springtwelve_motionx_hook("RPMovieWriter", "setUpAssetWriterWithHandler:", HaogeSpringTwelveMotionXWriter, HaogeSpringTwelveMotionXOrigWriter);
        haoge_springtwelve_motionx_hook("AVAssetWriterInput", "initWithMediaType:outputSettings:", HaogeSpringTwelveMotionXInput, HaogeSpringTwelveMotionXOrigInput);
        HaogeSpringTwelveMotionXHook("FigScreenCaptureController", sel_registerName("screenCaptureControllerWithSize:minIntervalBetweenFrames:"),
                    (IMP)HaogeSpringTwelveMotionXCapture, (IMP *)&HaogeSpringTwelveMotionXOrigCapture, true);
        return;
    }
    if (HaogeSpringTwelveMotionXProcess("backboardd")) { HaogeSpringTwelveMotionXInstallReasons(); return; }
    haoge_springtwelve_motionx_hook("UIScreen", "maximumFramesPerSecond", HaogeSpringTwelveMotionXMaximumFPS, HaogeSpringTwelveMotionXUnusedOriginals[0]);
    haoge_springtwelve_motionx_hook("CADisplayLink", "setPreferredFramesPerSecond:", HaogeSpringTwelveMotionXFPS, HaogeSpringTwelveMotionXOrigFPS);
    haoge_springtwelve_motionx_hook("CADisplayLink", "setFrameInterval:", HaogeSpringTwelveMotionXInterval, HaogeSpringTwelveMotionXOrigInterval);
    haoge_springtwelve_motionx_hook("CADisplayLink", "setPreferredFrameRateRange:", HaogeSpringTwelveMotionXLinkRange, HaogeSpringTwelveMotionXOrigLinkRange);
    haoge_springtwelve_motionx_hook("CAAnimation", "setPreferredFrameRateRange:", HaogeSpringTwelveMotionXAnimationRange, HaogeSpringTwelveMotionXOrigAnimationRange);
    haoge_springtwelve_motionx_hook("CADynamicFrameRateSource", "setPreferredFrameRateRange:", HaogeSpringTwelveMotionXSourceRange, HaogeSpringTwelveMotionXOrigSourceRange);
    HaogeSpringTwelveMotionXInstallReasons();
    if (HaogeSpringTwelveMotionXProcess("SpringBoard")) {
        HaogeSpringTwelveMotionXHook("CADisplayLink", sel_registerName("displayLinkWithTarget:selector:"), (IMP)HaogeSpringTwelveMotionXDisplayLink,
                    (IMP *)&HaogeSpringTwelveMotionXOrigDisplayLink, true);
        haoge_springtwelve_motionx_hook("UIScrollView", "setContentOffset:", HaogeSpringTwelveMotionXOffset, HaogeSpringTwelveMotionXOrigOffset);
        haoge_springtwelve_motionx_hook("UIScrollView", "setContentOffset:animated:", HaogeSpringTwelveMotionXAnimatedOffset, HaogeSpringTwelveMotionXOrigAnimatedOffset);
        haoge_springtwelve_motionx_hook("NCNotificationShortLookView", "didMoveToWindow", HaogeSpringTwelveMotionXMoved, HaogeSpringTwelveMotionXOrigMoved);
    }
    haoge_springtwelve_motionx_hook("SBProMotionPolicy", "maximumSupportedRefreshRate", HaogeSpringTwelveMotionXPolicyMaximum, HaogeSpringTwelveMotionXUnusedOriginals[1]);
    haoge_springtwelve_motionx_hook("SBProMotionPolicy", "effectiveMaxRefreshRate", HaogeSpringTwelveMotionXEffectiveMaximum, HaogeSpringTwelveMotionXUnusedOriginals[2]);
    haoge_springtwelve_motionx_hook("SBProMotionPolicy", "policyRefreshRate", HaogeSpringTwelveMotionXPolicyRate, HaogeSpringTwelveMotionXUnusedOriginals[3]);
    haoge_springtwelve_motionx_hook("SBProMotionPolicy", "isLimitFrameRateEnabled", HaogeSpringTwelveMotionXLimitEnabled, HaogeSpringTwelveMotionXUnusedOriginals[4]);
    haoge_springtwelve_motionx_hook("SBProMotionPolicy", "shouldLimitFrameRate", HaogeSpringTwelveMotionXShouldLimit, HaogeSpringTwelveMotionXUnusedOriginals[5]);
    haoge_springtwelve_motionx_hook("SBDisplayRefreshRateController", "maximumRefreshRate", HaogeSpringTwelveMotionXControllerMaximum, HaogeSpringTwelveMotionXUnusedOriginals[6]);
}

#undef haoge_springtwelve_motionx_hook

// Independent of the original per-thread capture/writer key initializer.
static pthread_once_t HaogeSpringTwelveMotionXInstallOnce = PTHREAD_ONCE_INIT;

extern "C" void HaogeSpringTwelveInstallMotionX(void) {
    pthread_once(&HaogeSpringTwelveMotionXInstallOnce, HaogeSpringTwelveMotionXInitialize);
}
