// Adapted from the user's Clipboard-PasteTip-Source reconstruction.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <string.h>
#import "HaogeSpringTwelveSwitches.h"

@interface PBCFUserNotificationPasteAnnouncer : NSObject
- (void)authorizationDidCompleteWithPasteAllowed:(BOOL)allowed;
@end

static BOOL haoge_springtwelve_pasteMethod(Class cls, BOOL classMethod, NSString *name, NSArray<NSString *> *types) {
    if (!cls) return NO;
    SEL selector = NSSelectorFromString(name);
    Method method = classMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != types.count + 2) return NO;
    char result[16] = {0};
    method_getReturnType(method, result, sizeof(result));
    if (strcmp(result, "v")) return NO;
    for (NSUInteger i = 0; i < types.count; i++) {
        char actual[64] = {0};
        method_getArgumentType(method, (unsigned)i + 2, actual, sizeof(actual));
        const char *expected = types[i].UTF8String;
        BOOL matches = !strcmp(expected, "B") ? (!strcmp(actual, "B") || !strcmp(actual, "c")) :
            (!strcmp(expected, "@") ? actual[0] == '@' : !strcmp(actual, expected));
        if (!matches) return NO;
    }
    return YES;
}

static BOOL haoge_springtwelve_pasteCanRespond(id item, BOOL *wide) {
    Class cls = object_getClass(item);
    if (!haoge_springtwelve_pasteMethod(cls, NO, @"_setActivated:", @[@"B"])) return NO;
    if (haoge_springtwelve_pasteMethod(cls, NO, @"_sendResponseAndCleanUp:", @[@"q"])) {
        *wide = YES; return YES;
    }
    *wide = NO;
    return haoge_springtwelve_pasteMethod(cls, NO, @"_sendResponseAndCleanUp:", @[@"i"]);
}

%group HaogeSpringTwelvePasteLegacy
%hook DRPasteAnnouncer
- (void)announceDeniedPaste {
    if (!HaogeSpringTwelveOn(@"allowPasteWithoutPrompt")) { %orig; }
}
- (void)announcePaste:(id)paste {
    if (!HaogeSpringTwelveOn(@"allowPasteWithoutPrompt")) { %orig; }
}
%end
%end

%group HaogeSpringTwelvePasteRemote
%hook PBDruidRemotePasteAnnouncer
+ (void)announceDeniedPaste {
    if (!HaogeSpringTwelveOn(@"allowPasteWithoutPrompt")) { %orig; }
}
+ (void)announcePaste:(id)paste {
    if (!HaogeSpringTwelveOn(@"allowPasteWithoutPrompt")) { %orig; }
}
%end
%end

%group HaogeSpringTwelvePasteCFAnnouncements
%hook PBCFUserNotificationPasteAnnouncer
+ (void)announceDeniedPaste {
    if (!HaogeSpringTwelveOn(@"allowPasteWithoutPrompt")) { %orig; }
}
+ (void)announcePaste:(id)paste {
    if (!HaogeSpringTwelveOn(@"allowPasteWithoutPrompt")) { %orig; }
}
%end
%end

%group HaogeSpringTwelvePasteCFAuthorization
%hook PBCFUserNotificationPasteAnnouncer
- (void)requestAuthorizationForPaste:(id)paste replyHandler:(void (^)(BOOL))reply {
    if (!HaogeSpringTwelveOn(@"allowPasteWithoutPrompt")) { %orig; return; }
    if (reply) reply(YES);
    [self authorizationDidCompleteWithPasteAllowed:YES];
}
- (void)announcePaste:(id)paste replyHandler:(void (^)(BOOL))reply {
    if (!HaogeSpringTwelveOn(@"allowPasteWithoutPrompt")) { %orig; return; }
    if (reply) reply(YES);
    [self authorizationDidCompleteWithPasteAllowed:YES];
}
%end
%end

