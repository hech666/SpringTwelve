#import "HaogeCallRecorderRecordingAccess.h"
#import "HaogeCallRecorderPaths.h"
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>
#import <unistd.h>

// ABI: Theos sandbox.h issue_file; WebKit SandboxSPI.h consume (int64_t).
// Resolved at runtime: no new entitlement, Mach service, or hard private-library dependency.
typedef char *(*HaogeIssueFile)(const char *, const char *, uint32_t);
typedef int64_t (*HaogeConsume)(const char *);
NSString * const HaogeCallRecorderRecordingAccessReady = @"com.haoge.springtwelve.recording.access-local-ready";
static CFStringRef const HaogeRequest = CFSTR("com.haoge.springtwelve.recording.recordings-access-request");
static CFStringRef const HaogeReady = CFSTR("com.haoge.springtwelve.recording.recordings-access-ready");
static NSString * const HaogeTokenFile = @"HaogeCallRecorder-recordings.token";
static dispatch_queue_t HaogeAccessQueue;
static BOOL HaogePhone;
static NSMutableArray<NSNumber *> *HaogeHandles; // Intentionally never released before process exit.
static BOOL HaogeConsumed;

static NSString *HaogePhoneCaches(void) {
    return NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
}
void haoge_callrecorder_accessLog(const char *stage, int code) {
    // Only fixed stage labels + errno; NEVER paths, token, phone numbers, or audio.
    NSLog(@"[HaogeCallRecorder:Access] stage=%s errno=%d (%s)", stage, code, strerror(code));
    NSString *path = HaogePhone ? [HaogePhoneCaches() stringByAppendingPathComponent:@"HaogeCallRecorder-access.log"] :
        [haoge_callrecorder_recordingDirectory() stringByAppendingPathComponent:@"Diagnostics/HaogeCallRecorder-access.log"];
    if (!path) return;
    int fd = open(path.fileSystemRepresentation, O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW|O_CLOEXEC, 0600);
    if (fd < 0) return;
    struct stat st;
    if (!fstat(fd, &st) && S_ISREG(st.st_mode) && st.st_nlink == 1 && st.st_uid == getuid() && !(st.st_mode & 0077)) {
        if (st.st_size > 65536) ftruncate(fd, 0);
        char line[256];
        int n = snprintf(line, sizeof(line), "%.3f stage=%s errno=%d (%s)\n", NSDate.date.timeIntervalSince1970, stage, code, strerror(code));
        if (n > 0 && n < (int)sizeof(line)) write(fd, line, (size_t)n);
    }
    close(fd);
}
static void *HaogeSandboxSymbol(const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (!symbol) {
        // iOS SDK libsystem_sandbox.tbd exports the extension SPI through libSystem.
        static void *library;
        if (!library) library = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_LAZY|RTLD_LOCAL);
        if (library) symbol = dlsym(library, name);
    }
    return symbol;
}
static NSString *HaogeCanonical(NSString *path) {
    if (!path.isAbsolutePath) { errno = EINVAL; return nil; }
    char *resolved = realpath(path.fileSystemRepresentation, NULL);
    if (!resolved) return nil;
    NSString *result = [NSString stringWithUTF8String:resolved]; free(resolved);
    return result;
}

