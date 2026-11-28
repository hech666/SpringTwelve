// Independent static semantic reconstruction; not the original author's source.
// arm64 addresses below identify evidence, not hard-coded runtime addresses.
#import "HaogeSpringTwelveI27Runtime.h"
#import "HaogeSpringTwelveI27Drawing.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <float.h>

// Identity keys replace the original self-pointing globals 0x14560..0x145a0.
static char HaogeSpringTwelveI27RenderingKey;       // 0x14560
static char HaogeSpringTwelveI27WifiOverlayKey;     // 0x14568
static char HaogeSpringTwelveI27TopOverlayKey;      // 0x14570
static char HaogeSpringTwelveI27BottomOverlayKey;   // 0x14578
static char HaogeSpringTwelveI27CellularColorKey;   // 0x14580
static char HaogeSpringTwelveI27SingleOverlayKey;   // 0x14588
static char HaogeSpringTwelveI27NetworkSizeKey;     // 0x14590
static char HaogeSpringTwelveI27NetworkBarsKey;     // 0x14598
static char HaogeSpringTwelveI27NetworkUpdatingKey; // 0x145a0
static BOOL HaogeSpringTwelveI27LoggedKind[3];
static BOOL HaogeSpringTwelveI27LoggedNetworkImage;

static const NSInteger HaogeSpringTwelveI27WifiTag = 83369;
static const NSInteger HaogeSpringTwelveI27SingleTag = 110234;
static const NSInteger HaogeSpringTwelveI27TopTag = 110235;
static const NSInteger HaogeSpringTwelveI27BottomTag = 110236;

typedef NS_ENUM(NSInteger, HaogeSpringTwelveI27RuntimeKind) {
    HaogeSpringTwelveI27RuntimeWifi = 0, HaogeSpringTwelveI27RuntimeCellular = 1,
    HaogeSpringTwelveI27RuntimeDual = 2, HaogeSpringTwelveI27RuntimeOther = 3
};

