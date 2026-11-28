// Static reconstruction from the supplied arm64/arm64e Mach-O slices.
// See evidence/DRAWING-RECONSTRUCTION.md and evidence/extract-drawing.py.
// Compile as Objective-C++ with ARC and UIKit/CoreGraphics. No private API.
#import "HaogeSpringTwelveI27Drawing.h"
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdint.h>
#include <limits.h>

// Hexadecimal binary64 literals preserve the exact constants, not rounded
// redraws. Rows: start.xy, first control.xy, second control.xy, end.xy, width.
static const double HaogeSpringTwelveI27WiFiArcs[2][9] = {
    { 0x1.599999999999ap+2, 0x1.fcccccccccccdp+3, 0x1.9666666666666p+3, 0x1.1cccccccccccdp+3, 0x1.6e66666666666p+4, 0x1.5666666666666p+2, 0x1.0c00000000000p+5, 0x1.5666666666666p+2, 0x1.299999999999ap+3 },
    { 0x1.0bae147ae147bp+4, 0x1.bd9999999999ap+4, 0x1.54ccccccccccdp+4, 0x1.8cccccccccccdp+4, 0x1.a99999999999ap+4, 0x1.6666666666666p+4, 0x1.0c00000000000p+5, 0x1.6666666666666p+4, 0x1.2000000000000p+3 }
};
static const double HaogeSpringTwelveI27WiFiDotMove[2] = {
    0x1.0c00000000000p+5, 0x1.1d33333333333p+5
};
// Four cubic curves, six arguments per CGContextAddCurveToPoint.
static const double HaogeSpringTwelveI27WiFiDotCurves[4][6] = {
    { 0x1.c89eb851eb852p+4, 0x1.1d33333333333p+5, 0x1.80ccccccccccdp+4, 0x1.32dc28f5c28f6p+5, 0x1.80ccccccccccdp+4, 0x1.4accccccccccdp+5 },
    { 0x1.80ccccccccccdp+4, 0x1.5333333333333p+5, 0x1.d68f5c28f5c29p+4, 0x1.8933333333333p+5, 0x1.0c00000000000p+5, 0x1.8d33333333333p+5 },
    { 0x1.2cb851eb851ecp+5, 0x1.8933333333333p+5, 0x1.579999999999ap+5, 0x1.5333333333333p+5, 0x1.579999999999ap+5, 0x1.4accccccccccdp+5 },
    { 0x1.579999999999ap+5, 0x1.32dc28f5c28f6p+5, 0x1.33b0a3d70a3d7p+5, 0x1.1d33333333333p+5, 0x1.0c00000000000p+5, 0x1.1d33333333333p+5 }
};
// Rows are CGRect x,y,width,height, in the original 72 x 54 design space.
// In particular, x=-2.95 and rightmost x+width=74.95 are NOT corrected.
static const double HaogeSpringTwelveI27SingleSIMRects[4][4] = {
    { -0x1.799999999999ap+1, 0x1.d000000000000p+4, 0x1.999999999999ap+3, 0x1.6000000000000p+4 },
    { 0x1.2c00000000000p+4, 0x1.6000000000000p+4, 0x1.999999999999ap+3, 0x1.d000000000000p+4 },
    { 0x1.439999999999ap+5, 0x1.a000000000000p+3, 0x1.999999999999ap+3, 0x1.3000000000000p+5 },
    { 0x1.f133333333333p+5, 0x1.4000000000000p+2, 0x1.999999999999ap+3, 0x1.7000000000000p+5 }
};
static const double HaogeSpringTwelveI27CellularRects[4][4] = {
    { -0x1.799999999999ap+1, 0x1.04ccccccccccdp+4, 0x1.999999999999ap+3, 0x1.14ccccccccccdp+4 },
    { 0x1.2c00000000000p+4, 0x1.7666666666666p+3, 0x1.999999999999ap+3, 0x1.5e66666666666p+4 },
    { 0x1.439999999999ap+5, 0x1.799999999999ap+2, 0x1.999999999999ap+3, 0x1.bb33333333333p+4 },
    { 0x1.f133333333333p+5, 0x1.6666666666666p-1, 0x1.999999999999ap+3, 0x1.0733333333333p+5 }
};
static const double HaogeSpringTwelveI27Cellular2Rects[4][4] = {
    { -0x1.799999999999ap+1, 0x1.3666666666666p+5, 0x1.999999999999ap+3, 0x1.d666666666666p+3 },
    { 0x1.2c00000000000p+4, 0x1.3666666666666p+5, 0x1.999999999999ap+3, 0x1.d666666666666p+3 },
    { 0x1.439999999999ap+5, 0x1.3666666666666p+5, 0x1.999999999999ap+3, 0x1.d666666666666p+3 },
    { 0x1.f133333333333p+5, 0x1.3666666666666p+5, 0x1.999999999999ap+3, 0x1.d666666666666p+3 }
};

