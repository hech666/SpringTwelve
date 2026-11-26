#import <UIKit/UIKit.h>
#import "HaogeSpringTwelveSwitches.h"

static BOOL HaogeSpringTwelveTodayOff(void) { return HaogeSpringTwelveOn(@"disableTodayView"); }
static BOOL HaogeSpringTwelveLibraryOff(void) { return HaogeSpringTwelveOn(@"disableAppLibrary"); }

@protocol HaogeSpringTwelveTrailingPage <NSObject>
- (id)trailingCustomViewController;
@end

%group HaogeSpringTwelveSpringBoardPages
%hook SBRootFolderControllerConfiguration
- (NSUInteger)ignoresOverscrollOnFirstPageOrientations {
    return HaogeSpringTwelveTodayOff() ? 0 : %orig;
}
- (void)setIgnoresOverscrollOnFirstPageOrientations:(NSUInteger)mask {
    %orig(HaogeSpringTwelveTodayOff() ? 0 : mask);
}
- (NSUInteger)ignoresOverscrollOnLastPageOrientations {
    return HaogeSpringTwelveLibraryOff() ? 0 : %orig;
}
- (void)setIgnoresOverscrollOnLastPageOrientations:(NSUInteger)mask {
    %orig(HaogeSpringTwelveLibraryOff() ? 0 : mask);
}
%end

%hook SBRootFolderView
- (NSUInteger)_trailingCustomPageCount {
    if (HaogeSpringTwelveLibraryOff()) {
        id<HaogeSpringTwelveTrailingPage> folder = (id)self;
        Class library = NSClassFromString(@"SBHLibraryOverscrollViewController");
        if (library && [folder respondsToSelector:@selector(trailingCustomViewController)] &&
            [[folder trailingCustomViewController] isKindOfClass:library]) return 0;
    }
    return %orig;
}
%end

%hook SBIconController
- (BOOL)isAppLibraryAllowed {
    return HaogeSpringTwelveLibraryOff() ? NO : %orig;
}
- (BOOL)isAppLibrarySupported {
    return HaogeSpringTwelveLibraryOff() ? NO : %orig;
}
- (void)iconManager:(id)manager rootFolderController:(id)folder didOverscrollOnLastPageByAmount:(double)amount {
    if (!HaogeSpringTwelveLibraryOff()) %orig;
}
- (void)iconManager:(id)manager rootFolderController:(id)folder didEndOverscrollOnLastPageWithVelocity:(double)velocity translation:(double)translation {
    if (!HaogeSpringTwelveLibraryOff()) %orig;
}
- (BOOL)_shouldTodayViewController:(id)controller receiveTouch:(id)touch {
    return HaogeSpringTwelveTodayOff() ? NO : %orig;
}
- (void)activateTodayViewWithCompletion:(dispatch_block_t)completion {
    if (HaogeSpringTwelveTodayOff()) {
        if (completion) completion();
        return;
    }
    %orig;
}
- (void)presentTodayOverlayForIconManager:(id)manager {
    if (!HaogeSpringTwelveTodayOff()) %orig;
}
%end

%hook SBRootFolderController
- (BOOL)isTodayViewPageHidden {
    return HaogeSpringTwelveTodayOff() ? YES : %orig;
}
- (void)setTodayViewPageHidden:(BOOL)hidden {
    %orig(HaogeSpringTwelveTodayOff() ? YES : hidden);
}
%end

%hook SBHIconManager
- (void)presentTodayOverlayForIconDragManager:(id)manager {
    if (!HaogeSpringTwelveTodayOff()) %orig;
}
- (void)presentTodayOverlay {
    if (!HaogeSpringTwelveTodayOff()) %orig;
}
%end

%hook SBMainDisplayPolicyAggregator
- (BOOL)_allowsCapabilityTodayViewWithExplanation:(id __autoreleasing *)explanation {
    return HaogeSpringTwelveTodayOff() ? NO : %orig;
}
- (BOOL)_allowsCapabilityLockScreenTodayViewWithExplanation:(id __autoreleasing *)explanation {
    return HaogeSpringTwelveOn(@"disableLockScreenTodayView") ? NO : %orig;
}
%end

%hook SBSearchGesture
- (BOOL)searchScrollViewShouldRecognize:(id)scrollView {
    return HaogeSpringTwelveOn(@"disableHomePullDownSearch") ? NO : %orig;
}
- (void)revealAnimated:(BOOL)animated {
    if (!HaogeSpringTwelveOn(@"disableHomePullDownSearch")) %orig;
}
%end

// Original 0x23f9c checks each registered target, not swipe direction.
static BOOL HaogeSpringTwelveHasCoverSheetTarget(id pan) {
    Class coverSheet = NSClassFromString(@"CSCoverSheetViewController");
    if (!coverSheet || !pan) return NO;
    @try {
        id entries = [pan valueForKey:@"_targets"];
        if (![entries respondsToSelector:@selector(countByEnumeratingWithState:objects:count:)]) return NO;
        for (id entry in entries) {
            if ([entry respondsToSelector:@selector(target)] && [[entry target] isKindOfClass:coverSheet]) return YES;
        }
    } @catch (NSException *exception) {
        // Private UIKit storage changed: let SpringBoard handle the pan.
        return NO;
    }
    return NO;
}

%hook CSScrollView
- (void)handlePan:(id)pan {
    if (HaogeSpringTwelveOn(@"disableLockScreenCamera") && HaogeSpringTwelveHasCoverSheetTarget(pan)) return;
    %orig;
}
%end

%end // HaogeSpringTwelveSpringBoardPages

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        NSArray<NSString *> *classes = @[@"SBRootFolderControllerConfiguration", @"SBRootFolderView",
            @"SBIconController", @"SBRootFolderController", @"SBHIconManager",
            @"SBMainDisplayPolicyAggregator", @"SBSearchGesture", @"CSScrollView"];
        for (NSString *name in classes) if (!NSClassFromString(name)) return;
        %init(HaogeSpringTwelveSpringBoardPages);
    }
}
