#ifndef HaogeSpringTwelveI27_DRAWING_H
#define HaogeSpringTwelveI27_DRAWING_H

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Public reconstruction IDs, NOT the runtime class classifier's 0/1/2/3 IDs.
typedef NS_ENUM(NSInteger, HaogeSpringTwelveI27GlyphKind) {
    HaogeSpringTwelveI27GlyphKindWiFi = 0,        // arm64 0xb110; bars 0...3
    HaogeSpringTwelveI27GlyphKindSingleSIM = 1,   // arm64 0xc474, "SingleSIM"; bars 0...4
    HaogeSpringTwelveI27GlyphKindCellular = 2,    // "Cellular": upper dual-SIM shape
    HaogeSpringTwelveI27GlyphKindCellular2 = 3    // "Cellular2": lower dual-SIM shape
};

// Fit an unpadded drawing size to native bounds: enlarge by 1.08, then
// aspect-fit at 1.34 (WiFi) or the exact binary64 4/3 constant (cellular).
// Invalid kind or bounds <= 0.1 return CGSizeZero. This is NOT UIImage.size.
FOUNDATION_EXPORT CGSize HaogeSpringTwelveI27GlyphSize(NSInteger kind, CGSize nativeBoundsSize);

// True original factories take width/height, so a size argument is required.
// Invalid kind, bars outside the range above, or dimensions <= 0.1 return nil.
// Does not silently clamp bars. Uses mainScreen.scale (<1 => 2), transparent
// bitmap, pixel-rounded padding, and UIImageRenderingModeAlwaysTemplate.
// Returned image.size includes padding: WiFi +1.5 x +2, cellular +2.5 x +2,
// rounded to physical pixels before division by scale. Call on main thread.
FOUNDATION_EXPORT UIImage * _Nullable HaogeSpringTwelveI27MakeGlyph(NSInteger kind,
                                                    NSInteger bars,
                                                    CGSize drawingSize);

// Pure numeric part of arm64 0xad5c: max(0,min(maximum,bars)).
// Returns NSNotFound for invalid kind. Runtime selector/ivar lookup is external.
FOUNDATION_EXPORT NSInteger HaogeSpringTwelveI27ClampBars(NSInteger kind, NSInteger bars);

// arm64 0xb8cc only: reset transform, set zero-origin bounds, center in host
// bounds, and bring an existing subview forward. No view creation or hiding.
// drawing/image size <=0.1 in either dimension falls back to host.bounds.size.
FOUNDATION_EXPORT void HaogeSpringTwelveI27CenterGlyphView(UIView *host,
                                          UIView * _Nullable glyphView,
                                          CGSize size);

NS_ASSUME_NONNULL_END
#endif