static void HaogeIssueToPhone(void) {
    @autoreleasepool {
        // No caller-supplied path. Reject symlink redirection outside this exact real directory.
        NSString *mobile = HaogeCanonical(@"/var/mobile");
        NSString *directory = HaogeCanonical(haoge_callrecorder_recordingDirectory());
        if (!mobile || !directory) { haoge_callrecorder_accessLog("sb.realpath", errno); return; }
        if (![directory isEqualToString:[mobile stringByAppendingPathComponent:@"Documents/CallRecordings"]]) {
            haoge_callrecorder_accessLog("sb.scope", EACCES); return;
        }
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL lookup = NSSelectorFromString(@"applicationProxyForIdentifier:");
        SEL dataURL = NSSelectorFromString(@"dataContainerURL");
        if (![proxyClass respondsToSelector:lookup]) { haoge_callrecorder_accessLog("sb.proxy-api", ENOSYS); return; }
        id proxy = ((id (*)(id, SEL, NSString *))[proxyClass methodForSelector:lookup])(proxyClass, lookup, @"com.apple.mobilephone");
        if (![proxy respondsToSelector:dataURL]) { haoge_callrecorder_accessLog("sb.proxy-container", ENOENT); return; }
        NSURL *containerURL = ((id (*)(id, SEL))[proxy methodForSelector:dataURL])(proxy, dataURL);
        if (![containerURL isKindOfClass:NSURL.class] || !containerURL.isFileURL) { haoge_callrecorder_accessLog("sb.container-url", EINVAL); return; }
        NSString *container = HaogeCanonical(containerURL.path);
        if (!container) { haoge_callrecorder_accessLog("sb.container-realpath", errno); return; }
        NSString *cachePath = [container stringByAppendingPathComponent:@"Library/Caches"];
        // Phone's existing Caches is required; do not create/alter an app container or its permissions.
        NSString *cache = HaogeCanonical(cachePath);
        if (!cache) { haoge_callrecorder_accessLog("sb.cache-realpath", errno); return; }
        if (![cache isEqualToString:cachePath]) { haoge_callrecorder_accessLog("sb.cache-symlink", EACCES); return; }
        int parent = open(cache.fileSystemRepresentation, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
        if (parent < 0) { haoge_callrecorder_accessLog("sb.cache-open", errno); return; }
        struct stat st;
        if (fstat(parent, &st)) { int code=errno; close(parent); haoge_callrecorder_accessLog("sb.cache-stat", code); return; }
        HaogeIssueFile issue = (HaogeIssueFile)HaogeSandboxSymbol("sandbox_extension_issue_file");
        if (!issue) { close(parent); haoge_callrecorder_accessLog("sb.issue-symbol", ENOSYS); return; }
        const char * const *extensionClass = (const char * const *)HaogeSandboxSymbol("APP_SANDBOX_READ_WRITE");
        if (!extensionClass || !*extensionClass) { close(parent); haoge_callrecorder_accessLog("sb.class-symbol", ENOSYS); return; }
        struct stat existing;
        if (fstatat(parent, HaogeTokenFile.fileSystemRepresentation, &existing, AT_SYMLINK_NOFOLLOW) == 0) {
            if (!S_ISREG(existing.st_mode) || existing.st_nlink != 1 || existing.st_uid != st.st_uid || (existing.st_mode & 0777) != 0600) {
                close(parent); haoge_callrecorder_accessLog("sb.token-target", EACCES); return;
            }
        } else if (errno != ENOENT) { int code=errno; close(parent); haoge_callrecorder_accessLog("sb.token-target-stat", code); return; }
        errno = 0;
        char *token = issue(*extensionClass, directory.fileSystemRepresentation, 0);
        int code = token ? 0 : (errno ?: EACCES);
        if (!token) { close(parent); haoge_callrecorder_accessLog("sb.issue", code); return; }
        size_t length = strlen(token);
        NSString *temporary = [HaogeTokenFile stringByAppendingFormat:@".%@", NSUUID.UUID.UUIDString];
        int fd = openat(parent, temporary.fileSystemRepresentation, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC, 0600);
        const char *stage = "sb.token-create";
        if (fd < 0) code = errno;
        if (!code && fchown(fd, st.st_uid, st.st_gid)) { code=errno; stage="sb.token-owner"; }
        if (!code && fchmod(fd, 0600)) { code=errno; stage="sb.token-mode"; }
        if (!code && (!length || length > 65536)) { code=EOVERFLOW; stage="sb.token-size"; }
        size_t offset = 0;
        while (!code && offset < length) {
            ssize_t n = write(fd, token+offset, length-offset);
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) { code=n < 0 ? errno : EIO; stage="sb.token-write"; break; }
            offset += (size_t)n;
        }
        if (!code && fsync(fd)) { code=errno; stage="sb.token-sync"; }
        if (fd >= 0 && close(fd) && !code) { code=errno; stage="sb.token-close"; }
        if (!code && renameat(parent, temporary.fileSystemRepresentation, parent, HaogeTokenFile.fileSystemRepresentation)) { code=errno; stage="sb.token-publish"; }
        if (code) unlinkat(parent, temporary.fileSystemRepresentation, 0);
        close(parent); memset(token, 0, length); free(token);
        haoge_callrecorder_accessLog(code ? stage : "sb.ready", code);
        if (!code) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), HaogeReady, NULL, NULL, YES);
    }
}

