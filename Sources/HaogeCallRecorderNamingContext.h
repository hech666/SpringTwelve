#pragma once
#import <CoreTelephony/CTCallCenter.h>
#import <CoreTelephony/CTCall.h>
#import <Contacts/Contacts.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "HaogeCallRecorderFileName.h"

// Metadata only. No telephony setters, PCM, helper arguments or control protocol changes.
static id HaogeCallRecorderNamingObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    if (!sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@' ||
        (sig.methodReturnType[1] != '\0' && sig.methodReturnType[1] != '"')) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}
static BOOL HaogeCallRecorderNamingBool(id object, NSString *name, BOOL *out) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    if (!sig || sig.numberOfArguments != 2 || sig.methodReturnType[1] != '\0') return NO;
    if (sig.methodReturnType[0] == 'B') *out = ((bool (*)(id, SEL))objc_msgSend)(object, selector);
    else if (sig.methodReturnType[0] == 'c') *out = ((signed char (*)(id, SEL))objc_msgSend)(object, selector) != 0;
    else return NO;
    return YES;
}
static NSString *HaogeCallRecorderNamingContact(NSString *number) {
    // Read the host's authorized address book only. Never prompt from SpringBoard or bypass TCC.
    @try {
        if ([CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts] != CNAuthorizationStatusAuthorized) return nil;
        CNContactStore *store = [CNContactStore new];
        NSPredicate *predicate = [CNContact predicateForContactsMatchingPhoneNumber:[CNPhoneNumber phoneNumberWithStringValue:number]];
        NSArray *keys = @[[CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName]];
        NSArray<CNContact *> *matches = [store unifiedContactsMatchingPredicate:predicate keysToFetch:keys error:NULL];
        if (matches.count != 1) return nil; // Never choose an arbitrary person sharing a number.
        return HaogeCallRecorderSafeContactComponent([CNContactFormatter stringFromContact:matches.firstObject style:CNContactFormatterStyleFullName]);
    } @catch (__unused NSException *exception) { return nil; }
}
@interface HaogeCallRecorderNamingContext : NSObject
@property(nonatomic, copy) NSString *haoge_callrecorder_ctID;
@property(nonatomic, copy) NSString *haoge_callrecorder_tuID;
@property(nonatomic, copy) NSString *haoge_callrecorder_number;
@property(nonatomic, copy) NSString *haoge_callrecorder_contact;
@property(nonatomic) BOOL haoge_callrecorder_ambiguous;
@property(nonatomic) BOOL haoge_callrecorder_closed;
@property(nonatomic) NSUInteger haoge_callrecorder_revision;
- (void)haoge_callrecorder_observeID:(NSString *)key state:(NSString *)state multiple:(BOOL)multiple;
- (void)haoge_callrecorder_sample:(CTCallCenter *)center;
- (NSDictionary *)haoge_callrecorder_finish;
@end
@implementation HaogeCallRecorderNamingContext
- (void)haoge_callrecorder_observeID:(NSString *)key state:(NSString *)state multiple:(BOOL)multiple {
    @synchronized (self) {
        if (self.haoge_callrecorder_closed) return;
        self.haoge_callrecorder_revision++;
        if (multiple) self.haoge_callrecorder_ambiguous = YES;
        if (self.haoge_callrecorder_ctID && ![self.haoge_callrecorder_ctID isEqualToString:key] &&
            ![state isEqualToString:CTCallStateDisconnected]) self.haoge_callrecorder_ambiguous = YES;
        if ([state isEqualToString:CTCallStateDisconnected] &&
            (!self.haoge_callrecorder_ctID || [self.haoge_callrecorder_ctID isEqualToString:key])) self.haoge_callrecorder_closed = YES;
    }
}
- (void)haoge_callrecorder_sample:(CTCallCenter *)center {
    NSUInteger revision;
    @synchronized (self) {
        if (self.haoge_callrecorder_closed || self.haoge_callrecorder_ambiguous) return;
        revision = self.haoge_callrecorder_revision;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_block_t ambiguous = ^{ @synchronized (self) {
            if (!self.haoge_callrecorder_closed && revision == self.haoge_callrecorder_revision)
                self.haoge_callrecorder_ambiguous = YES;
        }};
        @try {
            @synchronized (self) {
                if (self.haoge_callrecorder_closed || self.haoge_callrecorder_ambiguous || revision != self.haoge_callrecorder_revision) return;
            }
            // Slow framework/host calls never hold the lock used by normal-stop.
            NSSet<CTCall *> *current = center.currentCalls;
            if (current.count > 1) { ambiguous(); return; }
            if (current.count != 1) return;
            CTCall *cellularCall = current.anyObject;
            if (![cellularCall.callState isEqualToString:CTCallStateConnected]) return;
            NSString *ctID = [cellularCall.callID copy];
            if (![ctID isKindOfClass:NSString.class] || !ctID.length || ctID.length > 256) return;
            static void *framework; static dispatch_once_t once;
            dispatch_once(&once, ^{ framework = dlopen("/System/Library/PrivateFrameworks/TelephonyUtilities.framework/TelephonyUtilities", RTLD_LAZY | RTLD_LOCAL); });
            if (!framework) return;
            id tu = HaogeCallRecorderNamingObject(NSClassFromString(@"TUCallCenter"), @"sharedInstance");
            id calls = HaogeCallRecorderNamingObject(tu, @"currentCalls");
            if (![calls isKindOfClass:NSArray.class]) return;
            if ([calls count] != 1) { if ([calls count] > 1) ambiguous(); return; }
            id call = [calls firstObject];
            if (![call isKindOfClass:NSClassFromString(@"TUCall")]) return;
            BOOL connected = NO, conference = YES, telephony = NO;
            id provider = HaogeCallRecorderNamingObject(call, @"provider");
            if (![provider isKindOfClass:NSClassFromString(@"TUCallProvider")] ||
                !HaogeCallRecorderNamingBool(provider, @"isTelephonyProvider", &telephony) || !telephony ||
                !HaogeCallRecorderNamingBool(call, @"isConnected", &connected) || !connected ||
                !HaogeCallRecorderNamingBool(call, @"isConferenced", &conference)) return;
            if (conference) { ambiguous(); return; }
            NSString *tuID = HaogeCallRecorderNamingObject(call, @"callUUID");
            if (![tuID isKindOfClass:NSString.class] || !tuID.length || tuID.length > 256) return;
            id handle = HaogeCallRecorderNamingObject(call, @"handle");
            if (![handle isKindOfClass:NSClassFromString(@"TUHandle")]) return;
            NSString *number = HaogeCallRecorderNormalizedPeerNumber(HaogeCallRecorderNamingObject(handle, @"value"));
            NSSet<CTCall *> *confirmed = center.currentCalls;
            if (confirmed.count != 1) { if (confirmed.count > 1) ambiguous(); return; }
            CTCall *confirmedCall = confirmed.anyObject;
            if (![confirmedCall.callID isEqualToString:ctID]) { ambiguous(); return; }
            if (![confirmedCall.callState isEqualToString:CTCallStateConnected]) return;
            @synchronized (self) {
                if (self.haoge_callrecorder_closed || self.haoge_callrecorder_ambiguous || revision != self.haoge_callrecorder_revision) return;
                // CT/TU identifiers are bound independently, never equated across frameworks.
                if ((self.haoge_callrecorder_ctID && ![self.haoge_callrecorder_ctID isEqualToString:ctID]) ||
                    (self.haoge_callrecorder_tuID && ![self.haoge_callrecorder_tuID isEqualToString:tuID]) ||
                    (number && self.haoge_callrecorder_number && ![self.haoge_callrecorder_number isEqualToString:number])) {
                    self.haoge_callrecorder_ambiguous = YES; return;
                }
                self.haoge_callrecorder_ctID = ctID; self.haoge_callrecorder_tuID = tuID;
                if (!number || self.haoge_callrecorder_number) return;
                self.haoge_callrecorder_number = number;
            }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                NSString *contact = HaogeCallRecorderNamingContact(number);
                @synchronized (self) { if (!self.haoge_callrecorder_ambiguous) self.haoge_callrecorder_contact = contact; }
            });
        } @catch (__unused NSException *exception) { ambiguous(); }
    });
}
- (NSDictionary *)haoge_callrecorder_finish {
    @synchronized (self) {
        self.haoge_callrecorder_closed = YES;
        self.haoge_callrecorder_revision++;
        if (self.haoge_callrecorder_ambiguous || !self.haoge_callrecorder_number.length) return @{};
        return self.haoge_callrecorder_contact.length ? @{@"number":self.haoge_callrecorder_number, @"contact":self.haoge_callrecorder_contact}
                                                  : @{@"number":self.haoge_callrecorder_number};
    }
}
@end
