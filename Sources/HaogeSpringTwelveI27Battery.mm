// ARC semantic reconstruction of the arm64 battery module, 0x7818–0x8bc8.
// Addresses refer to evidence/arm64.dylib, not to the arm64e slice.
// See evidence/BATTERY-RECONSTRUCTION.md for evidence and unresolved boundaries.
#import "HaogeSpringTwelveI27Battery.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <stdint.h>

#if !__has_feature(objc_arc)
#error HaogeSpringTwelveI27Battery.mm requires Objective-C ARC.
#endif

extern "C" void MSHookMessageEx(Class cls, SEL selector, IMP replacement,
                                IMP *original);

// Declarations only, not implementations or claims about any other OS version.
// Every private selector below is present in the supplied binary's selrefs.
@interface UIView (HaogeSpringTwelveI27BatteryObservedSelectors)
- (UIColor *)bodyColor;
- (UIColor *)pinColor;
- (UIView *)percentageLabel;
- (void)setShowsPercentage:(BOOL)shows;
- (void)_updateBolt;
- (void)_updateLightningBoltAndPercentagePosition;
@end

// Original key slots: 0x14548, 0x14550, 0x14558, each self-referential.
// All three associations use policy 1 (RETAIN_NONATOMIC), including removals.
static const void *HaogeSpringTwelveI27BatteryRequestedKey = &HaogeSpringTwelveI27BatteryRequestedKey;
static const void *HaogeSpringTwelveI27BatteryRefreshGuardKey = &HaogeSpringTwelveI27BatteryRefreshGuardKey;
static const void *HaogeSpringTwelveI27BatteryOverrideDepthKey = &HaogeSpringTwelveI27BatteryOverrideDepthKey;
static BOOL HaogeSpringTwelveI27BatteryInstalled;                   // Original 0x14642.
static BOOL HaogeSpringTwelveI27BatteryIvarLookupAttempted;         // Original 0x14688.
static Ivar HaogeSpringTwelveI27BatteryShowsPercentageIvar;         // Original 0x14690.

static UIColor *(*HaogeSpringTwelveI27BatteryOriginalTextColor)(UIView *, SEL);
static void (*HaogeSpringTwelveI27BatteryOriginalSetShowsPercentage)(UIView *, SEL, BOOL);
static void (*HaogeSpringTwelveI27BatteryOriginalUpdateBolt)(UIView *, SEL);
static void (*HaogeSpringTwelveI27BatteryOriginalUpdatePosition)(UIView *, SEL);
static void (*HaogeSpringTwelveI27BatteryOriginalLayoutSubviews)(UIView *, SEL);
static void (*HaogeSpringTwelveI27BatteryOriginalTraitCollectionDidChange)(UIView *, SEL,
                                                          UITraitCollection *);
static BOOL (*HaogeSpringTwelveI27BatteryOriginalShowsPercentage)(UIView *, SEL);
static BOOL (*HaogeSpringTwelveI27BatteryOriginalCurrentlyShowsPercentage)(UIView *, SEL);

// Shared inlined lookup from 0x8640 / 0x8774. Deliberately not dispatch_once:
// the attempted flag is set BEFORE lookup, and a failed lookup is never retried.
static Ivar HaogeSpringTwelveI27BatteryResolveShowsPercentageIvar(void) {
    if (!HaogeSpringTwelveI27BatteryIvarLookupAttempted) {
        HaogeSpringTwelveI27BatteryIvarLookupAttempted = YES;
        Class cls = objc_getClass("_UIBatteryView");
        if (cls != Nil) {
            HaogeSpringTwelveI27BatteryShowsPercentageIvar =
                class_getInstanceVariable(cls, "_showsPercentage");
            if (HaogeSpringTwelveI27BatteryShowsPercentageIvar == nullptr) {
                HaogeSpringTwelveI27BatteryShowsPercentageIvar =
                    class_getInstanceVariable(cls, "showsPercentage");
            }
        }
    }
    return HaogeSpringTwelveI27BatteryShowsPercentageIvar;
}

