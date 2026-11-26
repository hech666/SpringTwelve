#import "AxsSpringTwelveSwitches.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <string.h>
#include <atomic>

#pragma mark - Dynamic access and associated state

static char AxsDialDualButtonsKey;
static char AxsDialDualHostKey;
static char AxsDialT9BarKey;
static char AxsDialT9ScrollKey;
static char AxsDialT9ResultsKey;
static char AxsDialT9ObservedLCDKey;
static char AxsDialT9QueryKey;
static char AxsDialT9GenerationKey;
static char AxsDialT9RetryCountKey;
static char AxsDialT9ForceRetryKey;
static char AxsDialOriginalButtonKey;
static char AxsDialOriginalHiddenKey;
static char AxsDialDeleteButtonKey;
static char AxsDialDeleteTransformKey;
static char AxsDialDeleteLayoutPendingKey;
static char AxsDialIdentityKey;

static id AxsDialGet(id object, NSString *name) {
    if (!object || !name.length) return nil;
    SEL selector = NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

// The confirmed owner of these controls is dialerView. A controller fallback is
// accepted only when it actually returns a UIView (older host implementations).
static UIView *AxsDialPart(id controller, NSString *name) {
    id part = AxsDialGet(AxsDialGet(controller, @"dialerView"), name);
    if (![part isKindOfClass:[UIView class]]) part = AxsDialGet(controller, name);
    return [part isKindOfClass:[UIView class]] ? part : nil;
}

static NSArray *AxsDialIdentities(id controller) {
    id values = AxsDialGet(AxsDialGet(controller, @"defaultCallProvider"), @"prioritizedSenderIdentities");
    if (![values isKindOfClass:[NSArray class]]) values = AxsDialGet(values, @"allObjects");
    if (![values isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *real = [NSMutableArray array];
    for (id value in values) {
        if (value && value != [NSNull null] && ![value isKindOfClass:[NSString class]] &&
            ![value isKindOfClass:[NSNumber class]]) [real addObject:value];
    }
    return [real copy];
}

static BOOL AxsDialDualEnabled(void) {
    return AxsSpringTwelveOn(@"captureDualSimDialerEnabled");
}

static BOOL AxsDialT9Enabled(void) {
    return AxsSpringTwelveOn(@"captureT9DialerEnabled");
}

static void AxsDialRemoveT9Observer(id controller) {
    id oldLCD = objc_getAssociatedObject(controller, &AxsDialT9ObservedLCDKey);
    if (!oldLCD) return;
    SEL removeTarget = @selector(removeTarget:action:forControlEvents:);
    if ([oldLCD respondsToSelector:removeTarget]) {
        ((void (*)(id, SEL, id, SEL, UIControlEvents))objc_msgSend)(
            oldLCD, removeTarget, controller,
            @selector(axs_springtwelve_dialerTextChanged:), UIControlEventEditingChanged);
    }
    [[NSNotificationCenter defaultCenter] removeObserver:controller
        name:UITextFieldTextDidChangeNotification object:oldLCD];
    objc_setAssociatedObject(controller, &AxsDialT9ObservedLCDKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void AxsDialEnsureT9Observer(id controller, id lcdView) {
    if (!AxsDialT9Enabled() || !lcdView) {
        AxsDialRemoveT9Observer(controller);
        return;
    }
    id previous = objc_getAssociatedObject(controller, &AxsDialT9ObservedLCDKey);
    if (previous == lcdView) return;
    AxsDialRemoveT9Observer(controller);

    SEL addTarget = @selector(addTarget:action:forControlEvents:);
    if ([lcdView respondsToSelector:addTarget]) {
        ((void (*)(id, SEL, id, SEL, UIControlEvents))objc_msgSend)(
            lcdView, addTarget, controller,
            @selector(axs_springtwelve_dialerTextChanged:), UIControlEventEditingChanged);
    }
    [[NSNotificationCenter defaultCenter] addObserver:controller
        selector:@selector(axs_springtwelve_dialerTextChanged:)
        name:UITextFieldTextDidChangeNotification object:lcdView];
    objc_setAssociatedObject(controller, &AxsDialT9ObservedLCDKey, lcdView,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Dual-SIM call controls

static void AxsDialRestoreDeleteButton(id controller) {
    UIView *button = objc_getAssociatedObject(controller, &AxsDialDeleteButtonKey);
    NSArray<NSValue *> *transforms = objc_getAssociatedObject(controller, &AxsDialDeleteTransformKey);
    if (button && transforms.count == 2 &&
        CGAffineTransformEqualToTransform(button.transform, transforms[1].CGAffineTransformValue)) {
        [UIView performWithoutAnimation:^{ button.transform = transforms[0].CGAffineTransformValue; }];
    }
    objc_setAssociatedObject(controller, &AxsDialDeleteButtonKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &AxsDialDeleteTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Move the actual control, not a copy: native targets, gestures and visibility stay intact.
static BOOL AxsDialPositionDeleteButton(id controller, UIView *button, UIView *host, CGRect row) {
    CGRect original = [button convertRect:button.bounds toView:host];
    CGPoint destination = CGPointMake(CGRectGetMidX(row),
                                      CGRectGetMaxY(row) + 8.0 + CGRectGetHeight(original) / 2.0);
    CGRect target = CGRectOffset(original, destination.x - CGRectGetMidX(original),
                                  destination.y - CGRectGetMidY(original));
    // A transform outside any native ancestor may draw correctly but reject touches.
    for (UIView *ancestor = button.superview; ancestor; ancestor = ancestor.superview) {
        if (!CGRectContainsRect(ancestor.bounds, [host convertRect:target toView:ancestor])) return NO;
        if (ancestor == host) break;
    }
    CGPoint from = [host convertPoint:CGPointMake(CGRectGetMidX(original), CGRectGetMidY(original))
                               toView:button.superview];
    CGPoint to = [host convertPoint:destination toView:button.superview];
    CGAffineTransform base = button.transform;
    CGAffineTransform moved = base;
    moved.tx += to.x - from.x;
    moved.ty += to.y - from.y;
    objc_setAssociatedObject(controller, &AxsDialDeleteButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &AxsDialDeleteTransformKey,
                             @[[NSValue valueWithCGAffineTransform:base],
                               [NSValue valueWithCGAffineTransform:moved]], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView performWithoutAnimation:^{ button.transform = moved; }];
    return YES;
}

static void AxsDialRemoveDualButtons(id controller) {
    AxsDialRestoreDeleteButton(controller);
    NSArray *buttons = objc_getAssociatedObject(controller, &AxsDialDualButtonsKey);
    for (id button in buttons) {
        if ([button isKindOfClass:[UIView class]]) [button removeFromSuperview];
    }
    id originalButton = objc_getAssociatedObject(controller, &AxsDialOriginalButtonKey);
    NSNumber *wasHidden = objc_getAssociatedObject(controller, &AxsDialOriginalHiddenKey);
    if ([originalButton isKindOfClass:[UIView class]] && wasHidden)
        ((UIView *)originalButton).hidden = wasHidden.boolValue;
    objc_setAssociatedObject(controller, &AxsDialDualButtonsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &AxsDialDualHostKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &AxsDialOriginalButtonKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &AxsDialOriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSString *AxsDialIdentityTitle(id identity, NSUInteger index) {
    // Prefer the short, display-appropriate name; localizedName can be a long
    // format (e.g. a full number or a verbose label) that truncates to "…".
    NSString *title = AxsDialGet(identity, @"localizedShortName");
    if (![title isKindOfClass:[NSString class]] || !title.length)
        title = AxsDialGet(identity, @"localizedName");
    if (![title isKindOfClass:[NSString class]] || !title.length ||
        title.length > 4) {
        title = index == 0 ? @"卡一" : @"卡二";
    }
    return title;
}

static void AxsDialUpdateDualButtons(id controller) {
    AxsDialRestoreDeleteButton(controller);
    UIView *callButton = AxsDialPart(controller, @"callButton");
    UIView *host = AxsDialGet(controller, @"dialerView");
    if (![host isKindOfClass:UIView.class] || ![callButton isDescendantOfView:host])
        host = callButton.superview;
    NSArray *identities = AxsDialIdentities(controller);
    if (!AxsDialDualEnabled() || identities.count < 2 || !callButton.superview || !host ||
        CGRectGetWidth(callButton.bounds) < 20.0 || CGRectGetHeight(callButton.bounds) < 20.0) {
        AxsDialRemoveDualButtons(controller);
        return;
    }

    // A native circular call button is an anchor, not the width of two buttons.
    // Mount in dialerView so a narrow native wrapper cannot clip/reject touches.
    CGRect anchor = [callButton convertRect:callButton.bounds toView:host];
    CGRect available = UIEdgeInsetsInsetRect(host.bounds, host.safeAreaInsets);
    CGFloat gap = 18.0;
    CGFloat height = 48.0;
    CGFloat totalWidth = MIN(CGRectGetWidth(available) - 24.0,
                             MIN(320.0, MAX(240.0, CGRectGetWidth(available) * 0.72)));
    CGFloat width = (totalWidth - gap) / 2.0;
    UIView *deleteButton = AxsDialPart(controller, @"deleteButton");
    CGFloat controlsHeight = height;
    if (deleteButton) {
        if (![deleteButton isDescendantOfView:host] || [deleteButton isDescendantOfView:callButton]) {
            AxsDialRemoveDualButtons(controller);
            return;
        }
        CGRect deleteRect = [deleteButton convertRect:deleteButton.bounds toView:host];
        if (CGRectIsEmpty(deleteRect) || CGRectIsInfinite(deleteRect)) {
            AxsDialRemoveDualButtons(controller);
            return;
        }
        controlsHeight += 8.0 + MAX(44.0, CGRectGetHeight(deleteRect));
    }
    // Do not shift above the native call row into the numeric keypad.
    CGFloat minimumY = MAX(CGRectGetMinY(available), CGRectGetMinY(anchor));
    CGFloat maximumY = CGRectGetMaxY(available) - controlsHeight;
    if (CGRectIsEmpty(anchor) || CGRectIsInfinite(anchor) || width < 96.0 || minimumY > maximumY) {
        AxsDialRemoveDualButtons(controller);
        return;
    }
    CGFloat x = MIN(MAX(CGRectGetMidX(anchor) - totalWidth / 2.0, CGRectGetMinX(available) + 12.0),
                    CGRectGetMaxX(available) - totalWidth - 12.0);
    CGFloat y = MIN(MAX(CGRectGetMidY(anchor) - height / 2.0, minimumY), maximumY);

    NSArray *buttons = objc_getAssociatedObject(controller, &AxsDialDualButtonsKey);
    id oldCallButton = objc_getAssociatedObject(controller, &AxsDialOriginalButtonKey);
    id oldHost = objc_getAssociatedObject(controller, &AxsDialDualHostKey);
    if (![buttons isKindOfClass:[NSArray class]] || buttons.count != 2 ||
        oldCallButton != callButton || oldHost != host) {
        AxsDialRemoveDualButtons(controller);
        BOOL originalHidden = callButton.hidden;
        NSMutableArray *created = [NSMutableArray arrayWithCapacity:2];
        UIColor *green = [UIColor systemGreenColor];
        UIColor *blue = [UIColor systemBlueColor];
        NSArray *colors = @[green, blue];
        for (NSUInteger index = 0; index < 2; index++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tag = index == 0 ? 101 : 102;
            button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
            button.layer.cornerRadius = 27.0;
            button.layer.masksToBounds = YES;
            button.backgroundColor = colors[index];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            [button addTarget:controller action:@selector(axs_springtwelve_dualSimTapped:)
             forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(button, &AxsDialIdentityKey, identities[index],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [host addSubview:button];
            [created addObject:button];
        }
        buttons = [created copy];
        objc_setAssociatedObject(controller, &AxsDialDualButtonsKey, buttons, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, &AxsDialDualHostKey, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, &AxsDialOriginalButtonKey, callButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, &AxsDialOriginalHiddenKey, @(originalHidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    callButton.hidden = YES; // Phone may restore the native button during layout.
    for (NSUInteger index = 0; index < 2; index++) {
        UIButton *button = buttons[index];
        id identity = identities[index];
        objc_setAssociatedObject(button, &AxsDialIdentityKey, identity, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        button.frame = CGRectMake(x + index * (width + gap), y, width, height);
        button.layer.cornerRadius = height / 2.0;
        [button setTitle:AxsDialIdentityTitle(identity, index) forState:UIControlStateNormal];
        button.accessibilityLabel = AxsDialIdentityTitle(identity, index);
        button.hidden = NO;
        [host bringSubviewToFront:button];
    }
    if (deleteButton && !AxsDialPositionDeleteButton(controller, deleteButton, host,
                                                     CGRectMake(x, y, totalWidth, height))) {
        AxsDialRemoveDualButtons(controller);
    }
}

#pragma mark - T9 contact indexing

static dispatch_queue_t AxsDialContactsQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.axs.springtwelve.dialer.contacts", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSArray *AxsDialContactCache;
static NSMutableArray *AxsDialContactWaiters;
static BOOL AxsDialContactLoadStarted;
static BOOL AxsDialContactCacheReady;
static NSTimeInterval AxsDialContactRetryAfter;
static NSHashTable *AxsDialControllers;
static char AxsDialT9SuppressedKey;
static std::atomic<bool> AxsDialApplicationActive{false};

static BOOL AxsDialIsApplicationActive(void) {
    return AxsDialApplicationActive.load(std::memory_order_acquire);
}

static void AxsDialFinishContactLoad(NSArray *contacts) {
    BOOL success = contacts != nil;
    if (success) {
        AxsDialContactCache = [contacts copy];
        AxsDialContactCacheReady = YES;
        AxsDialContactRetryAfter = 0.0;
    } else {
        AxsDialContactCache = @[];
        AxsDialContactCacheReady = NO;
        AxsDialContactRetryAfter = NSProcessInfo.processInfo.systemUptime + 5.0;
    }
    NSLog(@"[SpringTwelve:T9] contacts %@ count=%lu",
          success ? @"loaded" : @"failed",
          (unsigned long)(success ? AxsDialContactCache.count : 0));
    AxsDialContactLoadStarted = NO;
    NSArray *waiters = [AxsDialContactWaiters copy] ?: @[];
    [AxsDialContactWaiters removeAllObjects];
    NSArray *result = AxsDialContactCache ?: @[];
    for (id waiterObject in waiters) {
        void (^waiter)(NSArray *, BOOL) = waiterObject;
        dispatch_async(dispatch_get_main_queue(), ^{ waiter(result, success); });
    }
}

static void AxsDialFetchContacts(id store) {
    @try {
        Class requestClass = NSClassFromString(@"CNContactFetchRequest");
        if (!requestClass || ![requestClass instancesRespondToSelector:@selector(initWithKeysToFetch:)]) {
            AxsDialFinishContactLoad(nil);
            return;
        }
        NSArray *keys = @[@"givenName", @"familyName", @"middleName", @"nickname",
                          @"organizationName", @"phoneNumbers"];
        id request = ((id (*)(id, SEL, id))objc_msgSend)(
            [requestClass alloc], @selector(initWithKeysToFetch:), keys);
        SEL enumerate = NSSelectorFromString(@"enumerateContactsWithFetchRequest:error:usingBlock:");
        if (!request || ![store respondsToSelector:enumerate]) {
            AxsDialFinishContactLoad(nil);
            return;
        }
        NSMutableArray *contacts = [NSMutableArray array];
        NSError *error = nil;
        id block = ^(id contact, BOOL *stop) {
            if (contact) [contacts addObject:contact];
        };
        BOOL success = ((BOOL (*)(id, SEL, id, NSError **, id))objc_msgSend)(
            store, enumerate, request, &error, block);
        NSLog(@"[SpringTwelve:T9] enumeration success=%d contacts=%lu error=%@/%ld",
              success, (unsigned long)contacts.count,
              error.domain ?: @"none", (long)error.code);
        AxsDialFinishContactLoad(success && !error ? contacts : nil);
    } @catch (NSException *exception) {
        NSLog(@"[SpringTwelve:T9] enumeration exception=%@", exception.name);
        AxsDialFinishContactLoad(nil);
    }
}

static void AxsDialLoadContacts(void (^completion)(NSArray *, BOOL)) {
    if (!completion) return;
    dispatch_async(AxsDialContactsQueue(), ^{
        if (!AxsDialContactWaiters) AxsDialContactWaiters = [NSMutableArray array];
        if (!AxsDialIsApplicationActive()) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], NO); });
            return;
        }
        if (AxsDialContactCacheReady) {
            NSArray *cached = AxsDialContactCache ?: @[];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(cached, YES); });
            return;
        }
        if (AxsDialContactRetryAfter > NSProcessInfo.processInfo.systemUptime) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], NO); });
            return;
        }
        [AxsDialContactWaiters addObject:[completion copy]];
        if (AxsDialContactLoadStarted) return;
        AxsDialContactLoadStarted = YES;

        // Do not request access here. Contacts.framework enforces the access
        // available to the host process; absence of a prompt is not a bypass.
        @try {
            void *contactsHandle = dlopen("/System/Library/Frameworks/Contacts.framework/Contacts", RTLD_LAZY);
            Class storeClass = NSClassFromString(@"CNContactStore");
            NSLog(@"[SpringTwelve:T9] contacts framework=%d storeClass=%d",
                  contactsHandle != NULL, storeClass != Nil);
            if (!storeClass) {
                AxsDialFinishContactLoad(nil);
                return;
            }
            id store = [[storeClass alloc] init];
            if (!store) {
                AxsDialFinishContactLoad(nil);
                return;
            }
            AxsDialFetchContacts(store);
        } @catch (__unused NSException *exception) {
            AxsDialFinishContactLoad(nil);
        }
    });
}

static NSString *AxsDialASCIIOnlyDigits(NSString *source) {
    if (![source isKindOfClass:[NSString class]] || source.length == 0) return @"";
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger index = 0; index < source.length; index++) {
        unichar ch = [source characterAtIndex:index];
        if (ch >= '0' && ch <= '9') [digits appendFormat:@"%C", ch];
    }
    return digits;
}

static NSString *AxsDialNormalizedLatin(NSString *source) {
    if (![source isKindOfClass:[NSString class]] || source.length == 0) return @"";
    NSString *latin = source;
    @try {
        NSString *mandarin = [latin stringByApplyingTransform:NSStringTransformMandarinToLatin reverse:NO];
        if (mandarin.length) latin = mandarin;
        NSString *plain = [latin stringByApplyingTransform:NSStringTransformStripDiacritics reverse:NO];
        if (plain.length) latin = plain;
    } @catch (__unused NSException *exception) {
        // The lowercase/ASCII filtering below is a safe fallback on older Foundation implementations.
    }
    latin = [latin lowercaseString];
    NSMutableString *normalized = [NSMutableString string];
    BOOL pendingSpace = NO;
    for (NSUInteger index = 0; index < latin.length; index++) {
        unichar ch = [latin characterAtIndex:index];
        if (ch >= 'a' && ch <= 'z') {
            if (pendingSpace && normalized.length) [normalized appendString:@" "];
            [normalized appendFormat:@"%C", ch];
            pendingSpace = NO;
        } else {
            pendingSpace = YES;
        }
    }
    return normalized;
}

static unichar AxsDialT9DigitForLetter(unichar letter) {
    switch (letter) {
        case 'a': case 'b': case 'c': return '2';
        case 'd': case 'e': case 'f': return '3';
        case 'g': case 'h': case 'i': return '4';
        case 'j': case 'k': case 'l': return '5';
        case 'm': case 'n': case 'o': return '6';
        case 'p': case 'q': case 'r': case 's': return '7';
        case 't': case 'u': case 'v': return '8';
        case 'w': case 'x': case 'y': case 'z': return '9';
        default: return 0;
    }
}

static NSString *AxsDialT9Code(NSString *normalized, BOOL initialsOnly) {
    NSMutableString *code = [NSMutableString string];
    BOOL inWord = NO;
    for (NSUInteger index = 0; index < normalized.length; index++) {
        unichar ch = [normalized characterAtIndex:index];
        if (ch >= 'a' && ch <= 'z') {
            if (!initialsOnly || !inWord) {
                unichar digit = AxsDialT9DigitForLetter(ch);
                if (digit) [code appendFormat:@"%C", digit];
            }
            inWord = YES;
        } else {
            inWord = NO;
        }
    }
    return code;
}

static NSString *AxsDialContactString(id contact, NSString *property) {
    id value = AxsDialGet(contact, property);
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSArray *AxsDialContactPhones(id contact) {
    id value = AxsDialGet(contact, @"phoneNumbers");
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static NSString *AxsDialPhoneString(id labeledValue) {
    id phoneNumber = AxsDialGet(labeledValue, @"value");
    id value = AxsDialGet(phoneNumber, @"stringValue");
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static BOOL AxsDialContactMatches(id contact, NSString *digits, BOOL *nameMatched) {
    if (nameMatched) *nameMatched = NO;
    BOOL matchedByName = NO;
    NSString *family = AxsDialContactString(contact, @"familyName");
    NSString *given = AxsDialContactString(contact, @"givenName");
    NSString *middle = AxsDialContactString(contact, @"middleName");
    NSString *nickname = AxsDialContactString(contact, @"nickname");
    NSString *organization = AxsDialContactString(contact, @"organizationName");
    NSString *full = [NSString stringWithFormat:@"%@%@%@%@", family, given, middle, nickname];
    if (!full.length) full = organization;
    if (full.length) {
        NSString *normalized = AxsDialNormalizedLatin(full);
        matchedByName = [AxsDialT9Code(normalized, NO) hasPrefix:digits] ||
                        [AxsDialT9Code(normalized, YES) hasPrefix:digits];
    }
    if (nameMatched) *nameMatched = matchedByName;
    // Phone digits are deliberately not a search field; T9 matches only name prefixes.
    return matchedByName;
}

static NSArray *AxsDialFindCandidates(NSArray *contacts, NSString *digits) {
    if (!digits.length || !contacts.count) return @[];
    NSMutableArray *matches = [NSMutableArray arrayWithCapacity:8];
    for (id contact in contacts) {
        if (!AxsDialContactMatches(contact, digits, NULL)) continue;
        NSString *family = AxsDialContactString(contact, @"familyName");
        NSString *given = AxsDialContactString(contact, @"givenName");
        NSString *middle = AxsDialContactString(contact, @"middleName");
        NSString *nickname = AxsDialContactString(contact, @"nickname");
        NSString *name = [NSString stringWithFormat:@"%@%@%@%@", family, given, middle, nickname];
        if (!name.length) name = AxsDialContactString(contact, @"organizationName");
        if (!name.length) continue;
        NSArray *phones = AxsDialContactPhones(contact);
        NSString *phone = phones.count ? AxsDialPhoneString(phones[0]) : @"";
        if (!phone.length) continue;
        [matches addObject:@{@"name": name, @"phone": phone}];
        if (matches.count >= 8) break;
    }
    return [matches copy];
}

#pragma mark - T9 suggestion view

static void AxsDialLayoutT9Bar(id controller) {
    UIView *bar = objc_getAssociatedObject(controller, &AxsDialT9BarKey);
    if (![bar isKindOfClass:[UIView class]]) return;
    UIView *dialerView = AxsDialGet(controller, @"dialerView");
    UIView *lcdView = AxsDialPart(controller, @"lcdView");
    if (![dialerView isKindOfClass:[UIView class]] || ![lcdView isKindOfClass:[UIView class]]) {
        bar.hidden = YES;
        return;
    }
    UIView *host = dialerView;
    CGRect lcdRect = [lcdView convertRect:lcdView.bounds toView:host];
    CGFloat height = 38.0;
    CGFloat inset = 8.0;
    CGFloat y = CGRectGetMaxY(lcdRect) + 4.0;

    // Place suggestions in the gap above the keypad (the call button may be
    // below it and is not a reliable layout boundary across Phone versions).
    UIView *phonePad = AxsDialPart(controller, @"phonePadView");
    if ([phonePad isKindOfClass:[UIView class]]) {
        CGRect padRect = [phonePad convertRect:phonePad.bounds toView:host];
        if (y + height > CGRectGetMinY(padRect) - 2.0)
            y = CGRectGetMinY(lcdRect) - height - 4.0;
    }
    if (y < 0.0 || y + height > CGRectGetHeight(host.bounds) ||
        CGRectGetWidth(host.bounds) <= inset * 2.0) {
        bar.hidden = YES;
        return;
    }
    bar.frame = CGRectMake(inset, y, CGRectGetWidth(host.bounds) - inset * 2.0, height);
    UIScrollView *scroll = objc_getAssociatedObject(controller, &AxsDialT9ScrollKey);
    if ([scroll isKindOfClass:[UIScrollView class]]) scroll.frame = bar.bounds;

    NSArray *results = objc_getAssociatedObject(controller, &AxsDialT9ResultsKey);
    NSString *query = objc_getAssociatedObject(controller, &AxsDialT9QueryKey);
    BOOL suppressed = [objc_getAssociatedObject(controller, &AxsDialT9SuppressedKey) boolValue];
    BOOL visible = AxsDialApplicationActive && AxsDialT9Enabled() && !suppressed && query.length > 0 && results.count > 0 &&
                   [controller isViewLoaded] && ((UIViewController *)controller).view.window != nil;
    bar.hidden = !visible;
    if (visible) [host bringSubviewToFront:bar];
}

static void AxsDialShowCandidates(id controller, NSArray *candidates) {
    NSArray *safeCandidates = [candidates isKindOfClass:[NSArray class]] ? candidates : @[];
    objc_setAssociatedObject(controller, &AxsDialT9ResultsKey, safeCandidates,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *dialerView = AxsDialGet(controller, @"dialerView");
    if (![dialerView isKindOfClass:[UIView class]]) return;

    UIView *bar = objc_getAssociatedObject(controller, &AxsDialT9BarKey);
    UIScrollView *scroll = objc_getAssociatedObject(controller, &AxsDialT9ScrollKey);
    if (![bar isKindOfClass:[UIView class]] || ![scroll isKindOfClass:[UIScrollView class]]) {
        bar = [[UIView alloc] initWithFrame:CGRectZero];
        bar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.88];
        bar.layer.cornerRadius = 8.0;
        bar.layer.masksToBounds = YES;
        scroll = [[UIScrollView alloc] initWithFrame:bar.bounds];
        scroll.showsHorizontalScrollIndicator = NO;
        scroll.alwaysBounceHorizontal = YES;
        [bar addSubview:scroll];
        [dialerView addSubview:bar];
        objc_setAssociatedObject(controller, &AxsDialT9BarKey, bar,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, &AxsDialT9ScrollKey, scroll,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (bar.superview != dialerView) {
        [bar removeFromSuperview];
        [dialerView addSubview:bar];
    }

    for (UIView *subview in [scroll.subviews copy]) [subview removeFromSuperview];
    CGFloat buttonWidth = 148.0;
    CGFloat gap = 4.0;
    [safeCandidates enumerateObjectsUsingBlock:^(NSDictionary *candidate, NSUInteger index, BOOL *stop) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        NSString *name = [candidate[@"name"] isKindOfClass:[NSString class]] ? candidate[@"name"] : @"Contact";
        NSString *phone = [candidate[@"phone"] isKindOfClass:[NSString class]] ? candidate[@"phone"] : @"";
        [button setTitle:phone.length ? [NSString stringWithFormat:@"%@ · %@", name, phone] : name
                forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
        button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
        button.layer.cornerRadius = 6.0;
        button.clipsToBounds = YES;
        button.tag = (NSInteger)index;
        [button addTarget:controller action:@selector(axs_springtwelve_t9CandidateTapped:)
         forControlEvents:UIControlEventTouchUpInside];
        button.frame = CGRectMake(index * (buttonWidth + gap), 2.0, buttonWidth, 34.0);
        [scroll addSubview:button];
    }];
    scroll.contentSize = CGSizeMake(safeCandidates.count ? safeCandidates.count * (buttonWidth + gap) - gap : 0.0, 38.0);
    NSLog(@"[SpringTwelve:T9] candidateCount=%lu", (unsigned long)safeCandidates.count);
    bar.hidden = !AxsDialT9Enabled() || safeCandidates.count == 0;
    AxsDialLayoutT9Bar(controller);
    if (!bar.hidden) [dialerView bringSubviewToFront:bar];
}

static void AxsDialRefreshT9(id controller) {
    if (![NSThread isMainThread]) {
        __weak id weakController = controller;
        dispatch_async(dispatch_get_main_queue(), ^{
            id strongController = weakController;
            if (strongController) AxsDialRefreshT9(strongController);
        });
        return;
    }
    if (!AxsDialT9Enabled()) {
        AxsDialRemoveT9Observer(controller);
        UIView *bar = objc_getAssociatedObject(controller, &AxsDialT9BarKey);
        bar.hidden = YES;
        objc_setAssociatedObject(controller, &AxsDialT9QueryKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSUInteger generation = [objc_getAssociatedObject(controller, &AxsDialT9GenerationKey) unsignedIntegerValue] + 1;
        objc_setAssociatedObject(controller, &AxsDialT9GenerationKey, @(generation),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (!AxsDialApplicationActive) {
        UIView *bar = objc_getAssociatedObject(controller, &AxsDialT9BarKey);
        bar.hidden = YES;
        return;
    }
    if ([objc_getAssociatedObject(controller, &AxsDialT9SuppressedKey) boolValue]) {
        UIView *bar = objc_getAssociatedObject(controller, &AxsDialT9BarKey);
        bar.hidden = YES;
        return;
    }
    id lcdView = AxsDialPart(controller, @"lcdView");
    AxsDialEnsureT9Observer(controller, lcdView);
    NSString *text = AxsDialGet(lcdView, @"text");
    NSString *digits = AxsDialASCIIOnlyDigits(text);
    NSString *previous = objc_getAssociatedObject(controller, &AxsDialT9QueryKey);
    BOOL forced = [objc_getAssociatedObject(controller, &AxsDialT9ForceRetryKey) boolValue];
    if ([previous isEqualToString:digits] && !forced) return;
    objc_setAssociatedObject(controller, &AxsDialT9ForceRetryKey, @NO,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (![previous isEqualToString:digits]) {
        objc_setAssociatedObject(controller, &AxsDialT9RetryCountKey, @0,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSLog(@"[SpringTwelve:T9] input changed digitsLength=%lu", (unsigned long)digits.length);

    NSUInteger generation = [objc_getAssociatedObject(controller, &AxsDialT9GenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(controller, &AxsDialT9GenerationKey, @(generation),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &AxsDialT9QueryKey, digits,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (!digits.length) {
        AxsDialShowCandidates(controller, @[]);
        return;
    }
    AxsDialShowCandidates(controller, @[]);

    __weak id weakController = controller;
    AxsDialLoadContacts(^(NSArray *contacts, BOOL loaded) {
        id requestController = weakController;
        if (!requestController) return;
        if (!loaded) {
            NSUInteger retryCount = [objc_getAssociatedObject(requestController, &AxsDialT9RetryCountKey) unsignedIntegerValue] + 1;
            objc_setAssociatedObject(requestController, &AxsDialT9RetryCountKey, @(retryCount), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSLog(@"[SpringTwelve:T9] contact load failed retry=%lu/2", (unsigned long)retryCount);
            if (retryCount > 2) return;
            __weak id retryController = weakController;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                id currentController = retryController;
                if (!currentController || !AxsDialT9Enabled() || !AxsDialApplicationActive ||
                    [objc_getAssociatedObject(currentController, &AxsDialT9SuppressedKey) boolValue]) return;
                NSUInteger currentGeneration = [objc_getAssociatedObject(currentController, &AxsDialT9GenerationKey) unsignedIntegerValue];
                if (currentGeneration != generation) return;
                objc_setAssociatedObject(currentController, &AxsDialT9ForceRetryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                AxsDialRefreshT9(currentController);
            });
            return;
        }
        if (!AxsDialApplicationActive) return;
        objc_setAssociatedObject(weakController, &AxsDialT9RetryCountKey, @0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray *results = AxsDialFindCandidates(contacts, digits);
            dispatch_async(dispatch_get_main_queue(), ^{
                id strongController = weakController;
                if (!strongController || !AxsDialApplicationActive || !AxsDialT9Enabled() ||
                    [objc_getAssociatedObject(strongController, &AxsDialT9SuppressedKey) boolValue]) return;
                NSUInteger current = [objc_getAssociatedObject(strongController, &AxsDialT9GenerationKey) unsignedIntegerValue];
                if (current != generation) return;
                AxsDialShowCandidates(strongController, results);
            });
        });
    });
}

static BOOL AxsDialMethodHasSignature(Class cls, SEL selector, NSUInteger argumentCount,
                                      BOOL lastArgumentMustBeObject, BOOL lastArgumentMustBeBool) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (!signature || signature.numberOfArguments != argumentCount) return NO;
    const char *returnType = signature.methodReturnType;
    if (!returnType || returnType[0] != 'v') return NO;
    if (lastArgumentMustBeObject) {
        const char *type = [signature getArgumentTypeAtIndex:argumentCount - 1];
        if (!type || type[0] != '@') return NO;
    }
    if (lastArgumentMustBeBool) {
        const char *type = [signature getArgumentTypeAtIndex:argumentCount - 1];
        if (!type || (type[0] != 'B' && type[0] != 'c')) return NO;
    }
    return YES;
}

static void AxsDialRefreshLater(id controller) {
    __weak id weakController = controller;
    dispatch_async(dispatch_get_main_queue(), ^{
        id strongController = weakController;
        if (strongController) AxsDialRefreshT9(strongController);
    });
}

%group AxsSpringTwelveDialGroup
%hook DialerController

- (void)viewDidLoad {
    %orig;
    if (AxsDialControllers) [AxsDialControllers addObject:self];
    __weak id weakController = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id controller = weakController;
        if (!controller) return;
        AxsDialEnsureT9Observer(controller, AxsDialPart(controller, @"lcdView"));
        AxsDialRefreshT9(controller);
    });
}

- (void)viewDidLayoutSubviews {
    AxsDialRestoreDeleteButton(self);
    %orig;
    AxsDialUpdateDualButtons(self);
    AxsDialEnsureT9Observer(self, AxsDialPart(self, @"lcdView"));
    AxsDialRefreshT9(self);
    AxsDialLayoutT9Bar(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    [AxsDialControllers addObject:self];
    AxsDialUpdateDualButtons(self);
    objc_setAssociatedObject(self, &AxsDialT9SuppressedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &AxsDialT9QueryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    AxsDialRefreshT9(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    [AxsDialControllers addObject:self];
    AxsDialUpdateDualButtons(self);
    // Sender identities may finish loading after the first appearance callback.
    // One visible-page follow-up, not an unbounded layout/retry loop.
    __weak id weakController = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id controller = weakController;
        if (controller && [controller isViewLoaded] && ((UIViewController *)controller).view.window)
            AxsDialUpdateDualButtons(controller);
    });
    objc_setAssociatedObject(self, &AxsDialT9SuppressedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &AxsDialT9QueryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    AxsDialRefreshT9(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig(animated);
    objc_setAssociatedObject(self, &AxsDialT9SuppressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSUInteger generation = [objc_getAssociatedObject(self, &AxsDialT9GenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(self, &AxsDialT9GenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    AxsDialShowCandidates(self, @[]);
}

%new
- (void)axs_springtwelve_dualSimTapped:(UIButton *)sender {
    if (!AxsDialDualEnabled()) return;
    id identity = objc_getAssociatedObject(sender, &AxsDialIdentityKey);
    if (!identity) return;
    SEL dialSelector = NSSelectorFromString(@"axs_springtwelve_dialIdentity:");
    if ([(id)self respondsToSelector:dialSelector])
        ((void (*)(id, SEL, id))objc_msgSend)(self, dialSelector, identity);
}

%new
- (void)axs_springtwelve_dialIdentity:(id)identity {
    if (!identity) return;
    id provider = AxsDialGet(self, @"defaultCallProvider");
    SEL action = NSSelectorFromString(@"performCallActionForCallProvider:video:senderIdentity:");
    if (![(id)self respondsToSelector:action] || !provider) return;
    @try {
        ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(self, action, provider, NO, identity);
    } @catch (__unused NSException *exception) { }
}

%new
- (void)axs_springtwelve_dialerTextChanged:(id)sender {
    AxsDialRefreshLater(self);
}

%new
- (void)axs_springtwelve_t9CandidateTapped:(UIButton *)sender {
    if (!AxsDialT9Enabled()) return;
    NSArray *results = objc_getAssociatedObject(self, &AxsDialT9ResultsKey);
    if (![results isKindOfClass:[NSArray class]] || sender.tag < 0 ||
        (NSUInteger)sender.tag >= results.count) return;
    NSDictionary *candidate = results[(NSUInteger)sender.tag];
    NSString *phone = [candidate[@"phone"] isKindOfClass:[NSString class]] ? candidate[@"phone"] : nil;
    UIView *lcdView = AxsDialPart(self, @"lcdView");
    if (!phone.length || !lcdView) return;
    NSUInteger generation = [objc_getAssociatedObject(self, &AxsDialT9GenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(self, &AxsDialT9GenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &AxsDialT9QueryKey, AxsDialASCIIOnlyDigits(phone), OBJC_ASSOCIATION_COPY_NONATOMIC);
    AxsDialShowCandidates(self, @[]);
    SEL formattedSetter = NSSelectorFromString(@"setText:needsFormat:");
    if ([lcdView respondsToSelector:formattedSetter]) {
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(lcdView, formattedSetter, phone, YES);
    }
}

%end
%end

%group AxsSpringTwelveDialTextGroup
%hook DialerController
- (void)dialerViewTextDidChange:(id)sender {
    %orig(sender);
    AxsDialRefreshLater(self);
}
%end
%end

%group AxsSpringTwelveDialAppendGroup
%hook DialerController
- (void)phonePad:(id)phonePad appendString:(id)string playDTMFTone:(BOOL)playDTMFTone {
    %orig(phonePad, string, playDTMFTone);
    AxsDialRefreshLater(self);
}
%end
%end

%group AxsSpringTwelveDialDeleteVisibilityGroup
%hook DialerController
- (void)showOrHideDeleteButton {
    AxsDialRestoreDeleteButton(self);
    %orig;
    if (!AxsDialDualEnabled() ||
        [objc_getAssociatedObject(self, &AxsDialDeleteLayoutPendingKey) boolValue]) return;
    objc_setAssociatedObject(self, &AxsDialDeleteLayoutPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak id weakController = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        id controller = weakController;
        if (!controller) return;
        AxsDialUpdateDualButtons(controller);
        objc_setAssociatedObject(controller, &AxsDialDeleteLayoutPendingKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}
%end
%end

%group AxsSpringTwelveDialDeleteGroup
%hook DialerController
- (void)phonePadDeleteLastDigit:(id)sender {
    %orig(sender);
    AxsDialRefreshLater(self);
}
%end
%end

static BOOL AxsSpringTwelveDialInstalled;
static void AxsSpringTwelveDialInstall(void) {
    if (AxsSpringTwelveDialInstalled) return;
    CFStringRef bundleID = CFBundleGetIdentifier(CFBundleGetMainBundle());
    if (!bundleID || !CFEqual(bundleID, CFSTR("com.apple.mobilephone"))) return;
    Class dialerClass = NSClassFromString(@"DialerController");
    SEL loadSelector = @selector(viewDidLoad);
    SEL layoutSelector = @selector(viewDidLayoutSubviews);
    if (!dialerClass) {
        NSLog(@"[SpringTwelve:T9] DialerController missing");
        return;
    }
    if (!class_getInstanceMethod(dialerClass, loadSelector) ||
        !class_getInstanceMethod(dialerClass, layoutSelector)) {
        NSLog(@"[SpringTwelve:T9] required lifecycle selector missing");
        return;
    }

    %init(AxsSpringTwelveDialGroup);
    AxsSpringTwelveDialInstalled = YES;

    SEL textChanged = NSSelectorFromString(@"dialerViewTextDidChange:");
    BOOL hasTextChanged = AxsDialMethodHasSignature(dialerClass, textChanged, 3, YES, NO);
    if (hasTextChanged) %init(AxsSpringTwelveDialTextGroup);
    SEL append = NSSelectorFromString(@"phonePad:appendString:playDTMFTone:");
    BOOL hasAppend = AxsDialMethodHasSignature(dialerClass, append, 5, NO, YES);
    if (hasAppend) %init(AxsSpringTwelveDialAppendGroup);
    SEL deleteDigit = NSSelectorFromString(@"phonePadDeleteLastDigit:");
    BOOL hasDelete = AxsDialMethodHasSignature(dialerClass, deleteDigit, 3, YES, NO);
    if (hasDelete) %init(AxsSpringTwelveDialDeleteGroup);
    SEL deleteVisibility = NSSelectorFromString(@"showOrHideDeleteButton");
    BOOL hasDeleteVisibility = AxsDialMethodHasSignature(dialerClass, deleteVisibility, 2, NO, NO);
    if (hasDeleteVisibility) %init(AxsSpringTwelveDialDeleteVisibilityGroup);
    NSLog(@"[SpringTwelve:T9] hooks installed class=%@ text=%d append=%d delete=%d deleteVisibility=%d",
          NSStringFromClass(dialerClass), hasTextChanged, hasAppend, hasDelete, hasDeleteVisibility);
}

static void AxsDialPreferencesChanged(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ AxsDialPreferencesChanged(); });
        return;
    }
    for (id controller in AxsDialControllers.allObjects) {
        AxsDialUpdateDualButtons(controller);
        objc_setAssociatedObject(controller, &AxsDialT9QueryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSUInteger generation = [objc_getAssociatedObject(controller, &AxsDialT9GenerationKey) unsignedIntegerValue] + 1;
        objc_setAssociatedObject(controller, &AxsDialT9GenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        AxsDialRefreshT9(controller);
        AxsDialLayoutT9Bar(controller);
    }
}

static void AxsDialApplicationWillResignActive(void) {
    AxsDialApplicationActive = NO;
    for (id controller in AxsDialControllers.allObjects) {
        NSUInteger generation = [objc_getAssociatedObject(controller, &AxsDialT9GenerationKey) unsignedIntegerValue] + 1;
        objc_setAssociatedObject(controller, &AxsDialT9GenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        AxsDialShowCandidates(controller, @[]);
    }
    NSLog(@"[SpringTwelve:T9] app inactive; suggestions hidden");
}

static void AxsDialApplicationDidBecomeActive(void) {
    AxsDialApplicationActive = YES;
    NSLog(@"[SpringTwelve:T9] app active; refreshing dialer");
    for (id controller in AxsDialControllers.allObjects) {
        if ([objc_getAssociatedObject(controller, &AxsDialT9SuppressedKey) boolValue]) continue;
        if (![controller isViewLoaded] || ((UIViewController *)controller).view.window == nil) continue;
        AxsDialUpdateDualButtons(controller);
        objc_setAssociatedObject(controller, &AxsDialT9QueryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, &AxsDialT9RetryCountKey, @0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        AxsDialRefreshT9(controller);
    }
}

static void AxsSpringTwelveDialImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)header;
    (void)slide;
    dispatch_async(dispatch_get_main_queue(), ^{ AxsSpringTwelveDialInstall(); });
}

%ctor {
    CFStringRef bundleID = CFBundleGetIdentifier(CFBundleGetMainBundle());
    if (!bundleID || !CFEqual(bundleID, CFSTR("com.apple.mobilephone"))) return;
    AxsDialControllers = [NSHashTable weakObjectsHashTable];
    AxsDialApplicationActive = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(__unused NSNotification *note) { AxsDialApplicationWillResignActive(); }];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(__unused NSNotification *note) { AxsDialApplicationDidBecomeActive(); }];
    [center addObserverForName:@"com.axs.springtwelve.preferences-changed"
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            AxsDialPreferencesChanged();
        }];
    [[NSNotificationCenter defaultCenter] addObserverForName:@"CNContactStoreDidChangeNotification"
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            dispatch_async(AxsDialContactsQueue(), ^{
                AxsDialContactCache = nil;
                AxsDialContactCacheReady = NO;
                AxsDialContactRetryAfter = 0.0;
                AxsDialContactLoadStarted = NO;
            });
            AxsDialPreferencesChanged();
        }];
    _dyld_register_func_for_add_image(AxsSpringTwelveDialImageAdded);
    dispatch_async(dispatch_get_main_queue(), ^{ AxsSpringTwelveDialInstall(); });
}