static id HaogeSpringTwelveI27Get(id object, const void *key) {
    return object ? objc_getAssociatedObject(object, key) : nil;
}
static void HaogeSpringTwelveI27Set(id object, const void *key, id value) {
    if (object) objc_setAssociatedObject(object, key, value,
                                        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static id HaogeSpringTwelveI27ObjectGetter(id object, const char *name) {
    SEL selector = sel_registerName(name);
    if (![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}
static BOOL HaogeSpringTwelveI27VisibleColor(id color) {
    return [color isKindOfClass:[UIColor class]] &&
           CGColorGetAlpha([(UIColor *)color CGColor]) > 0x1.47ae147ae147bp-7;
}
// 0xbb80: no local exception swallowing and no KVC.
static UIColor *HaogeSpringTwelveI27ColorGetter(id object, const char *name) {
    if (!object || !name) return nil;
    id value = HaogeSpringTwelveI27ObjectGetter(object, name);
    return HaogeSpringTwelveI27VisibleColor(value) ? value : nil;
}

// 0xac84: both accessors suffice; otherwise use the class-name substring.
static BOOL HaogeSpringTwelveI27IsDual(UIView *view) {
    if ([view respondsToSelector:sel_registerName("topSignalView")] &&
        [view respondsToSelector:sel_registerName("bottomSignalView")]) return YES;
    const char *name = class_getName(object_getClass(view));
    return name && strstr(name, "DualCellularSignal") != NULL;
}
// 0xa144: deliberately do not classify arbitrary UIImageViews as signal views.
static HaogeSpringTwelveI27RuntimeKind HaogeSpringTwelveI27Kind(UIView *view) {
    const char *name = class_getName(object_getClass(view));
    if (!name || !strstr(name, "StatusBar") || !strstr(name, "Signal"))
        return HaogeSpringTwelveI27RuntimeOther;
    if (HaogeSpringTwelveI27IsDual(view)) return HaogeSpringTwelveI27RuntimeDual;
    if (strstr(name, "Wifi") || strstr(name, "WiFi")) return HaogeSpringTwelveI27RuntimeWifi;
    return strstr(name, "Cellular") ? HaogeSpringTwelveI27RuntimeCellular : HaogeSpringTwelveI27RuntimeOther;
}
// 0xa224: includes the starting view, with no invented depth limit.
static UIView *HaogeSpringTwelveI27DualAncestor(UIView *view) {
    for (UIView *cursor = view; cursor; cursor = cursor.superview)
        if (HaogeSpringTwelveI27IsDual(cursor)) return cursor;
    return nil;
}
static Ivar HaogeSpringTwelveI27FindIvar(id object, const char *name) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        Ivar ivar = class_getInstanceVariable(cls, name);
        if (ivar) return ivar;
    }
    return NULL;
}

// 0xad5c type jump tables: B/C unsigned byte, c signed byte, s/S 16,
// i/I 32, l/L/q/Q 64. A 64-bit unsigned payload is clamped as signed by
// the original LDR + signed CSEL sequence; do not turn it into NSUInteger.
static BOOL HaogeSpringTwelveI27ReadIntegralIvar(id object, Ivar ivar, NSInteger *value) {
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type) return NO;
    const uint8_t *p = (const uint8_t *)(__bridge const void *)object
                       + ivar_getOffset(ivar);
    switch (*type) {
        case 'B': case 'C': { uint8_t x; memcpy(&x, p, 1); *value = x; break; }
        case 'c': { int8_t x; memcpy(&x, p, 1); *value = x; break; }
        case 's': { int16_t x; memcpy(&x, p, 2); *value = x; break; }
        case 'S': { uint16_t x; memcpy(&x, p, 2); *value = x; break; }
        case 'i': { int32_t x; memcpy(&x, p, 4); *value = x; break; }
        case 'I': { uint32_t x; memcpy(&x, p, 4); *value = x; break; }
        case 'l': case 'L': case 'q': case 'Q': {
            int64_t x; memcpy(&x, p, 8); *value = (NSInteger)x; break;
        }
        default: return NO;
    }
    return YES;
}
static NSInteger HaogeSpringTwelveI27Bars(UIView *view, NSInteger maximum) {
    SEL getter = sel_registerName("numberOfActiveBars");
    if ([view respondsToSelector:getter]) {
        NSInteger n = ((NSInteger (*)(id, SEL))objc_msgSend)(view, getter);
        if (n >= 0 && (NSUInteger)n <= (NSUInteger)(maximum + 2))
            return n < maximum ? n : maximum;
    }
    static const char *const names[] = {
        "_numberOfActiveBars", "numberOfActiveBars", "_activeBars",
        "activeBars", "_displayValue"
    };
    for (const char *name : names) {
        Ivar ivar = HaogeSpringTwelveI27FindIvar(view, name);
        NSInteger n;
        if (ivar && HaogeSpringTwelveI27ReadIntegralIvar(view, ivar, &n))
            return n < 0 ? 0 : n > maximum ? maximum : n;
    }
    return 0;
}

// 0xbce4: inspect at most 40 views, including self. Only the FIRST actual
// status-bar ancestor is queried. foregroundColor is on that VIEW, not attrs.
static UIColor *HaogeSpringTwelveI27StatusBarColor(UIView *view) {
    Class stui = (Class)objc_getClass("STUIStatusBar");
    Class uikit = (Class)objc_getClass("_UIStatusBar");
    UIView *cursor = view;
    for (unsigned n = 0; cursor && n < 40; ++n, cursor = cursor.superview) {
        if ((stui && [cursor isKindOfClass:stui]) ||
            (uikit && [cursor isKindOfClass:uikit])) {
            id attrs = HaogeSpringTwelveI27ObjectGetter(cursor, "styleAttributes");
            UIColor *color = HaogeSpringTwelveI27ColorGetter(attrs, "imageTintColor");
            if (!color) color = HaogeSpringTwelveI27ColorGetter(attrs, "textColor");
            if (!color) color = HaogeSpringTwelveI27ColorGetter(cursor, "foregroundColor");
            return color;
        }
    }
    return nil;
}
static UIColor *HaogeSpringTwelveI27TraitColor(UIView *view) {
    if (view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight)
        return [UIColor blackColor];
    // The non-light branch evaluates this accessor again in 0xb638/0xcb18.
    (void)view.traitCollection.userInterfaceStyle;
    return [UIColor whiteColor];
}
static UIColor *HaogeSpringTwelveI27WifiColor(UIView *view) { // 0xb570
    UIColor *color = HaogeSpringTwelveI27ColorGetter(view, "activeColor");
    if (!color) color = HaogeSpringTwelveI27StatusBarColor(view);
    return color ?: HaogeSpringTwelveI27TraitColor(view);
}
void HaogeSpringTwelveI27CaptureCellularColor(UIView *view, UIColor *color) { // 0xd2d0
    if (view && HaogeSpringTwelveI27VisibleColor(color)) HaogeSpringTwelveI27Set(view, &HaogeSpringTwelveI27CellularColorKey, color);
}
static UIColor *HaogeSpringTwelveI27CellularColor(UIView *view) { // 0xc960
    UIColor *color = HaogeSpringTwelveI27StatusBarColor(view);
    if (color) return color;
    color = HaogeSpringTwelveI27Get(view, &HaogeSpringTwelveI27CellularColorKey);
    if (HaogeSpringTwelveI27VisibleColor(color)) return color;
    color = HaogeSpringTwelveI27ColorGetter(view, "activeColor");
    if (color) { HaogeSpringTwelveI27CaptureCellularColor(view, color); return color; }
    return HaogeSpringTwelveI27TraitColor(view);
}
void HaogeSpringTwelveI27CaptureWifiColor(UIView *view, UIColor *color) { // 0x8dcc post-orig
    (void)color;
    UIImageView *overlay = HaogeSpringTwelveI27Get(view, &HaogeSpringTwelveI27WifiOverlayKey);
    if (overlay) overlay.tintColor = HaogeSpringTwelveI27WifiColor(view);
}

static BOOL HaogeSpringTwelveI27ProtectedTag(NSInteger tag) {
    return tag == HaogeSpringTwelveI27WifiTag || (tag >= HaogeSpringTwelveI27SingleTag && tag <= HaogeSpringTwelveI27BottomTag);
}
// 0xbee8: a non-UIView, NON-nil delegate is not itself hidden. Only a nil
// delegate causes removeAllAnimations/opacity=0/hidden=YES. Other layers recurse.
static void HaogeSpringTwelveI27HideNativeSublayers(CALayer *root) {
    if (!root) return;
    for (CALayer *layer in root.sublayers) {
        id delegate = layer.delegate;
        if ([delegate isKindOfClass:[UIView class]] &&
            HaogeSpringTwelveI27ProtectedTag([(UIView *)delegate tag])) continue;
        if (!delegate) {
            [layer removeAllAnimations];
            layer.opacity = 0.0f;
            layer.hidden = YES;
        }
        HaogeSpringTwelveI27HideNativeSublayers(layer);
    }
}
// 0xc170: preserve tagged overlays, restoring their VIEW hidden/alpha only.
static void HaogeSpringTwelveI27HideNativeSubviews(UIView *root) {
    if (!root) return;
    for (UIView *child in root.subviews) {
        if (HaogeSpringTwelveI27ProtectedTag(child.tag)) {
            child.hidden = NO;
            child.alpha = 1.0;
            continue;
        }
        if ([child isKindOfClass:[UIImageView class]]) {
            child.hidden = YES;
            child.alpha = 0.0;
            child.layer.hidden = YES;
            child.layer.opacity = 0.0f;
            child.layer.contents = nil;
        }
        HaogeSpringTwelveI27HideNativeSubviews(child);
    }
}
// 0xa384 / 0xcd38. No added @finally around CATransaction: the original
// cleanup paths do not commit the transaction when a private API throws.
static void HaogeSpringTwelveI27EraseNativeDrawing(UIView *view) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    view.layer.contents = nil;
    HaogeSpringTwelveI27HideNativeSublayers(view.layer);
    HaogeSpringTwelveI27HideNativeSubviews(view);
    [CATransaction commit];
}
static void HaogeSpringTwelveI27SuppressCellular(UIView *view) { // 0xcc34
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 17) {
        UIColor *clear = [UIColor clearColor];
        SEL active = sel_registerName("setActiveColor:");
        SEL inactive = sel_registerName("setInactiveColor:");
        if ([view respondsToSelector:active])
            ((void (*)(id, SEL, id))objc_msgSend)(view, active, clear);
        if ([view respondsToSelector:inactive])
            ((void (*)(id, SEL, id))objc_msgSend)(view, inactive, clear);
    }
    HaogeSpringTwelveI27EraseNativeDrawing(view);
}
static UIImageView *HaogeSpringTwelveI27Overlay(UIView *host, const void *key, NSInteger tag) {
    UIImageView *overlay = HaogeSpringTwelveI27Get(host, key); // 0xb708
    if (overlay) {
        if (overlay.superview != host) {
            [overlay removeFromSuperview];
            [host addSubview:overlay];
        }
    } else {
        overlay = [[UIImageView alloc] initWithFrame:host.bounds];
        overlay.tag = tag;
        overlay.contentMode = UIViewContentModeScaleAspectFill; // initial raw 2
        overlay.userInteractionEnabled = NO;
        overlay.clipsToBounds = NO;
        overlay.isAccessibilityElement = NO;
        HaogeSpringTwelveI27Set(host, key, overlay);
        [host addSubview:overlay];
    }
    [host bringSubviewToFront:overlay];
    return overlay;
}

