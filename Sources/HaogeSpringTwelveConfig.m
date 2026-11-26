#import "HaogeSpringTwelveConfig.h"
#import "HaogeSpringTwelvePreferences.h"

@interface HaogeSpringTwelveConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void haoge_springtwelve_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    HaogeSpringTwelveConfig *config = (__bridge HaogeSpringTwelveConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config haoge_springtwelve_reload];
    });
}

@implementation HaogeSpringTwelveConfig

+ (instancetype)haoge_springtwelve_shared {
    static HaogeSpringTwelveConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.haoge.springtwelve.preferences", DISPATCH_QUEUE_SERIAL);
        [self haoge_springtwelve_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, haoge_springtwelve_preferencesDidChange,
            (__bridge CFStringRef)HaogeSpringTwelvePreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self haoge_springtwelve_reload]; });
    }
    return self;
}

- (void)haoge_springtwelve_reload {
    self.snapshot = haoge_springtwelve_readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:HaogeSpringTwelvePreferencesChanged object:self];
    });
}

- (id)haoge_springtwelve_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
