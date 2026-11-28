// Semantic reconstruction; suffixes are original arm64 addresses.
// The entry/registration order is recovered from startup block 0x6a58.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import "HaogeSpringTwelveI27Battery.h"
#import "HaogeSpringTwelveI27Runtime.h"
#include <stdlib.h>
#include <string.h>

extern "C" void MSHookMessageEx(Class, SEL, IMP, IMP *);

// Each statically generated hook has its OWN original IMP, like the input.
#define HaogeSpringTwelveI27_POST0(hex) \
static void (*HaogeSpringTwelveI27Orig##hex)(UIView *, SEL); \
static void HaogeSpringTwelveI27H##hex(UIView *view, SEL cmd) { \
    HaogeSpringTwelveI27Orig##hex(view, cmd); HaogeSpringTwelveI27RenderView(view); \
}
#define HaogeSpringTwelveI27_POSTOBJ(hex) \
static void (*HaogeSpringTwelveI27Orig##hex)(UIView *, SEL, id); \
static void HaogeSpringTwelveI27H##hex(UIView *view, SEL cmd, id arg) { \
    id __attribute__((objc_precise_lifetime)) keep = arg; \
    HaogeSpringTwelveI27Orig##hex(view, cmd, keep); HaogeSpringTwelveI27RenderView(view); \
}
HaogeSpringTwelveI27_POST0(8bc8)
HaogeSpringTwelveI27_POST0(8bf4)
HaogeSpringTwelveI27_POST0(8c20)
HaogeSpringTwelveI27_POST0(8cf0)
HaogeSpringTwelveI27_POST0(8d1c)
HaogeSpringTwelveI27_POST0(8d48)
HaogeSpringTwelveI27_POST0(8d74)
HaogeSpringTwelveI27_POST0(8da0)
HaogeSpringTwelveI27_POSTOBJ(8e74)
HaogeSpringTwelveI27_POST0(8ee0)
HaogeSpringTwelveI27_POST0(8f0c)
HaogeSpringTwelveI27_POST0(8f38)
HaogeSpringTwelveI27_POST0(8f64)
HaogeSpringTwelveI27_POST0(8f90)
HaogeSpringTwelveI27_POST0(8fbc)
HaogeSpringTwelveI27_POST0(8fe8)
HaogeSpringTwelveI27_POST0(9014)
HaogeSpringTwelveI27_POSTOBJ(9040)
HaogeSpringTwelveI27_POST0(90ac)
HaogeSpringTwelveI27_POST0(90d8)
HaogeSpringTwelveI27_POST0(9104)
HaogeSpringTwelveI27_POST0(9130)
HaogeSpringTwelveI27_POSTOBJ(9788)
HaogeSpringTwelveI27_POSTOBJ(97f4)
HaogeSpringTwelveI27_POST0(9860)
HaogeSpringTwelveI27_POST0(988c)
HaogeSpringTwelveI27_POSTOBJ(98b8)

// 0x8c4c caches the incoming STUI cellular color BEFORE original, with no
// post-render. 0x960c does the UIKit variant AFTER original and then renders.
static void (*HaogeSpringTwelveI27Orig8c4c)(UIView *, SEL, UIColor *);
static void HaogeSpringTwelveI27H8c4c(UIView *view, SEL cmd, UIColor *color) {
    UIColor *__attribute__((objc_precise_lifetime)) keep = color;
    HaogeSpringTwelveI27CaptureSTUICellularColor(view, keep);
    HaogeSpringTwelveI27Orig8c4c(view, cmd, keep);
}
static void (*HaogeSpringTwelveI27Orig8dcc)(UIView *, SEL, UIColor *);
static void HaogeSpringTwelveI27H8dcc(UIView *view, SEL cmd, UIColor *color) {
    HaogeSpringTwelveI27Orig8dcc(view, cmd, color);
    HaogeSpringTwelveI27RefreshWifiTint(view);
}
static IMP HaogeSpringTwelveI27Orig915c; // The hook's original returns an object.
static id HaogeSpringTwelveI27H915c(id item, SEL cmd, id update, id displayItem) {
    id __attribute__((objc_precise_lifetime)) keep = update;
    id result = ((id (*)(id, SEL, id, id))HaogeSpringTwelveI27Orig915c)(item, cmd, keep, displayItem);
    HaogeSpringTwelveI27UpdateWifiItem(item, keep);
    return result;
}
static void (*HaogeSpringTwelveI27Orig95e0)(UIView *, SEL, NSInteger);
static void HaogeSpringTwelveI27H95e0(UIView *view, SEL cmd, NSInteger bars) {
    HaogeSpringTwelveI27Orig95e0(view, cmd, bars);
    HaogeSpringTwelveI27RenderView(view);
}
static void (*HaogeSpringTwelveI27Orig960c)(UIView *, SEL, UIColor *);
static void HaogeSpringTwelveI27H960c(UIView *view, SEL cmd, UIColor *color) {
    UIColor *__attribute__((objc_precise_lifetime)) keep = color;
    HaogeSpringTwelveI27Orig960c(view, cmd, keep);
    HaogeSpringTwelveI27CaptureUIKitCellularColor(view, keep);
    HaogeSpringTwelveI27RenderView(view);
}

