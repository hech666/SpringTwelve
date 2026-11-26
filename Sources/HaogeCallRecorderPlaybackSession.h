#pragma once
#import <AVFoundation/AVFoundation.h>
#import <CoreTelephony/CTCallCenter.h>
#import <CoreTelephony/CTCall.h>
#import <CallKit/CallKit.h>
#import <dlfcn.h>

// Main-queue, playback-only lease on MobilePhone's shared session. A call,
// interruption, route loss or foreign category revokes it WITHOUT session writes.
@interface HaogeCallRecorderPlaybackSession : NSObject <CXCallObserverDelegate>
@property(nonatomic, copy) dispatch_block_t haoge_callrecorder_onRevoked;
@property(nonatomic, strong) CTCallCenter *haoge_callrecorder_cellular;
@property(nonatomic, strong) CXCallObserver *haoge_callrecorder_calls;
@property(nonatomic, copy) NSString *haoge_callrecorder_savedCategory;
@property(nonatomic, copy) NSString *haoge_callrecorder_savedMode;
@property(nonatomic) AVAudioSessionCategoryOptions haoge_callrecorder_savedOptions;
@property(nonatomic) AVAudioSessionRouteSharingPolicy haoge_callrecorder_savedPolicy;
@property(atomic) NSUInteger haoge_callrecorder_generation;
@property(nonatomic) NSUInteger haoge_callrecorder_ticket;
@property(atomic) BOOL haoge_callrecorder_settingCategory;
@property(nonatomic) BOOL haoge_callrecorder_owned;
@property(nonatomic) BOOL haoge_callrecorder_activated;
- (BOOL)haoge_callrecorder_hasCall;
- (BOOL)haoge_callrecorder_matches;
- (BOOL)haoge_callrecorder_begin:(NSError **)error;
- (void)haoge_callrecorder_finish;
- (void)haoge_callrecorder_abandon;
- (void)haoge_callrecorder_revoke;
@end