static BOOL HaogeSpringTwelveI27ValidKind(NSInteger kind) {
    return kind >= HaogeSpringTwelveI27GlyphKindWiFi && kind <= HaogeSpringTwelveI27GlyphKindCellular2;
}

static CGFloat HaogeSpringTwelveI27Alpha(CGFloat alpha) {
    return fmax(fmin(alpha, 1.0), 0.0);
}

static void HaogeSpringTwelveI27ConfigureContext(CGContextRef context) {
    CGContextSetShouldAntialias(context, true);
    CGContextSetAllowsAntialiasing(context, true);
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh); // raw 3
}

// arm64 0xba30: draw TWO cubics, reflecting in x=33.5. Retain the original
// subtract-then-add order: (center - x) + center, not a resampled arc.
static void HaogeSpringTwelveI27StrokeWiFiArc(CGContextRef context,
                               const double p[9], CGFloat alpha) {
    CGContextSaveGState(context);
    HaogeSpringTwelveI27ConfigureContext(context);
    CGContextSetRGBStrokeColor(context, 1.0, 1.0, 1.0, HaogeSpringTwelveI27Alpha(alpha));
    CGContextSetLineWidth(context, p[8]);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, p[0], p[1]);
    CGContextAddCurveToPoint(context, p[2], p[3], p[4], p[5], p[6], p[7]);
    const double center = 0x1.0c00000000000p+5;
    CGContextAddCurveToPoint(context,
                            (center - p[4]) + center, p[5],
                            (center - p[2]) + center, p[3],
                            (center - p[0]) + center, p[1]);
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
}

// arm64 0xb298...0xb4b0: outer arc, inner arc, then the filled Bezier dot.
static void HaogeSpringTwelveI27DrawWiFi(CGContextRef context, NSInteger bars) {
    const CGFloat inactive = 0x1.999999999999ap-2; // 0xf038: 0.4
    HaogeSpringTwelveI27StrokeWiFiArc(context, HaogeSpringTwelveI27WiFiArcs[0], bars == 3 ? 1.0 : inactive);
    HaogeSpringTwelveI27StrokeWiFiArc(context, HaogeSpringTwelveI27WiFiArcs[1], bars > 1 ? 1.0 : inactive);
    CGContextSaveGState(context);
    HaogeSpringTwelveI27ConfigureContext(context);
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, bars == 0 ? inactive : 1.0);
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, HaogeSpringTwelveI27WiFiDotMove[0], HaogeSpringTwelveI27WiFiDotMove[1]);
    for (NSInteger i = 0; i < 4; ++i) {
        const double *p = HaogeSpringTwelveI27WiFiDotCurves[i];
        CGContextAddCurveToPoint(context, p[0], p[1], p[2], p[3], p[4], p[5]);
    }
    CGContextClosePath(context);
    CGContextFillPath(context);
    CGContextRestoreGState(context);
}

// arm64 0xd200. CGPath clamps the radius against the actual rectangle itself.
static void HaogeSpringTwelveI27FillSignalRect(CGContextRef context, CGRect rect, CGFloat alpha) {
    if (CGRectIsEmpty(rect)) return;
    const CGFloat radius = 0x1.999999999999ap+2; // 0xf138: 6.4
    CGPathRef path = CGPathCreateWithRoundedRect(rect, radius, radius, NULL);
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, HaogeSpringTwelveI27Alpha(alpha));
    CGContextAddPath(context, path);
    CGContextFillPath(context);
    CGPathRelease(path);
}

static void HaogeSpringTwelveI27DrawCellular(CGContextRef context, NSInteger kind, NSInteger bars) {
    const double (*rects)[4] = kind == HaogeSpringTwelveI27GlyphKindSingleSIM
        ? HaogeSpringTwelveI27SingleSIMRects : kind == HaogeSpringTwelveI27GlyphKindCellular
        ? HaogeSpringTwelveI27CellularRects : HaogeSpringTwelveI27Cellular2Rects;
    const CGFloat inactive = 0x1.0a3d70a3d70a4p-2; // 0xf0e0: 0.26
    for (NSInteger i = 0; i < 4; ++i) {
        const double *r = rects[i];
        HaogeSpringTwelveI27FillSignalRect(context, CGRectMake(r[0], r[1], r[2], r[3]),
                           bars > i ? 1.0 : inactive);
    }
}

NSInteger HaogeSpringTwelveI27ClampBars(NSInteger kind, NSInteger bars) {
    if (!HaogeSpringTwelveI27ValidKind(kind)) return NSNotFound;
    const NSInteger maximum = kind == HaogeSpringTwelveI27GlyphKindWiFi ? 3 : 4;
    return bars < 0 ? 0 : bars > maximum ? maximum : bars;
}