%group HaogeSpringTwelvePasteAlert
%hook SBAlertItem
+ (void)activateAlertItem:(id)item {
    if (HaogeSpringTwelveOn(@"allowPasteWithoutPrompt")) {
        Class alertClass = NSClassFromString(@"SBUserNotificationAlert");
        if (alertClass && [item isKindOfClass:alertClass]) {
            Ivar sourceIvar = class_getInstanceVariable(object_getClass(item), "_alertSource");
            const char *encoding = sourceIvar ? ivar_getTypeEncoding(sourceIvar) : NULL;
            id source = encoding && encoding[0] == '@' ? object_getIvar(item, sourceIvar) : nil;
            BOOL wide = NO;
            if ([source isKindOfClass:NSString.class] && [source isEqualToString:@"pasted"] &&
                haoge_springtwelve_pasteCanRespond(item, &wide)) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(item, NSSelectorFromString(@"_setActivated:"), NO);
                SEL respond = NSSelectorFromString(@"_sendResponseAndCleanUp:");
                // Preserve original response value 1; do not guess its enum name.
                if (wide) ((void (*)(id, SEL, NSInteger))objc_msgSend)(item, respond, (NSInteger)1);
                else ((void (*)(id, SEL, int))objc_msgSend)(item, respond, 1);
                return;
            }
        }
    }
    %orig;
}
%end
%end

static void haoge_springtwelve_pasteInstall(void) {
    static BOOL legacy, remote, announcements, authorization, alerts;
    Class cls = NSClassFromString(@"DRPasteAnnouncer");
    if (!legacy && haoge_springtwelve_pasteMethod(cls, NO, @"announceDeniedPaste", @[]) &&
        haoge_springtwelve_pasteMethod(cls, NO, @"announcePaste:", @[@"@"])) {
        legacy = YES;
        %init(HaogeSpringTwelvePasteLegacy);
    }
    if (@available(iOS 16.0, *)) {
        cls = NSClassFromString(@"PBDruidRemotePasteAnnouncer");
        if (!remote && haoge_springtwelve_pasteMethod(cls, YES, @"announceDeniedPaste", @[]) &&
            haoge_springtwelve_pasteMethod(cls, YES, @"announcePaste:", @[@"@"])) {
            remote = YES;
            %init(HaogeSpringTwelvePasteRemote);
        }
        cls = NSClassFromString(@"PBCFUserNotificationPasteAnnouncer");
        if (!announcements && haoge_springtwelve_pasteMethod(cls, YES, @"announceDeniedPaste", @[]) &&
            haoge_springtwelve_pasteMethod(cls, YES, @"announcePaste:", @[@"@"])) {
            announcements = YES;
            %init(HaogeSpringTwelvePasteCFAnnouncements);
        }
        if (!authorization &&
            haoge_springtwelve_pasteMethod(cls, NO, @"requestAuthorizationForPaste:replyHandler:", @[@"@", @"@?"]) &&
            haoge_springtwelve_pasteMethod(cls, NO, @"announcePaste:replyHandler:", @[@"@", @"@?"]) &&
            haoge_springtwelve_pasteMethod(cls, NO, @"authorizationDidCompleteWithPasteAllowed:", @[@"B"])) {
            authorization = YES;
            %init(HaogeSpringTwelvePasteCFAuthorization);
        }
        cls = NSClassFromString(@"SBAlertItem");
        if (!alerts && haoge_springtwelve_pasteMethod(cls, YES, @"activateAlertItem:", @[@"@"])) {
            alerts = YES;
            %init(HaogeSpringTwelvePasteAlert);
        }
    }
}

static int HaogeSpringTwelvePasteInstallQueued;
static void haoge_springtwelve_pasteImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    if (__atomic_exchange_n(&HaogeSpringTwelvePasteInstallQueued, 1, __ATOMIC_RELAXED)) return;
    // dyld notifications may precede Objective-C registration. Never hook under
    // the image-loader lock; coalesce initial image callbacks onto the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        __atomic_store_n(&HaogeSpringTwelvePasteInstallQueued, 0, __ATOMIC_RELAXED);
        haoge_springtwelve_pasteInstall();
    });
}

%ctor {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName;
        BOOL springBoard = [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] &&
            [process isEqualToString:@"SpringBoard"];
        if (!springBoard && ![process isEqualToString:@"druid"] && ![process isEqualToString:@"pasted"]) return;
        _dyld_register_func_for_add_image(haoge_springtwelve_pasteImageAdded);
    }
}