static void (*HaogeSpringTwelveI27Orig9924)(UIImageView *, SEL);
static void HaogeSpringTwelveI27H9924(UIImageView *view, SEL cmd) {
    HaogeSpringTwelveI27Orig9924(view, cmd);
    if (HaogeSpringTwelveI27IsManagedWifiImage(view)) HaogeSpringTwelveI27RenderNetworkImage(view);
    else HaogeSpringTwelveI27SuppressNativeNetworkImage(view);
}
static void (*HaogeSpringTwelveI27Orig99ac)(UIImageView *, SEL, UIImage *);
static void HaogeSpringTwelveI27H99ac(UIImageView *view, SEL cmd, UIImage *image) {
    UIImage *__attribute__((objc_precise_lifetime)) keep = image;
    if (HaogeSpringTwelveI27IsManagedWifiImage(view) && !HaogeSpringTwelveI27IsUpdatingNetworkImage(view)) {
        UIImage *replacement = HaogeSpringTwelveI27NetworkReplacementImage(view);
        HaogeSpringTwelveI27Orig99ac(view, cmd, replacement ?: keep);
    } else if (HaogeSpringTwelveI27ShouldHideNetworkImage(view)) {
        HaogeSpringTwelveI27Orig99ac(view, cmd, nil);
        HaogeSpringTwelveI27SuppressNativeNetworkImage(view);
    } else {
        HaogeSpringTwelveI27Orig99ac(view, cmd, keep);
    }
}
static void (*HaogeSpringTwelveI27Orig9b10)(UIView *, SEL, BOOL);
static void HaogeSpringTwelveI27H9b10(UIView *view, SEL cmd, BOOL hidden) {
    if (HaogeSpringTwelveI27ShouldHideNetworkImage(view)) {
        HaogeSpringTwelveI27Orig9b10(view, cmd, YES);
        HaogeSpringTwelveI27SuppressNativeNetworkImage(view);
    } else HaogeSpringTwelveI27Orig9b10(view, cmd, hidden);
}
static void (*HaogeSpringTwelveI27Orig9b7c)(UIView *, SEL, CGFloat);
static void HaogeSpringTwelveI27H9b7c(UIView *view, SEL cmd, CGFloat alpha) {
    if (HaogeSpringTwelveI27ShouldHideNetworkImage(view)) {
        HaogeSpringTwelveI27Orig9b7c(view, cmd, 0.0);
        HaogeSpringTwelveI27SuppressNativeNetworkImage(view);
    } else HaogeSpringTwelveI27Orig9b7c(view, cmd, alpha);
}
static void (*HaogeSpringTwelveI27Orig9be8)(UIView *, SEL);
static void HaogeSpringTwelveI27H9be8(UIView *view, SEL cmd) {
    HaogeSpringTwelveI27Orig9be8(view, cmd); HaogeSpringTwelveI27SuppressNativeNetworkImage(view);
}
static void (*HaogeSpringTwelveI27Orig9c14)(UIView *, SEL);
static void HaogeSpringTwelveI27H9c14(UIView *view, SEL cmd) {
    HaogeSpringTwelveI27Orig9c14(view, cmd); HaogeSpringTwelveI27SuppressNativeNetworkImage(view);
}

// 0x9c40: hook only an OWN, no-argument method with exact return encoding v.
// Merely asking class_getInstanceMethod would also match inherited methods.
static void HaogeSpringTwelveI27HookOwnVoidMethod(Class cls, const char *name) {
    if (cls == Nil) return;
    SEL sel = sel_registerName(name);
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method chosen = nullptr;
    for (unsigned int i = 0; i < count; ++i) {
        if (sel_isEqual(method_getName(methods[i]), sel)) {
            chosen = methods[i]; break;
        }
    }
    free(methods);
    if (chosen == nullptr || method_getNumberOfArguments(chosen) != 2) return;
    char *type = method_copyReturnType(chosen);
    if (type == nullptr) return;
    BOOL valid = strcmp(type, "v") == 0;
    free(type);
    if (!valid) return;
    __block IMP original = nullptr;
    IMP replacement = imp_implementationWithBlock(^(UIView *view) {
        if (original != nullptr) ((void (*)(UIView *, SEL))original)(view, sel);
        HaogeSpringTwelveI27RenderView(view);
    });
    MSHookMessageEx(cls, sel, replacement, &original);
}