void haoge_callrecorder_consumeRecordingAccess(void) {
    if (!HaogePhone) return;
    @synchronized (HaogeHandles) {
        if (HaogeConsumed) return;
        NSString *path = [HaogePhoneCaches() stringByAppendingPathComponent:HaogeTokenFile];
        if (!path) { haoge_callrecorder_accessLog("phone.cache-path", ENOENT); return; }
        int fd = open(path.fileSystemRepresentation, O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
        if (fd < 0) { haoge_callrecorder_accessLog("phone.token-open", errno); return; }
        struct stat st;
        int code=0; const char *stage="phone.token-stat";
        if (fstat(fd, &st)) code=errno;
        if (!code && (!S_ISREG(st.st_mode) || st.st_nlink!=1 || st.st_uid!=getuid() || (st.st_mode & 0777)!=0600 || st.st_size<=0 || st.st_size>65536)) { code=EACCES; stage="phone.token-metadata"; }
        char *token = !code ? (char *)calloc(1, (size_t)st.st_size+1) : NULL;
        if (!code && !token) { code=ENOMEM; stage="phone.token-memory"; }
        size_t offset=0;
        while (!code && offset < (size_t)st.st_size) {
            ssize_t n=read(fd,token+offset,(size_t)st.st_size-offset);
            if (n<0 && errno==EINTR) continue;
            if (n<=0) { code=n<0?errno:EIO; stage="phone.token-read"; break; }
            offset+=(size_t)n;
        }
        close(fd);
        if (!code) {
            HaogeConsume consume=(HaogeConsume)HaogeSandboxSymbol("sandbox_extension_consume");
            if (!consume) { code=ENOSYS; stage="phone.consume-symbol"; }
            else {
                errno=0; int64_t handle=consume(token);
                if (handle<0) { code=errno?:EACCES; stage="phone.consume"; }
                else { [HaogeHandles addObject:@(handle)]; HaogeConsumed=YES; stage="phone.consumed"; }
            }
        }
        if (token) { memset(token,0,(size_t)st.st_size); free(token); }
        haoge_callrecorder_accessLog(stage,code);
    }
}
void haoge_callrecorder_requestRecordingAccess(void) {
    if (!HaogePhone) return;
    @synchronized (HaogeHandles) { HaogeConsumed=NO; } // Retain old handles; allow fresh token on failure.
    static NSTimeInterval last;
    @synchronized (HaogeHandles) {
        NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
        if (last && now-last<1.0) return;
        last=now;
    }
    haoge_callrecorder_accessLog("phone.request",0);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), HaogeRequest, NULL, NULL, YES);
}
static void HaogeAccessNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    if (HaogePhone) {
        dispatch_async(HaogeAccessQueue, ^{
            haoge_callrecorder_consumeRecordingAccess();
            dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:HaogeCallRecorderRecordingAccessReady object:nil]; });
        });
    } else dispatch_async(HaogeAccessQueue, ^{
        static NSTimeInterval last;
        NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
        if (last && now-last<0.5) return;
        last=now; HaogeIssueToPhone();
    });
}
void haoge_callrecorder_installRecordingAccess(void) {
    NSString *bundle=NSBundle.mainBundle.bundleIdentifier;
    HaogePhone=[bundle isEqualToString:@"com.apple.mobilephone"];
    if (!HaogePhone && ![bundle isEqualToString:@"com.apple.springboard"]) return;
    HaogeAccessQueue=dispatch_queue_create("com.haoge.springtwelve.recording.recording-access", DISPATCH_QUEUE_SERIAL);
    HaogeHandles=[NSMutableArray array];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, HaogeAccessNotification,
        HaogePhone ? HaogeReady : HaogeRequest, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    // Issuer has no startup side effects; first Phone permission failure requests the fixed grant.
}
