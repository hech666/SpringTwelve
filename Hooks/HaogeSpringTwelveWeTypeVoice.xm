// WeType-only adaptation of the user-supplied WTVRBGLauncher 1.1 binary.
// Original package credits Lessica. See docs/wetype-voice-no-jump.md.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <string.h>
#import "HaogeSpringTwelveSwitches.h"
#import "HaogeSpringTwelvePreferences.h"

@interface SBApplication : NSObject
- (NSString *)bundleIdentifier;
@end
@interface SBActivationSettings : NSObject
- (id)objectForActivationSetting:(unsigned int)setting;
- (NSInteger)flagForActivationSetting:(unsigned int)setting;
@end
@interface SBApplicationSceneEntity : NSObject
- (SBApplication *)application;
- (SBActivationSettings *)activationSettings;
@end
@interface SBWorkspaceTransitionContext : NSObject
- (NSSet *)previousEntities;
- (NSSet *)entities;
- (BOOL)animationDisabled;
@end
@interface SBApplicationSceneView : UIView
- (SBApplication *)application;
@end

static NSString *haoge_springtwelve_wetypeSource;
static UIView *haoge_springtwelve_wetypeSnapshot;
static NSMutableSet<UIView *> *haoge_springtwelve_wetypeFading;
static id haoge_springtwelve_wetypeObserver;

static void haoge_springtwelve_wetypeClear(void) {
    haoge_springtwelve_wetypeSource = nil;
    [haoge_springtwelve_wetypeSnapshot removeFromSuperview];
    haoge_springtwelve_wetypeSnapshot = nil;
    // Fades keep a local snapshot after the global slot is cleared.
    for (UIView *snapshot in [haoge_springtwelve_wetypeFading allObjects]) [snapshot removeFromSuperview];
    [haoge_springtwelve_wetypeFading removeAllObjects];
}

static BOOL haoge_springtwelve_wetypeMethod(Class cls, NSString *selector,
                                           const char *returns, BOOL setting) {
    Method method = cls ? class_getInstanceMethod(cls, NSSelectorFromString(selector)) : NULL;
    if (!method || method_getNumberOfArguments(method) != (setting ? 3u : 2u)) return NO;
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (strlen(type) != 1 || !strchr(returns, type[0])) return NO;
    method_getArgumentType(method, 0, type, sizeof(type));
    if (strcmp(type, "@") != 0) return NO;
    method_getArgumentType(method, 1, type, sizeof(type));
    if (strcmp(type, ":") != 0) return NO;
    if (setting) {
        method_getArgumentType(method, 2, type, sizeof(type));
        // Both unsigned setting widths pass these small constants in x2.
        if (strcmp(type, "I") != 0 && strcmp(type, "Q") != 0) return NO;
    }
    return YES;
}

%group HaogeSpringTwelveWeTypeVoice
%hook SBWorkspaceTransitionContext

- (BOOL)animationDisabled {
    BOOL original = %orig;
    if (![NSThread isMainThread]) return original;
    if (!HaogeSpringTwelveOn(@"weTypeVoiceNoJump")) {
        haoge_springtwelve_wetypeClear();
        return original;
    }
    SBApplicationSceneEntity *previous = [[self previousEntities] anyObject];
    SBApplicationSceneEntity *current = [[self entities] anyObject];
    Class entityClass = NSClassFromString(@"SBApplicationSceneEntity");
    if (![previous isKindOfClass:entityClass] || ![current isKindOfClass:entityClass]) return original;

    NSString *source = [[previous application] bundleIdentifier];
    NSString *target = [[current application] bundleIdentifier];
    SBActivationSettings *settings = [current activationSettings];
    id url = [settings objectForActivationSetting:5];
    if ([target isEqualToString:@"com.tencent.wetype"] &&
        [url isKindOfClass:[NSURL class]] &&
        [[url scheme] isEqualToString:@"wetype"] &&
        [[url host] isEqualToString:@"WXKBURL_STARTVOICERECORD"]) {
        haoge_springtwelve_wetypeSource = source;
        return YES;
    }
    // Preserve the recovered numeric flag; its private enum name is unknown.
    if ([settings flagForActivationSetting:42] && [source isEqualToString:@"com.tencent.wetype"]) return YES;
    return original;
}

%end
%hook SBApplicationSceneView

- (void)layoutSubviews {
    %orig;
    if (![NSThread isMainThread]) return;
    if (!HaogeSpringTwelveOn(@"weTypeVoiceNoJump")) {
        haoge_springtwelve_wetypeClear();
        return;
    }
    NSString *bundle = [[self application] bundleIdentifier];
    if (!bundle) return;
    if ([haoge_springtwelve_wetypeSource isEqualToString:bundle]) {
        haoge_springtwelve_wetypeSource = nil;
        if (!haoge_springtwelve_wetypeSnapshot) {
            UIWindow *window = [self window];
            UIView *snapshot = [window snapshotViewAfterScreenUpdates:NO];
            if (!snapshot) return;
            snapshot.frame = window.bounds;
            snapshot.userInteractionEnabled = NO;
            haoge_springtwelve_wetypeSnapshot = snapshot;
            [window addSubview:snapshot];
            return;
        }
    }
    if (haoge_springtwelve_wetypeSnapshot) {
        UIView *snapshot = haoge_springtwelve_wetypeSnapshot;
        haoge_springtwelve_wetypeSnapshot = nil;
        if (!haoge_springtwelve_wetypeFading) haoge_springtwelve_wetypeFading = [NSMutableSet set];
        [haoge_springtwelve_wetypeFading addObject:snapshot];
        [UIView animateWithDuration:0.3 delay:0.3 options:0
                         animations:^{ snapshot.alpha = 0.0; }
                         completion:^(BOOL finished) {
                             (void)finished;
                             [snapshot removeFromSuperview];
                             [haoge_springtwelve_wetypeFading removeObject:snapshot];
                         }];
    }
}

%end
%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
            ![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
        Class context = NSClassFromString(@"SBWorkspaceTransitionContext");
        Class scene = NSClassFromString(@"SBApplicationSceneView");
        Class entity = NSClassFromString(@"SBApplicationSceneEntity");
        Class settings = NSClassFromString(@"SBActivationSettings");
        if (!haoge_springtwelve_wetypeMethod(context, @"animationDisabled", "Bc", NO) ||
            !haoge_springtwelve_wetypeMethod(context, @"previousEntities", "@", NO) ||
            !haoge_springtwelve_wetypeMethod(context, @"entities", "@", NO) ||
            !haoge_springtwelve_wetypeMethod(scene, @"layoutSubviews", "v", NO) ||
            !haoge_springtwelve_wetypeMethod(scene, @"application", "@", NO) ||
            !haoge_springtwelve_wetypeMethod(entity, @"application", "@", NO) ||
            !haoge_springtwelve_wetypeMethod(entity, @"activationSettings", "@", NO) ||
            !haoge_springtwelve_wetypeMethod(settings, @"objectForActivationSetting:", "@", YES) ||
            !haoge_springtwelve_wetypeMethod(settings, @"flagForActivationSetting:", "ql", YES)) return;
        // Install regardless of preference; the existing snapshot supplies a live, default-OFF switch.
        %init(HaogeSpringTwelveWeTypeVoice);
        haoge_springtwelve_wetypeObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:HaogeSpringTwelvePreferencesChanged object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                (void)note;
                if (!HaogeSpringTwelveOn(@"weTypeVoiceNoJump")) haoge_springtwelve_wetypeClear();
            }];
    }
}