// 0x8640: success is distinct from the returned raw flag. Failure does not
// touch *value. No getter/KVC fallback: calling a hooked getter would recurse.
static BOOL HaogeSpringTwelveI27BatteryReadRawShowsPercentage(UIView *battery, BOOL *value) {
    if (battery == nil) return NO;
    Ivar ivar = HaogeSpringTwelveI27BatteryResolveShowsPercentageIvar();
    if (ivar == nullptr) return NO;
    const char *type = ivar_getTypeEncoding(ivar);
    ptrdiff_t offset = ivar_getOffset(ivar);
    if (type == nullptr) return NO;
    if (type[0] != 'B' && type[0] != 'c' && type[0] != 'C') return NO;
    const uint8_t *bytes = (const uint8_t *)(__bridge const void *)battery;
    uint8_t raw = bytes[offset];
    // In the original B loads are masked to bit zero; c/C are first normalized
    // by cmp/cset. This intentionally distinguishes noncanonical bytes 2, 254.
    *value = type[0] == 'B' ? ((raw & 1U) != 0) : (raw != 0);
    return YES;
}

// 0x8774: write one byte, only for the same B/c/C encodings.
static void HaogeSpringTwelveI27BatteryWriteRawShowsPercentage(UIView *battery, BOOL value) {
    if (battery == nil) return;
    Ivar ivar = HaogeSpringTwelveI27BatteryResolveShowsPercentageIvar();
    if (ivar == nullptr) return;
    const char *type = ivar_getTypeEncoding(ivar);
    ptrdiff_t offset = ivar_getOffset(ivar);
    if (type == nullptr) return;
    if (type[0] != 'B' && type[0] != 'c' && type[0] != 'C') return;
    uint8_t *bytes = (uint8_t *)(__bridge void *)battery;
    bytes[offset] = (uint8_t)value;
}

