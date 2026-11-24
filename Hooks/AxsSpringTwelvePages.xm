#import <UIKit/UIKit.h>
#import "AxsSpringTwelveSwitches.h"

static BOOL AxsSpringTwelveTodayOff(void) { return AxsSpringTwelveOn(@"disableTodayView"); }
static BOOL AxsSpringTwelveLibraryOff(void) { return AxsSpringTwelveOn(@"disableAppLibrary"); }

@protocol AxsSpringTwelveTrailingPage <NSObject>
- (id)trailingCustomViewController;
@end

%hook SBRootFolderControllerConfiguration
- (NSUInteger)ignoresOverscrollOnFirstPageOrientations {
    return AxsSpringTwelveTodayOff() ? 0 : %orig;
}
- (void)setIgnoresOverscrollOnFirstPageOrientations:(NSUInteger)mask {
    %orig(AxsSpringTwelveTodayOff() ? 0 : mask);
}
- (NSUInteger)ignoresOverscrollOnLastPageOrientations {
    return AxsSpringTwelveLibraryOff() ? 0 : %orig;
}
- (void)setIgnoresOverscrollOnLastPageOrientations:(NSUInteger)mask {
    %orig(AxsSpringTwelveLibraryOff() ? 0 : mask);
}
%end

%hook SBRootFolderView
- (NSUInteger)_trailingCustomPageCount {
    if (AxsSpringTwelveLibraryOff()) {
        id<AxsSpringTwelveTrailingPage> folder = (id)self;
        Class library = NSClassFromString(@"SBHLibraryOverscrollViewController");
        if (library && [folder respondsToSelector:@selector(trailingCustomViewController)] &&
            [[folder trailingCustomViewController] isKindOfClass:library]) return 0;
    }
    return %orig;
}
%end

%hook SBIconController
- (BOOL)isAppLibraryAllowed {
    return AxsSpringTwelveLibraryOff() ? NO : %orig;
}
- (BOOL)isAppLibrarySupported {
    return AxsSpringTwelveLibraryOff() ? NO : %orig;
}
- (void)iconManager:(id)manager rootFolderController:(id)folder didOverscrollOnLastPageByAmount:(double)amount {
    if (!AxsSpringTwelveLibraryOff()) %orig;
}
- (void)iconManager:(id)manager rootFolderController:(id)folder didEndOverscrollOnLastPageWithVelocity:(double)velocity translation:(double)translation {
    if (!AxsSpringTwelveLibraryOff()) %orig;
}
- (BOOL)_shouldTodayViewController:(id)controller receiveTouch:(id)touch {
    return AxsSpringTwelveTodayOff() ? NO : %orig;
}
- (void)activateTodayViewWithCompletion:(dispatch_block_t)completion {
    if (AxsSpringTwelveTodayOff()) {
        if (completion) completion();
        return;
    }
    %orig;
}
- (void)presentTodayOverlayForIconManager:(id)manager {
    if (!AxsSpringTwelveTodayOff()) %orig;
}
%end

%hook SBRootFolderController
- (BOOL)isTodayViewPageHidden {
    return AxsSpringTwelveTodayOff() ? YES : %orig;
}
- (void)setTodayViewPageHidden:(BOOL)hidden {
    %orig(AxsSpringTwelveTodayOff() ? YES : hidden);
}
%end

%hook SBHIconManager
- (void)presentTodayOverlayForIconDragManager:(id)manager {
    if (!AxsSpringTwelveTodayOff()) %orig;
}
- (void)presentTodayOverlay {
    if (!AxsSpringTwelveTodayOff()) %orig;
}
%end

%hook SBMainDisplayPolicyAggregator
- (BOOL)_allowsCapabilityTodayViewWithExplanation:(id __autoreleasing *)explanation {
    return AxsSpringTwelveTodayOff() ? NO : %orig;
}
- (BOOL)_allowsCapabilityLockScreenTodayViewWithExplanation:(id __autoreleasing *)explanation {
    return AxsSpringTwelveOn(@"disableLockScreenTodayView") ? NO : %orig;
}
%end

%hook SBSearchGesture
- (BOOL)searchScrollViewShouldRecognize:(id)scrollView {
    return AxsSpringTwelveOn(@"disableHomePullDownSearch") ? NO : %orig;
}
- (void)revealAnimated:(BOOL)animated {
    if (!AxsSpringTwelveOn(@"disableHomePullDownSearch")) %orig;
}
%end

// Original 0x23f9c checks each registered target, not swipe direction.
static BOOL AxsSpringTwelveHasCoverSheetTarget(id pan) {
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
    if (AxsSpringTwelveOn(@"disableLockScreenCamera") && AxsSpringTwelveHasCoverSheetTarget(pan)) return;
    %orig;
}
%end
