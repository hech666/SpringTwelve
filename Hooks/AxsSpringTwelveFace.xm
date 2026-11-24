#import "AxsSpringTwelveSwitches.h"
#import <objc/message.h>
static id stObj(id o, NSString *name) { SEL s=NSSelectorFromString(name); return [o respondsToSelector:s]?((id(*)(id,SEL))objc_msgSend)(o,s):nil; }
static BOOL stBool(id o, NSString *name, BOOL fallback) { SEL s=NSSelectorFromString(name); return [o respondsToSelector:s]?((BOOL(*)(id,SEL))objc_msgSend)(o,s):fallback; }
static BOOL stDismissPending, stRetryPending; // accessed on main queue only
%hook SBDashBoardLockScreenEnvironment
- (BOOL)biometricUnlockBehavior:(id)behavior requestsUnlock:(BOOL)request withFeedback:(BOOL)feedback {
    BOOL result=%orig;
    if (result && AxsSpringTwelveOn(@"autoDismissFaceID")) dispatch_async(dispatch_get_main_queue(), ^{
        if (stDismissPending) return;
        stDismissPending=YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,220*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
            stDismissPending=NO;
            if (!AxsSpringTwelveOn(@"autoDismissFaceID")) return;
            id lock=stObj(NSClassFromString(@"SBLockScreenManager"),@"sharedInstance");
            if (stBool(lock,@"isUILocked",YES)) return;
            Class c=NSClassFromString(@"SBCoverSheetPresentationManager");
            id m=stObj(c,@"sharedInstanceIfExists") ?: stObj(c,@"sharedInstance");
            if (!stBool(m,@"isPresented",NO) || stBool(m,@"isTransitioning",YES)) return;
            SEL s=NSSelectorFromString(@"setCoverSheetPresented:animated:withCompletion:");
            if ([m respondsToSelector:s]) ((void(*)(id,SEL,BOOL,BOOL,id))objc_msgSend)(m,s,NO,YES,nil);
        });
    });
    return result;
}
%end
%hook SBUIBiometricResource
- (void)biometricKitInterface:(id)interface handleEvent:(NSUInteger)event {
    %orig;
    if (event!=10 || !AxsSpringTwelveOn(@"autoDismissFaceID")) return;
    id resource=self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (stRetryPending) return;
        stRetryPending=YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
            stRetryPending=NO;
            SEL state=NSSelectorFromString(@"biometricLockoutState"), retry=NSSelectorFromString(@"resumeMatchingAdvisory:");
            if (!AxsSpringTwelveOn(@"autoDismissFaceID") || ![resource respondsToSelector:state] || ((NSInteger(*)(id,SEL))objc_msgSend)(resource,state)!=0 || !stBool(resource,@"isMatchingAllowed",NO)) return;
            if ([resource respondsToSelector:retry]) ((void(*)(id,SEL,NSUInteger))objc_msgSend)(resource,retry,0);
        });
    });
}
%end