// 0x84d4: remembered requested state + an independent "known" out flag.
// NSNumber(NO) is present/known, not a cache miss. Cache raw state only when
// no setter request has been remembered and the byte read actually succeeds.
static BOOL HaogeSpringTwelveI27BatteryRequestedPercentage(UIView *battery, BOOL *known) {
    *known = NO;
    if (battery == nil) return NO;
    NSNumber *remembered = objc_getAssociatedObject(battery,
                                                   HaogeSpringTwelveI27BatteryRequestedKey);
    if (remembered != nil) {
        *known = YES;
        return [remembered boolValue];
    }
    BOOL raw = NO;
    if (!HaogeSpringTwelveI27BatteryReadRawShowsPercentage(battery, &raw)) return NO;
    objc_setAssociatedObject(battery, HaogeSpringTwelveI27BatteryRequestedKey,
                             [NSNumber numberWithBool:raw],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    *known = YES;
    return raw;
}

// Inlined associated depth reads in 0x7c30, 0x7e64, 0x82d4, 0x83d4, 0x8aa8.
static NSInteger HaogeSpringTwelveI27BatteryOverrideDepth(UIView *battery) {
    NSNumber *depth = battery == nil ? nil :
        objc_getAssociatedObject(battery, HaogeSpringTwelveI27BatteryOverrideDepthKey);
    return [depth integerValue];
}

static void HaogeSpringTwelveI27BatteryBeginPercentageOverride(UIView *battery) {
    NSInteger depth = HaogeSpringTwelveI27BatteryOverrideDepth(battery);
    // Model the arm64 ADD's wrapping bits without C++ signed overflow UB.
    NSInteger next = (NSInteger)((NSUInteger)depth + (NSUInteger)1);
    objc_setAssociatedObject(battery, HaogeSpringTwelveI27BatteryOverrideDepthKey,
                             [NSNumber numberWithInteger:next],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 0x8aa8: reduce depth, removing the association when the old depth <= 1.
static void HaogeSpringTwelveI27BatteryEndPercentageOverride(UIView *battery) {
    NSInteger depth = HaogeSpringTwelveI27BatteryOverrideDepth(battery);
    if (depth > 1) {
        objc_setAssociatedObject(battery, HaogeSpringTwelveI27BatteryOverrideDepthKey,
                                 [NSNumber numberWithInteger:depth - 1],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        objc_setAssociatedObject(battery, HaogeSpringTwelveI27BatteryOverrideDepthKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// 0x8884: refresh once while suppressing recursive refresh requests. Exception
// cleanup at 0x8a70–0x8a80 clears the guard and then rethrows (0x8a18); it does
// NOT swallow exceptions. @finally expresses that observed catch-all cleanup.
static void HaogeSpringTwelveI27BatteryRefreshWithoutPercentage(UIView *battery) {
    if (battery == nil) return;
    BOOL known = NO;
    BOOL requested = HaogeSpringTwelveI27BatteryRequestedPercentage(battery, &known);
    if (requested || !known) return;
    NSNumber *guard = objc_getAssociatedObject(battery,
                                              HaogeSpringTwelveI27BatteryRefreshGuardKey);
    if ([guard boolValue]) return;
    objc_setAssociatedObject(battery, HaogeSpringTwelveI27BatteryRefreshGuardKey,
                             [NSNumber numberWithBool:YES],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        if ([battery respondsToSelector:@selector(_updateBolt)]) {
            [battery _updateBolt];
        }
        if ([battery respondsToSelector:
                      @selector(_updateLightningBoltAndPercentagePosition)]) {
            [battery _updateLightningBoltAndPercentagePosition];
        }
        UIView *label = [battery percentageLabel];
        if (label != nil) {
            [label setHidden:YES];
            [label setAlpha:0.0];
        }
    } @finally {
        objc_setAssociatedObject(battery, HaogeSpringTwelveI27BatteryRefreshGuardKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// 0x7818. Only the remembered "known and OFF" state substitutes a color.
static UIColor *HaogeSpringTwelveI27BatteryTextColor(UIView *battery, SEL command) {
    BOOL known;
    BOOL requested = HaogeSpringTwelveI27BatteryRequestedPercentage(battery, &known);
    if (!requested && known && battery != nil) {
        UIColor *color = [battery bodyColor];
        // Do not combine these comparisons: the first is <= and the final
        // acceptance is >. This also preserves the two different NaN paths.
        if (color == nil || CGColorGetAlpha([color CGColor]) <= 0.01) {
            color = [battery pinColor];
        }
        UIColor *result;
        if (color != nil && CGColorGetAlpha([color CGColor]) > 0.01) {
            result = [color colorWithAlphaComponent:1.0];
        } else {
            result = [[UIColor labelColor]
                      resolvedColorWithTraitCollection:[battery traitCollection]];
        }
        if (result != nil) return result;
    }
    return HaogeSpringTwelveI27BatteryOriginalTextColor(battery, command);
}

// 0x7a20. Both branches pass YES to the ORIGINAL setter. The association, not
// that forced original argument, remembers the caller's real preference.
static void HaogeSpringTwelveI27BatterySetShowsPercentage(UIView *battery, SEL command,
                                         BOOL requested) {
    if (battery != nil) {
        objc_setAssociatedObject(battery, HaogeSpringTwelveI27BatteryRequestedKey,
                                 [NSNumber numberWithBool:requested],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (requested) {
        BOOL raw = NO;
        if (HaogeSpringTwelveI27BatteryReadRawShowsPercentage(battery, &raw) && raw) {
            HaogeSpringTwelveI27BatteryWriteRawShowsPercentage(battery, NO);
        }
        HaogeSpringTwelveI27BatteryOriginalSetShowsPercentage(battery, command, YES);
        [battery _updateBolt];
        [battery _updateLightningBoltAndPercentagePosition];
        UIView *label = [battery percentageLabel];
        if (label != nil) {
            [label setHidden:NO];
            [label setAlpha:1.0];
        }
        [battery setNeedsLayout];
    } else {
        HaogeSpringTwelveI27BatteryOriginalSetShowsPercentage(battery, command, YES);
        UIView *label = [battery percentageLabel];
        if (label != nil) {
            [label setHidden:YES];
            [label setAlpha:0.0];
        }
        HaogeSpringTwelveI27BatteryRefreshWithoutPercentage(battery);
    }
}

// Shared semantic body of 0x7c30 and 0x7e64, whose instruction sequences are
// identical except for the saved original IMP. No additional method is hooked.
static void HaogeSpringTwelveI27BatteryUpdateWithPercentageOverride(
    UIView *battery, SEL command, void (*original)(UIView *, SEL)) {
    BOOL known;
    BOOL requested = HaogeSpringTwelveI27BatteryRequestedPercentage(battery, &known);
    if (requested || !known) {
        original(battery, command);
        return;
    }
    BOOL savedRaw = YES;
    BOOL canRestoreRaw = HaogeSpringTwelveI27BatteryReadRawShowsPercentage(battery, &savedRaw);
    HaogeSpringTwelveI27BatteryBeginPercentageOverride(battery);
    if (canRestoreRaw) HaogeSpringTwelveI27BatteryWriteRawShowsPercentage(battery, NO);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    original(battery, command);
    [CATransaction commit];
    if (canRestoreRaw) HaogeSpringTwelveI27BatteryWriteRawShowsPercentage(battery, savedRaw);
    HaogeSpringTwelveI27BatteryEndPercentageOverride(battery);
    UIView *label = [battery percentageLabel];
    if (label != nil) {
        [label setHidden:YES];
        [label setAlpha:0.0];
    }
    // Intentionally NO @finally here. The original unwind paths only release
    // ARC objects; on exceptions they do not commit/restore/decrement/hide.
}

// 0x7c30.
static void HaogeSpringTwelveI27BatteryUpdateBolt(UIView *battery, SEL command) {
    HaogeSpringTwelveI27BatteryUpdateWithPercentageOverride(battery, command,
                                           HaogeSpringTwelveI27BatteryOriginalUpdateBolt);
}

// 0x7e64.
static void HaogeSpringTwelveI27BatteryUpdateLightningBoltAndPercentagePosition(
    UIView *battery, SEL command) {
    HaogeSpringTwelveI27BatteryUpdateWithPercentageOverride(battery, command,
                                           HaogeSpringTwelveI27BatteryOriginalUpdatePosition);
}

// 0x8098: original layout always runs first, including for unknown state.
static void HaogeSpringTwelveI27BatteryLayoutSubviews(UIView *battery, SEL command) {
    HaogeSpringTwelveI27BatteryOriginalLayoutSubviews(battery, command);
    BOOL known;
    BOOL requested = HaogeSpringTwelveI27BatteryRequestedPercentage(battery, &known);
    if (!known) return;
    if (requested) {
        UIView *label = [battery percentageLabel];
        if (label != nil) {
            [label setHidden:NO];
            [label setAlpha:1.0];
        }
        return;
    }
    BOOL raw = NO;
    if (HaogeSpringTwelveI27BatteryReadRawShowsPercentage(battery, &raw) && !raw) {
        // Must go through the hook, not the saved IMP. This re-remembers NO
        // while forcing the original setter's internal value back to YES.
        [battery setShowsPercentage:NO];
        return;
    }
    UIView *label = [battery percentageLabel];
    if (label != nil) {
        [label setHidden:YES];
        [label setAlpha:0.0];
    }
    HaogeSpringTwelveI27BatteryRefreshWithoutPercentage(battery);
}

// 0x81e4: no extra trait comparison and no additional setNeedsLayout call.
static void HaogeSpringTwelveI27BatteryTraitCollectionDidChange(
    UIView *battery, SEL command, UITraitCollection *previousTraits) {
    HaogeSpringTwelveI27BatteryOriginalTraitCollectionDidChange(battery, command, previousTraits);
    BOOL known = NO;
    BOOL requested = HaogeSpringTwelveI27BatteryRequestedPercentage(battery, &known);
    if (!requested && known) {
        UIView *label = [battery percentageLabel];
        if (label != nil) {
            [label setHidden:YES];
            [label setAlpha:0.0];
        }
        HaogeSpringTwelveI27BatteryRefreshWithoutPercentage(battery);
    }
}

// 0x82d4 / 0x83d4: override only at positive depth AND known requested OFF.
// Outside that scope return the original result, not the remembered preference.
static BOOL HaogeSpringTwelveI27BatteryShowsPercentage(UIView *battery, SEL command) {
    if (HaogeSpringTwelveI27BatteryOverrideDepth(battery) >= 1) {
        BOOL known;
        BOOL requested = HaogeSpringTwelveI27BatteryRequestedPercentage(battery, &known);
        if (!requested && known) return NO;
    }
    return HaogeSpringTwelveI27BatteryOriginalShowsPercentage(battery, command);
}

static BOOL HaogeSpringTwelveI27BatteryCurrentlyShowsPercentage(UIView *battery, SEL command) {
    if (HaogeSpringTwelveI27BatteryOverrideDepth(battery) >= 1) {
        BOOL known;
        BOOL requested = HaogeSpringTwelveI27BatteryRequestedPercentage(battery, &known);
        if (!requested && known) return NO;
    }
    return HaogeSpringTwelveI27BatteryOriginalCurrentlyShowsPercentage(battery, command);
}

// Extracted battery prefix of startup block 0x6a58: 0x6a80–0x6c4c.
// No iOS-major-version check belongs to this group. The version-16 check
// beginning at 0x6c5c belongs to the following, separate signal module.
BOOL HaogeSpringTwelveI27InstallBatteryHooks(void) {
    @autoreleasepool {
        if (objc_getClass("UIApplication") == Nil) return NO;
        if (HaogeSpringTwelveI27BatteryInstalled) return YES;
        Class cls = objc_getClass("_UIBatteryView");
        if (cls == Nil) return NO;
        SEL setShows = @selector(setShowsPercentage:);
        SEL updateBolt = @selector(_updateBolt);
        SEL updatePosition = @selector(_updateLightningBoltAndPercentagePosition);
        SEL textColor = sel_registerName("_batteryTextColor");
        if (class_getInstanceMethod(cls, setShows) == nullptr) return NO;
        if (class_getInstanceMethod(cls, updateBolt) == nullptr) return NO;
        if (class_getInstanceMethod(cls, updatePosition) == nullptr) return NO;
        if (class_getInstanceMethod(cls, textColor) == nullptr) return NO;

        MSHookMessageEx(cls, textColor, (IMP)HaogeSpringTwelveI27BatteryTextColor,
                       (IMP *)&HaogeSpringTwelveI27BatteryOriginalTextColor);
        MSHookMessageEx(cls, setShows, (IMP)HaogeSpringTwelveI27BatterySetShowsPercentage,
                       (IMP *)&HaogeSpringTwelveI27BatteryOriginalSetShowsPercentage);
        MSHookMessageEx(cls, updateBolt, (IMP)HaogeSpringTwelveI27BatteryUpdateBolt,
                       (IMP *)&HaogeSpringTwelveI27BatteryOriginalUpdateBolt);
        MSHookMessageEx(cls, updatePosition,
                       (IMP)HaogeSpringTwelveI27BatteryUpdateLightningBoltAndPercentagePosition,
                       (IMP *)&HaogeSpringTwelveI27BatteryOriginalUpdatePosition);
        MSHookMessageEx(cls, @selector(layoutSubviews),
                       (IMP)HaogeSpringTwelveI27BatteryLayoutSubviews,
                       (IMP *)&HaogeSpringTwelveI27BatteryOriginalLayoutSubviews);
        MSHookMessageEx(cls, @selector(traitCollectionDidChange:),
                       (IMP)HaogeSpringTwelveI27BatteryTraitCollectionDidChange,
                       (IMP *)&HaogeSpringTwelveI27BatteryOriginalTraitCollectionDidChange);

        SEL shows = sel_registerName("showsPercentage");
        if (class_getInstanceMethod(cls, shows) != nullptr) {
            MSHookMessageEx(cls, shows, (IMP)HaogeSpringTwelveI27BatteryShowsPercentage,
                           (IMP *)&HaogeSpringTwelveI27BatteryOriginalShowsPercentage);
        }
        SEL currentlyShows = sel_registerName("_currentlyShowsPercentage");
        if (class_getInstanceMethod(cls, currentlyShows) != nullptr) {
            MSHookMessageEx(cls, currentlyShows,
                           (IMP)HaogeSpringTwelveI27BatteryCurrentlyShowsPercentage,
                           (IMP *)&HaogeSpringTwelveI27BatteryOriginalCurrentlyShowsPercentage);
        }
        HaogeSpringTwelveI27BatteryInstalled = YES;
        return YES;
    }
}
