#import "AxsSpringTwelveConfig.h"
#import "AxsSpringTwelvePreferences.h"

@interface AxsSpringTwelveConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void axs_springtwelve_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    AxsSpringTwelveConfig *config = (__bridge AxsSpringTwelveConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config axs_springtwelve_reload];
    });
}

@implementation AxsSpringTwelveConfig

+ (instancetype)axs_springtwelve_shared {
    static AxsSpringTwelveConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.axs.springtwelve.preferences", DISPATCH_QUEUE_SERIAL);
        [self axs_springtwelve_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, axs_springtwelve_preferencesDidChange,
            (__bridge CFStringRef)AxsSpringTwelvePreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self axs_springtwelve_reload]; });
    }
    return self;
}

- (void)axs_springtwelve_reload {
    self.snapshot = axs_springtwelve_readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AxsSpringTwelvePreferencesChanged object:self];
    });
}

- (id)axs_springtwelve_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
