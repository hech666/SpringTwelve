#import "HaogeSpringTwelveSwitches.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <string.h>
#include <atomic>

#pragma mark - Dynamic access and associated state

static char HaogeDialDualButtonsKey;
static char HaogeDialDualHostKey;
static char HaogeDialT9BarKey;
static char HaogeDialT9ScrollKey;
static char HaogeDialT9ResultsKey;
static char HaogeDialT9ObservedLCDKey;
static char HaogeDialT9QueryKey;
static char HaogeDialT9GenerationKey;
static char HaogeDialT9RetryCountKey;
static char HaogeDialT9ForceRetryKey;
static char HaogeDialOriginalButtonKey;
static char HaogeDialOriginalHiddenKey;
static char HaogeDialDeleteButtonKey;
static char HaogeDialDeleteTransformKey;
static char HaogeDialDeleteLayoutPendingKey;
static char HaogeDialIdentityKey;

static id HaogeDialGet(id object, NSString *name) {
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
static UIView *HaogeDialPart(id controller, NSString *name) {
    id part = HaogeDialGet(HaogeDialGet(controller, @"dialerView"), name);
    if (![part isKindOfClass:[UIView class]]) part = HaogeDialGet(controller, name);
    return [part isKindOfClass:[UIView class]] ? part : nil;
}

static NSArray *HaogeDialIdentities(id controller) {
    id values = HaogeDialGet(HaogeDialGet(controller, @"defaultCallProvider"), @"prioritizedSenderIdentities");
    if (![values isKindOfClass:[NSArray class]]) values = HaogeDialGet(values, @"allObjects");
    if (![values isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *real = [NSMutableArray array];
    for (id value in values) {
        if (value && value != [NSNull null] && ![value isKindOfClass:[NSString class]] &&
            ![value isKindOfClass:[NSNumber class]]) [real addObject:value];
    }
    return [real copy];
}

static BOOL HaogeDialDualEnabled(void) {
    return HaogeSpringTwelveOn(@"captureDualSimDialerEnabled");
}

static BOOL HaogeDialT9Enabled(void) {
    return HaogeSpringTwelveOn(@"captureT9DialerEnabled");
}

static void HaogeDialRemoveT9Observer(id controller) {
    id oldLCD = objc_getAssociatedObject(controller, &HaogeDialT9ObservedLCDKey);
    if (!oldLCD) return;
    SEL removeTarget = @selector(removeTarget:action:forControlEvents:);
    if ([oldLCD respondsToSelector:removeTarget]) {
        ((void (*)(id, SEL, id, SEL, UIControlEvents))objc_msgSend)(
            oldLCD, removeTarget, controller,
            @selector(haoge_springtwelve_dialerTextChanged:), UIControlEventEditingChanged);
    }
    [[NSNotificationCenter defaultCenter] removeObserver:controller
        name:UITextFieldTextDidChangeNotification object:oldLCD];
    objc_setAssociatedObject(controller, &HaogeDialT9ObservedLCDKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void HaogeDialEnsureT9Observer(id controller, id lcdView) {
    if (!HaogeDialT9Enabled() || !lcdView) {
        HaogeDialRemoveT9Observer(controller);
        return;
    }
    id previous = objc_getAssociatedObject(controller, &HaogeDialT9ObservedLCDKey);
    if (previous == lcdView) return;
    HaogeDialRemoveT9Observer(controller);

    SEL addTarget = @selector(addTarget:action:forControlEvents:);
    if ([lcdView respondsToSelector:addTarget]) {
        ((void (*)(id, SEL, id, SEL, UIControlEvents))objc_msgSend)(
            lcdView, addTarget, controller,
            @selector(haoge_springtwelve_dialerTextChanged:), UIControlEventEditingChanged);
    }
    [[NSNotificationCenter defaultCenter] addObserver:controller
        selector:@selector(haoge_springtwelve_dialerTextChanged:)
        name:UITextFieldTextDidChangeNotification object:lcdView];
    objc_setAssociatedObject(controller, &HaogeDialT9ObservedLCDKey, lcdView,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Dual-SIM call controls

static void HaogeDialRestoreDeleteButton(id controller) {
    UIView *button = objc_getAssociatedObject(controller, &HaogeDialDeleteButtonKey);
    NSArray<NSValue *> *transforms = objc_getAssociatedObject(controller, &HaogeDialDeleteTransformKey);
    if (button && transforms.count == 2 &&
        CGAffineTransformEqualToTransform(button.transform, transforms[1].CGAffineTransformValue)) {
        [UIView performWithoutAnimation:^{ button.transform = transforms[0].CGAffineTransformValue; }];
    }
    objc_setAssociatedObject(controller, &HaogeDialDeleteButtonKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &HaogeDialDeleteTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Move the actual control, not a copy: native targets, gestures and visibility stay intact.
static BOOL HaogeDialPositionDeleteButton(id controller, UIView *button, UIView *host, CGRect row) {
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
    objc_setAssociatedObject(controller, &HaogeDialDeleteButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &HaogeDialDeleteTransformKey,
                             @[[NSValue valueWithCGAffineTransform:base],
                               [NSValue valueWithCGAffineTransform:moved]], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView performWithoutAnimation:^{ button.transform = moved; }];
    return YES;
}

static void HaogeDialRemoveDualButtons(id controller) {
    HaogeDialRestoreDeleteButton(controller);
    NSArray *buttons = objc_getAssociatedObject(controller, &HaogeDialDualButtonsKey);
    for (id button in buttons) {
        if ([button isKindOfClass:[UIView class]]) [button removeFromSuperview];
    }
    id originalButton = objc_getAssociatedObject(controller, &HaogeDialOriginalButtonKey);
    NSNumber *wasHidden = objc_getAssociatedObject(controller, &HaogeDialOriginalHiddenKey);
    if ([originalButton isKindOfClass:[UIView class]] && wasHidden)
        ((UIView *)originalButton).hidden = wasHidden.boolValue;
    objc_setAssociatedObject(controller, &HaogeDialDualButtonsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &HaogeDialDualHostKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &HaogeDialOriginalButtonKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &HaogeDialOriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSString *HaogeDialIdentityTitle(id identity, NSUInteger index) {
    // Prefer the short, display-appropriate name; localizedName can be a long
    // format (e.g. a full number or a verbose label) that truncates to "…".
    NSString *title = HaogeDialGet(identity, @"localizedShortName");
    if (![title isKindOfClass:[NSString class]] || !title.length)
        title = HaogeDialGet(identity, @"localizedName");
    if (![title isKindOfClass:[NSString class]] || !title.length ||
        title.length > 4) {
        title = index == 0 ? @"卡一" : @"卡二";
    }
    return title;
}

static void HaogeDialUpdateDualButtons(id controller) {
    HaogeDialRestoreDeleteButton(controller);
    UIView *callButton = HaogeDialPart(controller, @"callButton");
    UIView *host = HaogeDialGet(controller, @"dialerView");
    if (![host isKindOfClass:UIView.class] || ![callButton isDescendantOfView:host])
        host = callButton.superview;
    NSArray *identities = HaogeDialIdentities(controller);
    if (!HaogeDialDualEnabled() || identities.count < 2 || !callButton.superview || !host ||
        CGRectGetWidth(callButton.bounds) < 20.0 || CGRectGetHeight(callButton.bounds) < 20.0) {
        HaogeDialRemoveDualButtons(controller);
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
    UIView *deleteButton = HaogeDialPart(controller, @"deleteButton");
    CGFloat controlsHeight = height;
    if (deleteButton) {
        if (![deleteButton isDescendantOfView:host] || [deleteButton isDescendantOfView:callButton]) {
            HaogeDialRemoveDualButtons(controller);
            return;
        }
        CGRect deleteRect = [deleteButton convertRect:deleteButton.bounds toView:host];
        if (CGRectIsEmpty(deleteRect) || CGRectIsInfinite(deleteRect)) {
            HaogeDialRemoveDualButtons(controller);
            return;
        }
        controlsHeight += 8.0 + MAX(44.0, CGRectGetHeight(deleteRect));
    }
    // Do not shift above the native call row into the numeric keypad.
    CGFloat minimumY = MAX(CGRectGetMinY(available), CGRectGetMinY(anchor));
    CGFloat maximumY = CGRectGetMaxY(available) - controlsHeight;
    if (CGRectIsEmpty(anchor) || CGRectIsInfinite(anchor) || width < 96.0 || minimumY > maximumY) {
        HaogeDialRemoveDualButtons(controller);
        return;
    }
    CGFloat x = MIN(MAX(CGRectGetMidX(anchor) - totalWidth / 2.0, CGRectGetMinX(available) + 12.0),
                    CGRectGetMaxX(available) - totalWidth - 12.0);
    CGFloat y = MIN(MAX(CGRectGetMidY(anchor) - height / 2.0, minimumY), maximumY);

    NSArray *buttons = objc_getAssociatedObject(controller, &HaogeDialDualButtonsKey);
    id oldCallButton = objc_getAssociatedObject(controller, &HaogeDialOriginalButtonKey);
    id oldHost = objc_getAssociatedObject(controller, &HaogeDialDualHostKey);
    if (![buttons isKindOfClass:[NSArray class]] || buttons.count != 2 ||
        oldCallButton != callButton || oldHost != host) {
        HaogeDialRemoveDualButtons(controller);
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
            [button addTarget:controller action:@selector(haoge_springtwelve_dualSimTapped:)
             forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(button, &HaogeDialIdentityKey, identities[index],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [host addSubview:button];
            [created addObject:button];
        }
        buttons = [created copy];
        objc_setAssociatedObject(controller, &HaogeDialDualButtonsKey, buttons, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, &HaogeDialDualHostKey, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, &HaogeDialOriginalButtonKey, callButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, &HaogeDialOriginalHiddenKey, @(originalHidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    callButton.hidden = YES; // Phone may restore the native button during layout.
    for (NSUInteger index = 0; index < 2; index++) {
        UIButton *button = buttons[index];
        id identity = identities[index];
        objc_setAssociatedObject(button, &HaogeDialIdentityKey, identity, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        button.frame = CGRectMake(x + index * (width + gap), y, width, height);
        button.layer.cornerRadius = height / 2.0;
        [button setTitle:HaogeDialIdentityTitle(identity, index) forState:UIControlStateNormal];
        button.accessibilityLabel = HaogeDialIdentityTitle(identity, index);
        button.hidden = NO;
        [host bringSubviewToFront:button];
    }
    if (deleteButton && !HaogeDialPositionDeleteButton(controller, deleteButton, host,
                                                     CGRectMake(x, y, totalWidth, height))) {
        HaogeDialRemoveDualButtons(controller);
    }
}

#pragma mark - T9 contact indexing

static dispatch_queue_t HaogeDialContactsQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.haoge.springtwelve.dialer.contacts", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSArray *HaogeDialContactCache;
static NSMutableArray *HaogeDialContactWaiters;
static BOOL HaogeDialContactLoadStarted;
static BOOL HaogeDialContactCacheReady;
static NSTimeInterval HaogeDialContactRetryAfter;
static NSHashTable *HaogeDialControllers;
static char HaogeDialT9SuppressedKey;
static std::atomic<bool> HaogeDialApplicationActive{false};

static BOOL HaogeDialIsApplicationActive(void) {
    return HaogeDialApplicationActive.load(std::memory_order_acquire);
}

static void HaogeDialFinishContactLoad(NSArray *contacts) {
    BOOL success = contacts != nil;
    if (success) {
        HaogeDialContactCache = [contacts copy];
        HaogeDialContactCacheReady = YES;
        HaogeDialContactRetryAfter = 0.0;
    } else {
        HaogeDialContactCache = @[];
        HaogeDialContactCacheReady = NO;
        HaogeDialContactRetryAfter = NSProcessInfo.processInfo.systemUptime + 5.0;
    }
    NSLog(@"[SpringTwelve:T9] contacts %@ count=%lu",
          success ? @"loaded" : @"failed",
          (unsigned long)(success ? HaogeDialContactCache.count : 0));
    HaogeDialContactLoadStarted = NO;
    NSArray *waiters = [HaogeDialContactWaiters copy] ?: @[];
    [HaogeDialContactWaiters removeAllObjects];
    NSArray *result = HaogeDialContactCache ?: @[];
    for (id waiterObject in waiters) {
        void (^waiter)(NSArray *, BOOL) = waiterObject;
        dispatch_async(dispatch_get_main_queue(), ^{ waiter(result, success); });
    }
}

static void HaogeDialFetchContacts(id store) {
    @try {
        Class requestClass = NSClassFromString(@"CNContactFetchRequest");
        if (!requestClass || ![requestClass instancesRespondToSelector:@selector(initWithKeysToFetch:)]) {
            HaogeDialFinishContactLoad(nil);
            return;
        }
        NSArray *keys = @[@"givenName", @"familyName", @"middleName", @"nickname",
                          @"organizationName", @"phoneNumbers"];
        id request = ((id (*)(id, SEL, id))objc_msgSend)(
            [requestClass alloc], @selector(initWithKeysToFetch:), keys);
        SEL enumerate = NSSelectorFromString(@"enumerateContactsWithFetchRequest:error:usingBlock:");
        if (!request || ![store respondsToSelector:enumerate]) {
            HaogeDialFinishContactLoad(nil);
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
        HaogeDialFinishContactLoad(success && !error ? contacts : nil);
    } @catch (NSException *exception) {
        NSLog(@"[SpringTwelve:T9] enumeration exception=%@", exception.name);
        HaogeDialFinishContactLoad(nil);
    }
}

static void HaogeDialLoadContacts(void (^completion)(NSArray *, BOOL)) {
    if (!completion) return;
    dispatch_async(HaogeDialContactsQueue(), ^{
        if (!HaogeDialContactWaiters) HaogeDialContactWaiters = [NSMutableArray array];
        if (!HaogeDialIsApplicationActive()) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], NO); });
            return;
        }
        if (HaogeDialContactCacheReady) {
            NSArray *cached = HaogeDialContactCache ?: @[];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(cached, YES); });
            return;
        }
        if (HaogeDialContactRetryAfter > NSProcessInfo.processInfo.systemUptime) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], NO); });
            return;
        }
        [HaogeDialContactWaiters addObject:[completion copy]];
        if (HaogeDialContactLoadStarted) return;
        HaogeDialContactLoadStarted = YES;

        // Do not request access here. Contacts.framework enforces the access
        // available to the host process; absence of a prompt is not a bypass.
        @try {
            void *contactsHandle = dlopen("/System/Library/Frameworks/Contacts.framework/Contacts", RTLD_LAZY);
            Class storeClass = NSClassFromString(@"CNContactStore");
            NSLog(@"[SpringTwelve:T9] contacts framework=%d storeClass=%d",
                  contactsHandle != NULL, storeClass != Nil);
            if (!storeClass) {
                HaogeDialFinishContactLoad(nil);
                return;
            }
            id store = [[storeClass alloc] init];
            if (!store) {
                HaogeDialFinishContactLoad(nil);
                return;
            }
            HaogeDialFetchContacts(store);
        } @catch (__unused NSException *exception) {
            HaogeDialFinishContactLoad(nil);
        }
    });
}

static NSString *HaogeDialASCIIOnlyDigits(NSString *source) {
    if (![source isKindOfClass:[NSString class]] || source.length == 0) return @"";
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger index = 0; index < source.length; index++) {
        unichar ch = [source characterAtIndex:index];
        if (ch >= '0' && ch <= '9') [digits appendFormat:@"%C", ch];
    }
    return digits;
}

static NSString *HaogeDialNormalizedLatin(NSString *source) {
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

static unichar HaogeDialT9DigitForLetter(unichar letter) {
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

static NSString *HaogeDialT9Code(NSString *normalized, BOOL initialsOnly) {
    NSMutableString *code = [NSMutableString string];
    BOOL inWord = NO;
    for (NSUInteger index = 0; index < normalized.length; index++) {
        unichar ch = [normalized characterAtIndex:index];
        if (ch >= 'a' && ch <= 'z') {
            if (!initialsOnly || !inWord) {
                unichar digit = HaogeDialT9DigitForLetter(ch);
                if (digit) [code appendFormat:@"%C", digit];
            }
            inWord = YES;
        } else {
            inWord = NO;
        }
    }
    return code;
}

static NSString *HaogeDialContactString(id contact, NSString *property) {
    id value = HaogeDialGet(contact, property);
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSArray *HaogeDialContactPhones(id contact) {
    id value = HaogeDialGet(contact, @"phoneNumbers");
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static NSString *HaogeDialPhoneString(id labeledValue) {
    id phoneNumber = HaogeDialGet(labeledValue, @"value");
    id value = HaogeDialGet(phoneNumber, @"stringValue");
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static BOOL HaogeDialContactMatches(id contact, NSString *digits, BOOL *nameMatched) {
    if (nameMatched) *nameMatched = NO;
    BOOL matchedByName = NO;
    NSString *family = HaogeDialContactString(contact, @"familyName");
    NSString *given = HaogeDialContactString(contact, @"givenName");
    NSString *middle = HaogeDialContactString(contact, @"middleName");
    NSString *nickname = HaogeDialContactString(contact, @"nickname");
    NSString *organization = HaogeDialContactString(contact, @"organizationName");
    NSString *full = [NSString stringWithFormat:@"%@%@%@%@", family, given, middle, nickname];
    if (!full.length) full = organization;
    if (full.length) {
        NSString *normalized = HaogeDialNormalizedLatin(full);
        matchedByName = [HaogeDialT9Code(normalized, NO) hasPrefix:digits] ||
                        [HaogeDialT9Code(normalized, YES) hasPrefix:digits];
    }
    if (nameMatched) *nameMatched = matchedByName;
    // Phone digits are deliberately not a search field; T9 matches only name prefixes.
    return matchedByName;
}

static NSArray *HaogeDialFindCandidates(NSArray *contacts, NSString *digits) {
    if (!digits.length || !contacts.count) return @[];
    NSMutableArray *matches = [NSMutableArray arrayWithCapacity:8];
    for (id contact in contacts) {
        if (!HaogeDialContactMatches(contact, digits, NULL)) continue;
        NSString *family = HaogeDialContactString(contact, @"familyName");
        NSString *given = HaogeDialContactString(contact, @"givenName");
        NSString *middle = HaogeDialContactString(contact, @"middleName");
        NSString *nickname = HaogeDialContactString(contact, @"nickname");
        NSString *name = [NSString stringWithFormat:@"%@%@%@%@", family, given, middle, nickname];
        if (!name.length) name = HaogeDialContactString(contact, @"organizationName");
        if (!name.length) continue;
        NSArray *phones = HaogeDialContactPhones(contact);
        NSString *phone = phones.count ? HaogeDialPhoneString(phones[0]) : @"";
        if (!phone.length) continue;
        [matches addObject:@{@"name": name, @"phone": phone}];
        if (matches.count >= 8) break;
    }
    return [matches copy];
}

#pragma mark - T9 suggestion view

static void HaogeDialLayoutT9Bar(id controller) {
    UIView *bar = objc_getAssociatedObject(controller, &HaogeDialT9BarKey);
    if (![bar isKindOfClass:[UIView class]]) return;
    UIView *dialerView = HaogeDialGet(controller, @"dialerView");
    UIView *lcdView = HaogeDialPart(controller, @"lcdView");
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
    UIView *phonePad = HaogeDialPart(controller, @"phonePadView");
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
    UIScrollView *scroll = objc_getAssociatedObject(controller, &HaogeDialT9ScrollKey);
    if ([scroll isKindOfClass:[UIScrollView class]]) scroll.frame = bar.bounds;

    NSArray *results = objc_getAssociatedObject(controller, &HaogeDialT9ResultsKey);
    NSString *query = objc_getAssociatedObject(controller, &HaogeDialT9QueryKey);
    BOOL suppressed = [objc_getAssociatedObject(controller, &HaogeDialT9SuppressedKey) boolValue];
    BOOL visible = HaogeDialApplicationActive && HaogeDialT9Enabled() && !suppressed && query.length > 0 && results.count > 0 &&
                   [controller isViewLoaded] && ((UIViewController *)controller).view.window != nil;
    bar.hidden = !visible;
    if (visible) [host bringSubviewToFront:bar];
}

static void HaogeDialShowCandidates(id controller, NSArray *candidates) {
    NSArray *safeCandidates = [candidates isKindOfClass:[NSArray class]] ? candidates : @[];
    objc_setAssociatedObject(controller, &HaogeDialT9ResultsKey, safeCandidates,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *dialerView = HaogeDialGet(controller, @"dialerView");
    if (![dialerView isKindOfClass:[UIView class]]) return;

    UIView *bar = objc_getAssociatedObject(controller, &HaogeDialT9BarKey);
    UIScrollView *scroll = objc_getAssociatedObject(controller, &HaogeDialT9ScrollKey);
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
        objc_setAssociatedObject(controller, &HaogeDialT9BarKey, bar,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, &HaogeDialT9ScrollKey, scroll,
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
        [button addTarget:controller action:@selector(haoge_springtwelve_t9CandidateTapped:)
         forControlEvents:UIControlEventTouchUpInside];
        button.frame = CGRectMake(index * (buttonWidth + gap), 2.0, buttonWidth, 34.0);
        [scroll addSubview:button];
    }];
    scroll.contentSize = CGSizeMake(safeCandidates.count ? safeCandidates.count * (buttonWidth + gap) - gap : 0.0, 38.0);
    NSLog(@"[SpringTwelve:T9] candidateCount=%lu", (unsigned long)safeCandidates.count);
    bar.hidden = !HaogeDialT9Enabled() || safeCandidates.count == 0;
    HaogeDialLayoutT9Bar(controller);
    if (!bar.hidden) [dialerView bringSubviewToFront:bar];
}

static void HaogeDialRefreshT9(id controller) {
    if (![NSThread isMainThread]) {
        __weak id weakController = controller;
        dispatch_async(dispatch_get_main_queue(), ^{
            id strongController = weakController;
            if (strongController) HaogeDialRefreshT9(strongController);
        });
        return;
    }
    if (!HaogeDialT9Enabled()) {
        HaogeDialRemoveT9Observer(controller);
        UIView *bar = objc_getAssociatedObject(controller, &HaogeDialT9BarKey);
        bar.hidden = YES;
        objc_setAssociatedObject(controller, &HaogeDialT9QueryKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSUInteger generation = [objc_getAssociatedObject(controller, &HaogeDialT9GenerationKey) unsignedIntegerValue] + 1;
        objc_setAssociatedObject(controller, &HaogeDialT9GenerationKey, @(generation),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (!HaogeDialApplicationActive) {
        UIView *bar = objc_getAssociatedObject(controller, &HaogeDialT9BarKey);
        bar.hidden = YES;
        return;
    }
    if ([objc_getAssociatedObject(controller, &HaogeDialT9SuppressedKey) boolValue]) {
        UIView *bar = objc_getAssociatedObject(controller, &HaogeDialT9BarKey);
        bar.hidden = YES;
        return;
    }
    id lcdView = HaogeDialPart(controller, @"lcdView");
    HaogeDialEnsureT9Observer(controller, lcdView);
    NSString *text = HaogeDialGet(lcdView, @"text");
    NSString *digits = HaogeDialASCIIOnlyDigits(text);
    NSString *previous = objc_getAssociatedObject(controller, &HaogeDialT9QueryKey);
    BOOL forced = [objc_getAssociatedObject(controller, &HaogeDialT9ForceRetryKey) boolValue];
    if ([previous isEqualToString:digits] && !forced) return;
    objc_setAssociatedObject(controller, &HaogeDialT9ForceRetryKey, @NO,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (![previous isEqualToString:digits]) {
        objc_setAssociatedObject(controller, &HaogeDialT9RetryCountKey, @0,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSLog(@"[SpringTwelve:T9] input changed digitsLength=%lu", (unsigned long)digits.length);

    NSUInteger generation = [objc_getAssociatedObject(controller, &HaogeDialT9GenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(controller, &HaogeDialT9GenerationKey, @(generation),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &HaogeDialT9QueryKey, digits,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (!digits.length) {
        HaogeDialShowCandidates(controller, @[]);
        return;
    }
    HaogeDialShowCandidates(controller, @[]);

    __weak id weakController = controller;
    HaogeDialLoadContacts(^(NSArray *contacts, BOOL loaded) {
        id requestController = weakController;
        if (!requestController) return;
        if (!loaded) {
            NSUInteger retryCount = [objc_getAssociatedObject(requestController, &HaogeDialT9RetryCountKey) unsignedIntegerValue] + 1;
            objc_setAssociatedObject(requestController, &HaogeDialT9RetryCountKey, @(retryCount), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSLog(@"[SpringTwelve:T9] contact load failed retry=%lu/2", (unsigned long)retryCount);
            if (retryCount > 2) return;
            __weak id retryController = weakController;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                id currentController = retryController;
                if (!currentController || !HaogeDialT9Enabled() || !HaogeDialApplicationActive ||
                    [objc_getAssociatedObject(currentController, &HaogeDialT9SuppressedKey) boolValue]) return;
                NSUInteger currentGeneration = [objc_getAssociatedObject(currentController, &HaogeDialT9GenerationKey) unsignedIntegerValue];
                if (currentGeneration != generation) return;
                objc_setAssociatedObject(currentController, &HaogeDialT9ForceRetryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                HaogeDialRefreshT9(currentController);
            });
            return;
        }
        if (!HaogeDialApplicationActive) return;
        objc_setAssociatedObject(weakController, &HaogeDialT9RetryCountKey, @0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray *results = HaogeDialFindCandidates(contacts, digits);
            dispatch_async(dispatch_get_main_queue(), ^{
                id strongController = weakController;
                if (!strongController || !HaogeDialApplicationActive || !HaogeDialT9Enabled() ||
                    [objc_getAssociatedObject(strongController, &HaogeDialT9SuppressedKey) boolValue]) return;
                NSUInteger current = [objc_getAssociatedObject(strongController, &HaogeDialT9GenerationKey) unsignedIntegerValue];
                if (current != generation) return;
                HaogeDialShowCandidates(strongController, results);
            });
        });
    });
}

static BOOL HaogeDialMethodHasSignature(Class cls, SEL selector, NSUInteger argumentCount,
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

static void HaogeDialRefreshLater(id controller) {
    __weak id weakController = controller;
    dispatch_async(dispatch_get_main_queue(), ^{
        id strongController = weakController;
        if (strongController) HaogeDialRefreshT9(strongController);
    });
}

%group HaogeSpringTwelveDialGroup
%hook DialerController

- (void)viewDidLoad {
    %orig;
    if (HaogeDialControllers) [HaogeDialControllers addObject:self];
    __weak id weakController = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id controller = weakController;
        if (!controller) return;
        HaogeDialEnsureT9Observer(controller, HaogeDialPart(controller, @"lcdView"));
        HaogeDialRefreshT9(controller);
    });
}

- (void)viewDidLayoutSubviews {
    HaogeDialRestoreDeleteButton(self);
    %orig;
    HaogeDialUpdateDualButtons(self);
    HaogeDialEnsureT9Observer(self, HaogeDialPart(self, @"lcdView"));
    HaogeDialRefreshT9(self);
    HaogeDialLayoutT9Bar(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    [HaogeDialControllers addObject:self];
    HaogeDialUpdateDualButtons(self);
    objc_setAssociatedObject(self, &HaogeDialT9SuppressedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &HaogeDialT9QueryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    HaogeDialRefreshT9(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    [HaogeDialControllers addObject:self];
    HaogeDialUpdateDualButtons(self);
    // Sender identities may finish loading after the first appearance callback.
    // One visible-page follow-up, not an unbounded layout/retry loop.
    __weak id weakController = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id controller = weakController;
        if (controller && [controller isViewLoaded] && ((UIViewController *)controller).view.window)
            HaogeDialUpdateDualButtons(controller);
    });
    objc_setAssociatedObject(self, &HaogeDialT9SuppressedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &HaogeDialT9QueryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    HaogeDialRefreshT9(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig(animated);
    objc_setAssociatedObject(self, &HaogeDialT9SuppressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSUInteger generation = [objc_getAssociatedObject(self, &HaogeDialT9GenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(self, &HaogeDialT9GenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    HaogeDialShowCandidates(self, @[]);
}

%new
- (void)haoge_springtwelve_dualSimTapped:(UIButton *)sender {
    if (!HaogeDialDualEnabled()) return;
    id identity = objc_getAssociatedObject(sender, &HaogeDialIdentityKey);
    if (!identity) return;
    SEL dialSelector = NSSelectorFromString(@"haoge_springtwelve_dialIdentity:");
    if ([(id)self respondsToSelector:dialSelector])
        ((void (*)(id, SEL, id))objc_msgSend)(self, dialSelector, identity);
}

%new
- (void)haoge_springtwelve_dialIdentity:(id)identity {
    if (!identity) return;
    id provider = HaogeDialGet(self, @"defaultCallProvider");
    SEL action = NSSelectorFromString(@"performCallActionForCallProvider:video:senderIdentity:");
    if (![(id)self respondsToSelector:action] || !provider) return;
    @try {
        ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(self, action, provider, NO, identity);
    } @catch (__unused NSException *exception) { }
}

%new
- (void)haoge_springtwelve_dialerTextChanged:(id)sender {
    HaogeDialRefreshLater(self);
}

%new
- (void)haoge_springtwelve_t9CandidateTapped:(UIButton *)sender {
    if (!HaogeDialT9Enabled()) return;
    NSArray *results = objc_getAssociatedObject(self, &HaogeDialT9ResultsKey);
    if (![results isKindOfClass:[NSArray class]] || sender.tag < 0 ||
        (NSUInteger)sender.tag >= results.count) return;
    NSDictionary *candidate = results[(NSUInteger)sender.tag];
    NSString *phone = [candidate[@"phone"] isKindOfClass:[NSString class]] ? candidate[@"phone"] : nil;
    UIView *lcdView = HaogeDialPart(self, @"lcdView");
    if (!phone.length || !lcdView) return;
    NSUInteger generation = [objc_getAssociatedObject(self, &HaogeDialT9GenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(self, &HaogeDialT9GenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &HaogeDialT9QueryKey, HaogeDialASCIIOnlyDigits(phone), OBJC_ASSOCIATION_COPY_NONATOMIC);
    HaogeDialShowCandidates(self, @[]);
    SEL formattedSetter = NSSelectorFromString(@"setText:needsFormat:");
    if ([lcdView respondsToSelector:formattedSetter]) {
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(lcdView, formattedSetter, phone, YES);
    }
}

%end
%end

%group HaogeSpringTwelveDialTextGroup
%hook DialerController
- (void)dialerViewTextDidChange:(id)sender {
    %orig(sender);
    HaogeDialRefreshLater(self);
}
%end
%end

%group HaogeSpringTwelveDialAppendGroup
%hook DialerController
- (void)phonePad:(id)phonePad appendString:(id)string playDTMFTone:(BOOL)playDTMFTone {
    %orig(phonePad, string, playDTMFTone);
    HaogeDialRefreshLater(self);
}
%end
%end

%group HaogeSpringTwelveDialDeleteVisibilityGroup
%hook DialerController
- (void)showOrHideDeleteButton {
    HaogeDialRestoreDeleteButton(self);
    %orig;
    if (!HaogeDialDualEnabled() ||
        [objc_getAssociatedObject(self, &HaogeDialDeleteLayoutPendingKey) boolValue]) return;
    objc_setAssociatedObject(self, &HaogeDialDeleteLayoutPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak id weakController = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        id controller = weakController;
        if (!controller) return;
        HaogeDialUpdateDualButtons(controller);
        objc_setAssociatedObject(controller, &HaogeDialDeleteLayoutPendingKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}
%end
%end

%group HaogeSpringTwelveDialDeleteGroup
%hook DialerController
- (void)phonePadDeleteLastDigit:(id)sender {
    %orig(sender);
    HaogeDialRefreshLater(self);
}
%end
%end

static BOOL HaogeSpringTwelveDialInstalled;
static void HaogeSpringTwelveDialInstall(void) {
    if (HaogeSpringTwelveDialInstalled) return;
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

    %init(HaogeSpringTwelveDialGroup);
    HaogeSpringTwelveDialInstalled = YES;

    SEL textChanged = NSSelectorFromString(@"dialerViewTextDidChange:");
    BOOL hasTextChanged = HaogeDialMethodHasSignature(dialerClass, textChanged, 3, YES, NO);
    if (hasTextChanged) %init(HaogeSpringTwelveDialTextGroup);
    SEL append = NSSelectorFromString(@"phonePad:appendString:playDTMFTone:");
    BOOL hasAppend = HaogeDialMethodHasSignature(dialerClass, append, 5, NO, YES);
    if (hasAppend) %init(HaogeSpringTwelveDialAppendGroup);
    SEL deleteDigit = NSSelectorFromString(@"phonePadDeleteLastDigit:");
    BOOL hasDelete = HaogeDialMethodHasSignature(dialerClass, deleteDigit, 3, YES, NO);
    if (hasDelete) %init(HaogeSpringTwelveDialDeleteGroup);
    SEL deleteVisibility = NSSelectorFromString(@"showOrHideDeleteButton");
    BOOL hasDeleteVisibility = HaogeDialMethodHasSignature(dialerClass, deleteVisibility, 2, NO, NO);
    if (hasDeleteVisibility) %init(HaogeSpringTwelveDialDeleteVisibilityGroup);
    NSLog(@"[SpringTwelve:T9] hooks installed class=%@ text=%d append=%d delete=%d deleteVisibility=%d",
          NSStringFromClass(dialerClass), hasTextChanged, hasAppend, hasDelete, hasDeleteVisibility);
}

static void HaogeDialPreferencesChanged(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ HaogeDialPreferencesChanged(); });
        return;
    }
    for (id controller in HaogeDialControllers.allObjects) {
        HaogeDialUpdateDualButtons(controller);
        objc_setAssociatedObject(controller, &HaogeDialT9QueryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSUInteger generation = [objc_getAssociatedObject(controller, &HaogeDialT9GenerationKey) unsignedIntegerValue] + 1;
        objc_setAssociatedObject(controller, &HaogeDialT9GenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        HaogeDialRefreshT9(controller);
        HaogeDialLayoutT9Bar(controller);
    }
}

static void HaogeDialApplicationWillResignActive(void) {
    HaogeDialApplicationActive = NO;
    for (id controller in HaogeDialControllers.allObjects) {
        NSUInteger generation = [objc_getAssociatedObject(controller, &HaogeDialT9GenerationKey) unsignedIntegerValue] + 1;
        objc_setAssociatedObject(controller, &HaogeDialT9GenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        HaogeDialShowCandidates(controller, @[]);
    }
    NSLog(@"[SpringTwelve:T9] app inactive; suggestions hidden");
}

static void HaogeDialApplicationDidBecomeActive(void) {
    HaogeDialApplicationActive = YES;
    NSLog(@"[SpringTwelve:T9] app active; refreshing dialer");
    for (id controller in HaogeDialControllers.allObjects) {
        if ([objc_getAssociatedObject(controller, &HaogeDialT9SuppressedKey) boolValue]) continue;
        if (![controller isViewLoaded] || ((UIViewController *)controller).view.window == nil) continue;
        HaogeDialUpdateDualButtons(controller);
        objc_setAssociatedObject(controller, &HaogeDialT9QueryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, &HaogeDialT9RetryCountKey, @0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        HaogeDialRefreshT9(controller);
    }
}

static void HaogeSpringTwelveDialImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)header;
    (void)slide;
    dispatch_async(dispatch_get_main_queue(), ^{ HaogeSpringTwelveDialInstall(); });
}

%ctor {
    CFStringRef bundleID = CFBundleGetIdentifier(CFBundleGetMainBundle());
    if (!bundleID || !CFEqual(bundleID, CFSTR("com.apple.mobilephone"))) return;
    HaogeDialControllers = [NSHashTable weakObjectsHashTable];
    HaogeDialApplicationActive = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(__unused NSNotification *note) { HaogeDialApplicationWillResignActive(); }];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(__unused NSNotification *note) { HaogeDialApplicationDidBecomeActive(); }];
    [center addObserverForName:@"com.haoge.springtwelve.preferences-changed"
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            HaogeDialPreferencesChanged();
        }];
    [[NSNotificationCenter defaultCenter] addObserverForName:@"CNContactStoreDidChangeNotification"
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            dispatch_async(HaogeDialContactsQueue(), ^{
                HaogeDialContactCache = nil;
                HaogeDialContactCacheReady = NO;
                HaogeDialContactRetryAfter = 0.0;
                HaogeDialContactLoadStarted = NO;
            });
            HaogeDialPreferencesChanged();
        }];
    _dyld_register_func_for_add_image(HaogeSpringTwelveDialImageAdded);
    dispatch_async(dispatch_get_main_queue(), ^{ HaogeSpringTwelveDialInstall(); });
}