// 0xce38: getter result is type checked; then object_getIvar, with no invented
// type-encoding validation (the original assumes these are object ivars).
static UIView *HaogeSpringTwelveI27ChildView(id object, const char *getter, const char *ivarName) {
    id candidate = HaogeSpringTwelveI27ObjectGetter(object, getter);
    if ([candidate isKindOfClass:[UIView class]]) return candidate;
    Ivar ivar = HaogeSpringTwelveI27FindIvar(object, ivarName);
    candidate = ivar ? object_getIvar(object, ivar) : nil;
    return [candidate isKindOfClass:[UIView class]] ? candidate : nil;
}
struct HaogeSpringTwelveI27SignalPair {
    __unsafe_unretained UIView *top;
    CGFloat topY;
    __unsafe_unretained UIView *bottom;
    CGFloat bottomY;
};
// 0xcfa0: selects the two SMALLEST centerY values, not min/max. Initial budget
// 4 still examines immediate children at budget 0; do not introduce !=root or
// class-name tests. Responding to numberOfActiveBars is the entire predicate.
static void HaogeSpringTwelveI27FindSignalPair(UIView *node, UIView *coordinateHost,
                              HaogeSpringTwelveI27SignalPair *pair, NSUInteger budget) {
    if (!node) return;
    SEL bars = sel_registerName("numberOfActiveBars");
    for (UIView *child in node.subviews) {
        if ([child respondsToSelector:bars]) {
            CGFloat y = CGRectGetMidY([child convertRect:child.bounds
                                                 toView:coordinateHost]);
            if (!pair->top || y < pair->topY) {
                pair->bottom = pair->top;
                pair->bottomY = pair->topY;
                pair->top = child;
                pair->topY = y;
            } else if (!pair->bottom || y < pair->bottomY) {
                pair->bottom = child;
                pair->bottomY = y;
            }
        }
        if (budget) HaogeSpringTwelveI27FindSignalPair(child, coordinateHost, pair, budget - 1);
    }
}
static void HaogeSpringTwelveI27RenderDual(UIView *view);
static void HaogeSpringTwelveI27RenderWifi(UIView *view) { // 0xa2b8
    NSInteger bars = HaogeSpringTwelveI27Bars(view, 3);
    CGRect bounds = view.bounds;
    if (!(bounds.size.width > 0.1 && bounds.size.height > 0.1)) return;
    CGSize size = HaogeSpringTwelveI27GlyphSize(HaogeSpringTwelveI27GlyphKindWiFi, bounds.size);
    UIImage *image = HaogeSpringTwelveI27MakeGlyph(HaogeSpringTwelveI27GlyphKindWiFi, bars, size);
    if (!image) return;
    UIColor *color = HaogeSpringTwelveI27WifiColor(view);
    HaogeSpringTwelveI27EraseNativeDrawing(view);
    UIImageView *overlay = HaogeSpringTwelveI27Overlay(view, &HaogeSpringTwelveI27WifiOverlayKey, HaogeSpringTwelveI27WifiTag);
    overlay.contentMode = UIViewContentModeCenter; // raw 4, not aspect-fit
    overlay.image = image;
    overlay.tintColor = color;
    HaogeSpringTwelveI27CenterGlyphView(view, overlay, image.size);
}
static void HaogeSpringTwelveI27RenderSingle(UIView *view) { // 0xa9bc
    UIView *dual = HaogeSpringTwelveI27DualAncestor(view);
    if (dual && dual != view) { HaogeSpringTwelveI27RenderDual(dual); return; }
    NSInteger bars = HaogeSpringTwelveI27Bars(view, 4);
    CGSize size = HaogeSpringTwelveI27GlyphSize(HaogeSpringTwelveI27GlyphKindSingleSIM, view.bounds.size);
    UIImage *image = HaogeSpringTwelveI27MakeGlyph(HaogeSpringTwelveI27GlyphKindSingleSIM, bars, size);
    if (!image) image = HaogeSpringTwelveI27MakeGlyph(HaogeSpringTwelveI27GlyphKindCellular, bars, size);
    if (!image) return;
    UIColor *color = HaogeSpringTwelveI27CellularColor(view);
    HaogeSpringTwelveI27SuppressCellular(view);
    UIImageView *overlay = HaogeSpringTwelveI27Overlay(view, &HaogeSpringTwelveI27SingleOverlayKey, HaogeSpringTwelveI27SingleTag);
    overlay.contentMode = UIViewContentModeCenter;
    overlay.image = image;
    overlay.tintColor = color;
    HaogeSpringTwelveI27CenterGlyphView(view, overlay, image.size);
}
static void HaogeSpringTwelveI27RenderDual(UIView *view) { // 0xa558
    UIView *top = HaogeSpringTwelveI27ChildView(view, "topSignalView", "_topSignalView");
    UIView *bottom = HaogeSpringTwelveI27ChildView(view, "bottomSignalView", "_bottomSignalView");
    if (!top || !bottom) {
        HaogeSpringTwelveI27SignalPair pair = { nil, DBL_MAX, nil, DBL_MAX };
        HaogeSpringTwelveI27FindSignalPair(view, view, &pair, 4);
        if (!top) top = pair.top;
        if (!bottom) bottom = pair.bottom;
    }
    NSInteger topBars = top ? HaogeSpringTwelveI27Bars(top, 4) : 0;
    NSInteger bottomBars = bottom ? HaogeSpringTwelveI27Bars(bottom, 4) : 0;
    CGSize size = HaogeSpringTwelveI27GlyphSize(HaogeSpringTwelveI27GlyphKindCellular, view.bounds.size);
    UIImage *upper = HaogeSpringTwelveI27MakeGlyph(HaogeSpringTwelveI27GlyphKindCellular, topBars, size);
    UIImage *lower = HaogeSpringTwelveI27MakeGlyph(HaogeSpringTwelveI27GlyphKindCellular2, bottomBars, size);
    if (!upper && !lower) return;
    UIColor *color = HaogeSpringTwelveI27CellularColor(view);
    if (top) HaogeSpringTwelveI27SuppressCellular(top);
    if (bottom) HaogeSpringTwelveI27SuppressCellular(bottom);
    HaogeSpringTwelveI27SuppressCellular(view);
    UIImageView *upperView = HaogeSpringTwelveI27Overlay(view, &HaogeSpringTwelveI27TopOverlayKey, HaogeSpringTwelveI27TopTag);
    upperView.hidden = upper == nil;
    upperView.contentMode = UIViewContentModeCenter;
    upperView.image = upper;
    upperView.tintColor = color;
    HaogeSpringTwelveI27CenterGlyphView(view, upperView, upper ? upper.size : size);
    UIImageView *lowerView = HaogeSpringTwelveI27Overlay(view, &HaogeSpringTwelveI27BottomOverlayKey, HaogeSpringTwelveI27BottomTag);
    lowerView.hidden = lower == nil;
    lowerView.contentMode = UIViewContentModeCenter;
    lowerView.image = lower;
    lowerView.tintColor = color;
    HaogeSpringTwelveI27CenterGlyphView(view, lowerView, lower ? lower.size : size);
}