@implementation HaogeCallRecorderPlaybackSession
- (instancetype)init {
    if ((self = [super init])) {
        _haoge_callrecorder_cellular = [CTCallCenter new];
        // Keep CallKit optional; no new framework link dependency or Makefile edit.
        dlopen("/System/Library/Frameworks/CallKit.framework/CallKit", RTLD_LAZY | RTLD_LOCAL);
        _haoge_callrecorder_calls = [NSClassFromString(@"CXCallObserver") new];
        [_haoge_callrecorder_calls setDelegate:self queue:dispatch_get_main_queue()];
        __weak typeof(self) weakSelf = self;
        _haoge_callrecorder_cellular.callEventHandler = ^(CTCall *call) {
            if (![call.callState isEqualToString:CTCallStateDisconnected]) [weakSelf haoge_callrecorder_revoke];
        };
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[AVAudioSessionInterruptionNotification, AVAudioSessionRouteChangeNotification,
                                  AVAudioSessionMediaServicesWereLostNotification, AVAudioSessionMediaServicesWereResetNotification])
            [center addObserver:self selector:@selector(haoge_callrecorder_audioChanged:) name:name object:nil];
    }
    return self;
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    _haoge_callrecorder_cellular.callEventHandler = nil;
    [_haoge_callrecorder_calls setDelegate:nil queue:NULL];
}
- (BOOL)haoge_callrecorder_hasCall {
    // If both observers are unavailable, do not risk commandeering Phone audio.
    if (!self.haoge_callrecorder_cellular && !self.haoge_callrecorder_calls) return YES;
    for (CXCall *call in self.haoge_callrecorder_calls.calls) if (!call.hasEnded) return YES;
    for (CTCall *call in self.haoge_callrecorder_cellular.currentCalls)
        if (![call.callState isEqualToString:CTCallStateDisconnected]) return YES;
    return NO;
}
- (BOOL)haoge_callrecorder_matches {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    return self.haoge_callrecorder_owned && self.haoge_callrecorder_ticket == self.haoge_callrecorder_generation &&
        [session.category isEqualToString:AVAudioSessionCategoryPlayback] &&
        [session.mode isEqualToString:AVAudioSessionModeDefault] && session.categoryOptions == 0 &&
        session.routeSharingPolicy == AVAudioSessionRouteSharingPolicyDefault;
}
- (void)haoge_callrecorder_abandon {
    @synchronized (self) { self.haoge_callrecorder_generation++; }
    self.haoge_callrecorder_owned = NO;
    self.haoge_callrecorder_activated = NO;
    self.haoge_callrecorder_savedCategory = nil;
    self.haoge_callrecorder_savedMode = nil;
}
- (void)haoge_callrecorder_revoke {
    // Invalidate before hopping to main, so cleanup cannot restore after takeover.
    @synchronized (self) { self.haoge_callrecorder_generation++; }
    dispatch_block_t cleanup = ^{
        [self haoge_callrecorder_abandon];
        if (self.haoge_callrecorder_onRevoked) self.haoge_callrecorder_onRevoked();
    };
    if (NSThread.isMainThread) cleanup();
    else dispatch_async(dispatch_get_main_queue(), cleanup);
}
- (void)callObserver:(CXCallObserver *)observer callChanged:(CXCall *)call {
    if (!call.hasEnded) [self haoge_callrecorder_revoke];
}
- (void)haoge_callrecorder_audioChanged:(NSNotification *)note {
    // A delayed notification from our normal release must not delete a paused player.
    if (!self.haoge_callrecorder_owned) return;
    if ([note.name isEqualToString:AVAudioSessionInterruptionNotification] &&
        [note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeEnded) return;
    if ([note.name isEqualToString:AVAudioSessionRouteChangeNotification] &&
        [note.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue] == AVAudioSessionRouteChangeReasonCategoryChange) {
        // setCategory itself emits this notification, sometimes after it returns.
        // Ignore only our in-flight setter or a still-matching playback fingerprint.
        if (self.haoge_callrecorder_settingCategory || [self haoge_callrecorder_matches]) return;
    }
    [self haoge_callrecorder_revoke];
}
- (BOOL)haoge_callrecorder_begin:(NSError **)error {
    if (!NSThread.isMainThread || [self haoge_callrecorder_hasCall]) {
        if (error) *error = [NSError errorWithDomain:@"com.haoge.springtwelve.recording.playback" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"通话期间不能回放录音，请挂断后重试。"}];
        return NO;
    }
    if (self.haoge_callrecorder_owned) return [self haoge_callrecorder_matches];
    AVAudioSession *session = AVAudioSession.sharedInstance;
    self.haoge_callrecorder_savedCategory = session.category;
    self.haoge_callrecorder_savedMode = session.mode;
    self.haoge_callrecorder_savedOptions = session.categoryOptions;
    self.haoge_callrecorder_savedPolicy = session.routeSharingPolicy;
    self.haoge_callrecorder_ticket = self.haoge_callrecorder_generation;
    self.haoge_callrecorder_owned = YES;
    self.haoge_callrecorder_settingCategory = YES;
    BOOL configured = [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault
        routeSharingPolicy:AVAudioSessionRouteSharingPolicyDefault options:0 error:error];
    self.haoge_callrecorder_settingCategory = NO;
    if (!configured || ![self haoge_callrecorder_matches] || [self haoge_callrecorder_hasCall]) {
        [self haoge_callrecorder_abandon];
        return NO;
    }
    BOOL active = [session setActive:YES error:error];
    self.haoge_callrecorder_activated = active;
    if (![self haoge_callrecorder_matches] || [self haoge_callrecorder_hasCall]) {
        [self haoge_callrecorder_abandon];
        return NO;
    }
    if (!active) { [self haoge_callrecorder_finish]; return NO; }
    return YES;
}
- (void)haoge_callrecorder_finish {
    if (!self.haoge_callrecorder_owned) return;
    if (!NSThread.isMainThread || ![self haoge_callrecorder_matches] || [self haoge_callrecorder_hasCall]) {
        [self haoge_callrecorder_abandon];
        return;
    }
    AVAudioSession *session = AVAudioSession.sharedInstance;
    BOOL released = YES;
    NSError *error = nil;
    if (self.haoge_callrecorder_activated)
        released = [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
    if (error) NSLog(@"[HaogeCallRecorderPlayback] release code=%ld", (long)error.code);
    // Recheck AFTER deactivation: a notification/call may have revoked our lease.
    if (released && [self haoge_callrecorder_matches] && ![self haoge_callrecorder_hasCall] &&
        self.haoge_callrecorder_savedCategory && self.haoge_callrecorder_savedMode) {
        self.haoge_callrecorder_settingCategory = YES;
        [session setCategory:self.haoge_callrecorder_savedCategory mode:self.haoge_callrecorder_savedMode
            routeSharingPolicy:self.haoge_callrecorder_savedPolicy options:self.haoge_callrecorder_savedOptions error:&error];
        self.haoge_callrecorder_settingCategory = NO;
        if (error) NSLog(@"[HaogeCallRecorderPlayback] restore code=%ld", (long)error.code);
    }
    [self haoge_callrecorder_abandon]; // Never reactivate a previous host session.
}
@end