static BOOL HaogeSpringTwelveI27HookIfPresent(Class cls, const char *name,
                                                IMP replacement, IMP *original) {
    if (cls == Nil || name == nullptr || replacement == nullptr || original == nullptr)
        return NO;
    SEL selector = sel_registerName(name);
    Method method = class_getInstanceMethod(cls, selector);
    if (method == nullptr || method_getTypeEncoding(method) == nullptr) return NO;
    MSHookMessageEx(cls, selector, replacement, original);
    return *original != nullptr;
}

#define HaogeSpringTwelveI27_HOOK(cls, selectorName, hex) \
    HaogeSpringTwelveI27HookIfPresent((cls), (selectorName), \
        (IMP)HaogeSpringTwelveI27H##hex, (IMP *)&HaogeSpringTwelveI27Orig##hex)

static BOOL HaogeSpringTwelveI27UIKit16Installed;
static BOOL HaogeSpringTwelveI27STUIInstalled;

static void HaogeSpringTwelveI27InstallUIKit16(void) {
    if (HaogeSpringTwelveI27UIKit16Installed) return;
    if ([[NSProcessInfo processInfo] operatingSystemVersion].majorVersion != 16) return;
    Class signal = objc_getClass("_UIStatusBarSignalView");
    if (signal == Nil) return;
    HaogeSpringTwelveI27_HOOK(signal, "layoutSubviews", 8fe8);
    HaogeSpringTwelveI27_HOOK(signal, "didMoveToWindow", 9014);
    HaogeSpringTwelveI27_HOOK(signal, "traitCollectionDidChange:", 9040);
    Class wifi = objc_getClass("_UIStatusBarWifiSignalView");
    Class cellular = objc_getClass("_UIStatusBarCellularSignalView");
    if (wifi != Nil) {
        HaogeSpringTwelveI27_HOOK(wifi, "layoutSubviews", 90ac);
        HaogeSpringTwelveI27_HOOK(wifi, "didMoveToWindow", 90d8);
    }
    if (cellular != Nil) {
        HaogeSpringTwelveI27_HOOK(cellular, "layoutSubviews", 9104);
        HaogeSpringTwelveI27_HOOK(cellular, "didMoveToWindow", 9130);
    }
    Class item = objc_getClass("_UIStatusBarWifiItem");
    if (item != Nil && class_getInstanceMethod(item,
              sel_registerName("applyUpdate:toDisplayItem:")) != nullptr) {
        HaogeSpringTwelveI27_HOOK(item, "applyUpdate:toDisplayItem:", 915c);
    }
    if (class_getInstanceMethod(signal,
              sel_registerName("setNumberOfActiveBars:")) != nullptr) {
        HaogeSpringTwelveI27_HOOK(signal, "setNumberOfActiveBars:", 95e0);
    }
    if (class_getInstanceMethod(signal, sel_registerName("setActiveColor:")) != nullptr) {
        HaogeSpringTwelveI27_HOOK(signal, "setActiveColor:", 960c);
    }
    if (wifi != Nil) {
        if (class_getInstanceMethod(wifi, sel_registerName("setActiveColor:")) != nullptr) {
            HaogeSpringTwelveI27_HOOK(wifi, "setActiveColor:", 9788);
        }
        if (class_getInstanceMethod(wifi, sel_registerName("applyStyleAttributes:")) != nullptr) {
            HaogeSpringTwelveI27_HOOK(wifi, "applyStyleAttributes:", 97f4);
        }
    }
    Class dual = objc_getClass("_UIStatusBarDualCellularSignalView");
    if (dual != Nil) {
        HaogeSpringTwelveI27_HOOK(dual, "layoutSubviews", 9860);
        HaogeSpringTwelveI27_HOOK(dual, "didMoveToWindow", 988c);
        HaogeSpringTwelveI27_HOOK(dual, "traitCollectionDidChange:", 98b8);
    }
    Class image = objc_getClass("_UIStatusBarImageView");
    if (image != Nil) {
        HaogeSpringTwelveI27_HOOK(image, "layoutSubviews", 9924);
        HaogeSpringTwelveI27_HOOK(image, "setImage:", 99ac);
        HaogeSpringTwelveI27_HOOK(image, "setHidden:", 9b10);
        HaogeSpringTwelveI27_HOOK(image, "setAlpha:", 9b7c);
        HaogeSpringTwelveI27_HOOK(image, "didMoveToSuperview", 9be8);
        HaogeSpringTwelveI27_HOOK(image, "didMoveToWindow", 9c14);
    }
    const char *classes[] = {
        "_UIStatusBarSignalView", "_UIStatusBarWifiSignalView",
        "_UIStatusBarCellularSignalView", "_UIStatusBarCellularSmallSignalView",
        "_UIStatusBarCellularFlatSignalView"
    };
    const char *updates[] = {"_updateBars", "_updateActiveBars", "_colorsDidChange",
        "_updateCycleAnimationIfNeeded", "_updateCycleAnimationNow"};
    for (unsigned i = 0; i < 5; ++i) {
        Class cls = objc_getClass(classes[i]);
        for (const char *method : updates) HaogeSpringTwelveI27HookOwnVoidMethod(cls, method);
        if (i >= 3) {
            HaogeSpringTwelveI27HookOwnVoidMethod(cls, "layoutSubviews");
            HaogeSpringTwelveI27HookOwnVoidMethod(cls, "didMoveToWindow");
        }
    }
    HaogeSpringTwelveI27UIKit16Installed = YES;
}

static void HaogeSpringTwelveI27InstallSTUI(void) {
    if (HaogeSpringTwelveI27STUIInstalled) return;
    Class signal = objc_getClass("STUIStatusBarSignalView");
    if (signal == Nil) return;
    // No independent version or per-method guard is present in this group.
    HaogeSpringTwelveI27_HOOK(signal, "_updateBars", 8bc8);
    HaogeSpringTwelveI27_HOOK(signal, "_updateActiveBars", 8bf4);
    HaogeSpringTwelveI27_HOOK(signal, "layoutSubviews", 8c20);
    HaogeSpringTwelveI27_HOOK(signal, "setActiveColor:", 8c4c);
    Class cellular = objc_getClass("STUIStatusBarCellularSignalView");
    HaogeSpringTwelveI27_HOOK(cellular, "_updateBars", 8cf0);
    HaogeSpringTwelveI27_HOOK(cellular, "_updateActiveBars", 8d1c);
    HaogeSpringTwelveI27_HOOK(cellular, "layoutSubviews", 8d48);
    Class small = objc_getClass("STUIStatusBarCellularSmallSignalView");
    HaogeSpringTwelveI27_HOOK(small, "layoutSubviews", 8d74);
    Class flat = objc_getClass("STUIStatusBarCellularFlatSignalView");
    HaogeSpringTwelveI27_HOOK(flat, "layoutSubviews", 8da0);
    Class wifi = objc_getClass("STUIStatusBarWifiSignalView");
    HaogeSpringTwelveI27_HOOK(wifi, "setActiveColor:", 8dcc);
    HaogeSpringTwelveI27_HOOK(wifi, "applyStyleAttributes:", 8e74);
    HaogeSpringTwelveI27_HOOK(wifi, "_updateBars", 8ee0);
    HaogeSpringTwelveI27_HOOK(wifi, "_updateActiveBars", 8f0c);
    HaogeSpringTwelveI27_HOOK(wifi, "_updateCycleAnimationIfNeeded", 8f38);
    HaogeSpringTwelveI27_HOOK(wifi, "_updateCycleAnimationNow", 8f64);
    HaogeSpringTwelveI27_HOOK(wifi, "layoutSubviews", 8f90);
    Class dual = objc_getClass("STUIStatusBarDualCellularSignalView");
    HaogeSpringTwelveI27_HOOK(dual, "layoutSubviews", 8fbc);
    HaogeSpringTwelveI27STUIInstalled = YES;
}

extern "C" void HaogeSpringTwelveInstallIOS27StatusBar(void) {
    static dispatch_once_t installOnce;
    dispatch_once(&installOnce, ^{
        @autoreleasepool {
            if (objc_getClass("UIApplication") == Nil) return;
            if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 16) return;
            BOOL battery = HaogeSpringTwelveI27InstallBatteryHooks();
            HaogeSpringTwelveI27InstallUIKit16();
            HaogeSpringTwelveI27InstallSTUI();
            dispatch_async(dispatch_get_main_queue(), ^{ HaogeSpringTwelveI27InitialRefresh(); });
            NSLog(@"[iOS27StatusBar native16] loaded; UIKit16 hooks=%d, STUI hooks=%d, battery hooks=%d",
                  HaogeSpringTwelveI27UIKit16Installed, HaogeSpringTwelveI27STUIInstalled, battery);
        }
    });
}