void HaogeSpringTwelveI27RenderView(UIView *view) { // 0x9dc0
    if (!view || ![NSThread isMainThread]) return;
    if (HaogeSpringTwelveI27Kind(view) == HaogeSpringTwelveI27RuntimeCellular) {
        UIView *dual = HaogeSpringTwelveI27DualAncestor(view);
        if (dual) view = dual;
    }
    HaogeSpringTwelveI27RuntimeKind kind = HaogeSpringTwelveI27Kind(view);
    if (kind == HaogeSpringTwelveI27RuntimeOther) return;
    if ([HaogeSpringTwelveI27Get(view, &HaogeSpringTwelveI27RenderingKey) boolValue]) return;
    if (!HaogeSpringTwelveI27LoggedKind[kind] && view.bounds.size.width > 0.1 &&
        view.bounds.size.height > 0.1) {
        HaogeSpringTwelveI27LoggedKind[kind] = YES;
        NSLog(@"[iOS27StatusBar native16] rendering class=%@ kind=%ld bounds=%@",
              NSStringFromClass(view.class), (long)kind, NSStringFromCGRect(view.bounds));
    }
    HaogeSpringTwelveI27Set(view, &HaogeSpringTwelveI27RenderingKey, @YES);
    @try {
        switch (HaogeSpringTwelveI27Kind(view)) {
            case HaogeSpringTwelveI27RuntimeWifi: HaogeSpringTwelveI27RenderWifi(view); break;
            case HaogeSpringTwelveI27RuntimeDual: HaogeSpringTwelveI27RenderDual(view); break;
            case HaogeSpringTwelveI27RuntimeCellular: {
                UIView *dual = HaogeSpringTwelveI27DualAncestor(view);
                if (dual && dual != view) HaogeSpringTwelveI27RenderDual(dual);
                else HaogeSpringTwelveI27RenderSingle(view);
                break;
            }
            default: break;
        }
    } @catch (NSException *exception) {
        (void)exception; // observed specific handler, not @catch(id)
    } @finally {
        HaogeSpringTwelveI27Set(view, &HaogeSpringTwelveI27RenderingKey, nil);
    }
}