CGSize HaogeSpringTwelveI27GlyphSize(NSInteger kind, CGSize nativeBoundsSize) {
    const double epsilon = 0x1.999999999999ap-4; // 0xf020: 0.1
    if (!HaogeSpringTwelveI27ValidKind(kind) || !isfinite(nativeBoundsSize.width) ||
        !isfinite(nativeBoundsSize.height) || nativeBoundsSize.width <= epsilon ||
        nativeBoundsSize.height <= epsilon) return CGSizeZero;
    const double enlargement = 0x1.147ae147ae148p+0; // 0xf028: 1.08
    const double aspect = kind == HaogeSpringTwelveI27GlyphKindWiFi
        ? 0x1.570a3d70a3d71p+0  // 0xf030: 1.34, NOT 67/50 recomputed
        : 0x1.5555555555555p+0; // immediate: binary64 4/3
    CGSize result = CGSizeMake(nativeBoundsSize.width * enlargement,
                               nativeBoundsSize.height * enlargement);
    if (result.width / result.height > aspect) {
        result.width = result.height * aspect;
    } else {
        result.height = result.width / aspect;
    }
    return result;
}

void HaogeSpringTwelveI27CenterGlyphView(UIView *host, UIView *glyphView, CGSize size) {
    if (!glyphView) return;
    const CGRect hostBounds = host.bounds;
    glyphView.transform = CGAffineTransformIdentity;
    const double epsilon = 0x1.999999999999ap-4;
    const CGSize target = fmin(size.width, size.height) <= epsilon
        ? hostBounds.size : size;
    glyphView.bounds = (CGRect){ CGPointZero, target };
    glyphView.center = CGPointMake(CGRectGetMidX(hostBounds), CGRectGetMidY(hostBounds));
    [host bringSubviewToFront:glyphView];
}

UIImage *HaogeSpringTwelveI27MakeGlyph(NSInteger kind, NSInteger bars, CGSize drawingSize) {
    const double epsilon = 0x1.999999999999ap-4;
    if (!HaogeSpringTwelveI27ValidKind(kind) || bars < 0 ||
        bars > (kind == HaogeSpringTwelveI27GlyphKindWiFi ? 3 : 4) ||
        !isfinite(drawingSize.width) || !isfinite(drawingSize.height) ||
        drawingSize.width <= epsilon || drawingSize.height <= epsilon) return nil;

    CGFloat scale = [UIScreen mainScreen].scale;
    if (!isfinite(scale)) return nil; // safety outside recovered normal domain
    if (scale < 1.0) scale = 2.0; // exactly <1, not <=1 or max(2,scale)
    const BOOL wifi = kind == HaogeSpringTwelveI27GlyphKindWiFi;
    const double widthPixels = (drawingSize.width + (wifi ? 1.5 : 2.5)) * scale;
    const double heightPixels = (drawingSize.height + 2.0) * scale;
    // Avoid C llround overflow for pathological input; original FCVTAS saturates.
    if (!isfinite(widthPixels) || !isfinite(heightPixels) ||
        widthPixels >= 0x1p63 || heightPixels >= 0x1p63) return nil;
    const int64_t roundedWidth = llround(widthPixels);
    const int64_t roundedHeight = llround(heightPixels);
    const int64_t pixelWidth = roundedWidth > 1 ? roundedWidth : 1;
    const int64_t pixelHeight = roundedHeight > 1 ? roundedHeight : 1;

    // Original caches remember only the most recent physical pixel width/height
    // per family and bars. Deliberately do NOT add raw point size or scale keys.
    static UIImage *HaogeSpringTwelveI27Images[4][5];
    static int64_t HaogeSpringTwelveI27PixelWidths[4][5];
    static int64_t HaogeSpringTwelveI27PixelHeights[4][5];
    UIImage *cached = HaogeSpringTwelveI27Images[kind][bars];
    if (cached && HaogeSpringTwelveI27PixelWidths[kind][bars] == pixelWidth &&
        HaogeSpringTwelveI27PixelHeights[kind][bars] == pixelHeight) return cached;

    const CGSize imageSize = CGSizeMake((double)pixelWidth / scale,
                                       (double)pixelHeight / scale);
    UIGraphicsBeginImageContextWithOptions(imageSize, NO, scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        UIGraphicsEndImageContext();
        return nil;
    }
    HaogeSpringTwelveI27ConfigureContext(context);
    CGContextTranslateCTM(context, wifi ? 0.75 : 1.25, 1.0);
    CGContextScaleCTM(context, drawingSize.width / (wifi ? 67.0 : 72.0),
                     drawingSize.height / (wifi ? 50.0 : 54.0));
    if (wifi) HaogeSpringTwelveI27DrawWiFi(context, bars);
    else HaogeSpringTwelveI27DrawCellular(context, kind, bars);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!image) return nil;
    image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    HaogeSpringTwelveI27Images[kind][bars] = image;
    HaogeSpringTwelveI27PixelWidths[kind][bars] = pixelWidth;
    HaogeSpringTwelveI27PixelHeights[kind][bars] = pixelHeight;
    return image;
}