void HaogeSpringTwelveI27RefreshWifiTint(UIView *view) {
    HaogeSpringTwelveI27CaptureWifiColor(view, nil);
}
BOOL HaogeSpringTwelveI27IsManagedWifiImage(UIView *view) {
    return HaogeSpringTwelveI27Get(view, &HaogeSpringTwelveI27NetworkBarsKey) != nil;
}
BOOL HaogeSpringTwelveI27IsUpdatingNetworkImage(UIView *view) {
    return [HaogeSpringTwelveI27Get(view, &HaogeSpringTwelveI27NetworkUpdatingKey) boolValue];
}
// 0xd928: the managed network-icon mark excludes an image even at level @0.
// Only ANCESTORS with both class-name substrings and any signal overlay count.
BOOL HaogeSpringTwelveI27ShouldHideNetworkImage(UIView *view) {
    if (HaogeSpringTwelveI27IsManagedWifiImage(view)) return NO;
    for (UIView *cursor = view.superview; cursor; cursor = cursor.superview) {
        const char *name = class_getName(object_getClass(cursor));
        if (!name || !strstr(name, "StatusBar") || !strstr(name, "Signal")) continue;
        if (HaogeSpringTwelveI27Get(cursor, &HaogeSpringTwelveI27SingleOverlayKey) ||
            HaogeSpringTwelveI27Get(cursor, &HaogeSpringTwelveI27TopOverlayKey) ||
            HaogeSpringTwelveI27Get(cursor, &HaogeSpringTwelveI27BottomOverlayKey) ||
            HaogeSpringTwelveI27Get(cursor, &HaogeSpringTwelveI27WifiOverlayKey)) return YES;
    }
    return NO;
}
void HaogeSpringTwelveI27SuppressNativeNetworkImage(UIView *view) { // 0xd7f0
    if (!view || !HaogeSpringTwelveI27ShouldHideNetworkImage(view)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    view.layer.contents = nil;
    view.layer.hidden = YES;
    view.layer.opacity = 0.0f;
    [CATransaction commit];
}
// 0xd664: this is intentionally NOT main-thread gated, since setImage:'s
// managed/no-guard branch calls this factory directly in the original binary.
UIImage *HaogeSpringTwelveI27NetworkReplacementImage(UIImageView *imageView) {
    NSNumber *bars = HaogeSpringTwelveI27Get(imageView, &HaogeSpringTwelveI27NetworkBarsKey);
    if (!bars) return nil;
    NSValue *saved = HaogeSpringTwelveI27Get(imageView, &HaogeSpringTwelveI27NetworkSizeKey);
    CGSize nativeSize = saved ? saved.CGSizeValue : imageView.bounds.size;
    if (!(nativeSize.width > 0.1 && nativeSize.height > 0.1)) return nil;
    CGSize size = HaogeSpringTwelveI27GlyphSize(HaogeSpringTwelveI27GlyphKindWiFi, nativeSize);
    return HaogeSpringTwelveI27MakeGlyph(HaogeSpringTwelveI27GlyphKindWiFi, bars.integerValue, size);
}
void HaogeSpringTwelveI27RenderNetworkImage(UIImageView *imageView) { // 0xd3f8
    if (!imageView || ![NSThread isMainThread] ||
        !HaogeSpringTwelveI27IsManagedWifiImage(imageView) ||
        HaogeSpringTwelveI27IsUpdatingNetworkImage(imageView)) return;
    UIImage *image = HaogeSpringTwelveI27NetworkReplacementImage(imageView);
    if (!image) return;
    HaogeSpringTwelveI27Set(imageView, &HaogeSpringTwelveI27NetworkUpdatingKey, @YES);
    @try {
        imageView.contentMode = UIViewContentModeCenter;
        imageView.image = image;
        if (!HaogeSpringTwelveI27LoggedNetworkImage) {
            HaogeSpringTwelveI27LoggedNetworkImage = YES;
            NSLog(@"[iOS27StatusBar native16] rendering networkIconView class=%@ bounds=%@",
                  NSStringFromClass(imageView.class), NSStringFromCGRect(imageView.bounds));
        }
    } @finally {
        // No catch here: 0xd628 catches only to execute cleanup then rethrows.
        HaogeSpringTwelveI27Set(imageView, &HaogeSpringTwelveI27NetworkUpdatingKey, nil);
    }
}
void HaogeSpringTwelveI27UpdateWifiItem(id item, id update) { // 0x915c post-orig body
    id candidate = HaogeSpringTwelveI27ObjectGetter(item, "networkIconView");
    if (![candidate isKindOfClass:[UIImageView class]]) return;
    UIImageView *imageView = candidate;
    if (!HaogeSpringTwelveI27IsManagedWifiImage(imageView)) {
        UIImage *oldImage = imageView.image;
        if (oldImage) HaogeSpringTwelveI27Set(imageView, &HaogeSpringTwelveI27NetworkSizeKey,
                              [NSValue valueWithCGSize:oldImage.size]);
    }
    id data = HaogeSpringTwelveI27ObjectGetter(update, "data");
    id entry = HaogeSpringTwelveI27ObjectGetter(data, "wifiEntry");
    SEL display = sel_registerName("displayValue");
    NSInteger bars = -1;
    if ([entry respondsToSelector:display])
        bars = ((NSInteger (*)(id, SEL))objc_msgSend)(entry, display);
    // Unsigned test also rejects negative values, exactly as CMP + B.LO.
    if ((NSUInteger)bars > 3) {
        id signalView = HaogeSpringTwelveI27ObjectGetter(item, "signalView");
        if (!signalView) return;
        bars = HaogeSpringTwelveI27Bars(signalView, 3);
        if ((NSUInteger)bars > 3) return;
    }
    HaogeSpringTwelveI27Set(imageView, &HaogeSpringTwelveI27NetworkBarsKey, @(bars));
    HaogeSpringTwelveI27RenderNetworkImage(imageView);
}

static void HaogeSpringTwelveI27WalkViewTree(UIView *view) { // 0xdb90
    if (!view) return;
    if (HaogeSpringTwelveI27Kind(view) != HaogeSpringTwelveI27RuntimeOther) HaogeSpringTwelveI27RenderView(view);
    for (UIView *child in view.subviews) HaogeSpringTwelveI27WalkViewTree(child);
}
void HaogeSpringTwelveI27InitialRefresh(void) { // 0x755c block body, dispatch is external
    @try {
        UIApplication *application = [UIApplication sharedApplication];
        if (!application) return;
        for (id scene in application.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in [(UIWindowScene *)scene windows])
                HaogeSpringTwelveI27WalkViewTree(window);
        }
    } @catch (NSException *exception) {
        (void)exception;
    }
}

// Hook-facing adapters preserve the distinct 0x8c4c and 0x960c ordering.
// Neither calls an original IMP nor renders; those operations belong to hooks.
void HaogeSpringTwelveI27CaptureSTUICellularColor(UIView *view, UIColor *color) {
    if (color && CGColorGetAlpha(color.CGColor) > 0x1.47ae147ae147bp-7)
        HaogeSpringTwelveI27CaptureCellularColor(view, color);
}
void HaogeSpringTwelveI27CaptureUIKitCellularColor(UIView *view, UIColor *color) {
    UIColor *effective = HaogeSpringTwelveI27ColorGetter(view, "activeColor") ?: color;
    if (HaogeSpringTwelveI27VisibleColor(effective)) HaogeSpringTwelveI27CaptureCellularColor(view, effective);
}
