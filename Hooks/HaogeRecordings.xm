// Clean-room recording browser only: this module never captures calls or imports audio.
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <dirent.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#import <errno.h>
#import <math.h>
#import <stdlib.h>
#import <string.h>
#import "HaogeSpringTwelvePreferences.h"
#import "HaogeSpringTwelveSwitches.h"
#import "HaogeCallRecorderPaths.h"
#import "HaogeCallRecorderRecordingAccess.h"
#import "HaogeCallRecorderPlaybackSession.h"
#import "HaogeCallRecorderFileName.h"

@interface HaogeCallRecorderRecording : NSObject
@property(nonatomic, copy) NSString *haoge_callrecorder_name;
@property(nonatomic, strong) NSDate *haoge_callrecorder_date;
@property(nonatomic) unsigned long long haoge_callrecorder_size;
@property(nonatomic) unsigned long long haoge_callrecorder_device;
@property(nonatomic) unsigned long long haoge_callrecorder_inode;
@end
@implementation HaogeCallRecorderRecording
@end

static NSString * const HaogeCallRecorderRecordingStateChanged = @"com.haoge.springtwelve.recording.call-recording-state";
static NSURL *HaogeCallRecorderRecordingsURL(void) {
    // Shared user-data path is the real mobile Documents folder on every scheme.
    NSString *path = haoge_callrecorder_recordingDirectory();
    return path.isAbsolutePath ? [NSURL fileURLWithPath:path isDirectory:YES] : nil;
}
static BOOL HaogeCallRecorderOwnedRecordingName(NSString *name) {
    if (!name.length || ![name isEqualToString:name.lastPathComponent] || [name containsString:@"/"]) return NO;
    if (HaogeCallRecorderReadableRecordingName(name)) return YES;
    if (([name hasPrefix:@"HaogeSpringTwelve-"] || [name hasPrefix:@"AxsSpringTwelve-"]) &&
        [@[@"mp3", @"m4a", @"mp4"] containsObject:name.pathExtension.lowercaseString])
        return name.stringByDeletingPathExtension.length >
            ([name hasPrefix:@"HaogeSpringTwelve-"] ? @"HaogeSpringTwelve-".length : @"AxsSpringTwelve-".length);
    // Legacy ownership still requires an audio extension; arbitrary prefixed documents are excluded.
    return [name hasPrefix:@"SpringTwelve-"] && name.stringByDeletingPathExtension.length > @"SpringTwelve-".length &&
        [@[@"m4a", @"caf", @"wav", @"aif", @"aiff", @"mp3", @"aac"] containsObject:name.pathExtension.lowercaseString];
}
static NSError *HaogeCallRecorderRecordingError(int code) {
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:code ?: EIO userInfo:nil];
}
static int HaogeCallRecorderOpenRecordingDirectory(NSError **error) {
    haoge_callrecorder_consumeRecordingAccess();
    NSURL *url = HaogeCallRecorderRecordingsURL();
    int descriptor = url ? open(url.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) : -1;
    int code = descriptor < 0 ? (url ? errno : EINVAL) : 0;
    haoge_callrecorder_accessLog("phone.directory-open", code);
    if (code == EPERM || code == EACCES) haoge_callrecorder_requestRecordingAccess();
    if (code && error) *error = HaogeCallRecorderRecordingError(code);
    return descriptor;
}
static BOOL HaogeCallRecorderRecordingMatches(HaogeCallRecorderRecording *record, const struct stat *info) {
    return S_ISREG(info->st_mode) && info->st_nlink == 1 &&
        (unsigned long long)info->st_dev == record.haoge_callrecorder_device &&
        (unsigned long long)info->st_ino == record.haoge_callrecorder_inode;
}
static NSArray<HaogeCallRecorderRecording *> *HaogeCallRecorderReadRecordingIndex(NSError **error) {
    int directory = HaogeCallRecorderOpenRecordingDirectory(error);
    if (directory < 0) {
        if (error && (*error).code == ENOENT) *error = nil; // Missing folder is an empty index, not an import request.
        return @[];
    }
    DIR *stream = fdopendir(directory); // Owns the descriptor on success.
    if (!stream) {
        int code = errno; close(directory);
        if (error) *error = HaogeCallRecorderRecordingError(code);
        return @[];
    }
    NSMutableArray *records = [NSMutableArray array];
    struct dirent *entry;
    int scanError = 0;
    for (;;) {
        errno = 0;
        entry = readdir(stream);
        if (!entry) { scanError = errno; break; }
        @autoreleasepool {
            NSString *name = [NSString stringWithUTF8String:entry->d_name];
            if (!HaogeCallRecorderOwnedRecordingName(name)) continue; // No metadata/content access for other names.
            struct stat info;
            if (fstatat(directory, entry->d_name, &info, AT_SYMLINK_NOFOLLOW) != 0 ||
                !S_ISREG(info.st_mode) || info.st_nlink != 1) continue;
            HaogeCallRecorderRecording *record = [HaogeCallRecorderRecording new];
            record.haoge_callrecorder_name = name;
            record.haoge_callrecorder_date = [NSDate dateWithTimeIntervalSince1970:info.st_mtimespec.tv_sec + info.st_mtimespec.tv_nsec / 1e9];
            record.haoge_callrecorder_size = (unsigned long long)MAX((off_t)0, info.st_size);
            record.haoge_callrecorder_device = (unsigned long long)info.st_dev;
            record.haoge_callrecorder_inode = (unsigned long long)info.st_ino;
            [records addObject:record];
        }
    }
    closedir(stream);
    if (scanError && error) *error = HaogeCallRecorderRecordingError(scanError);
    [records sortUsingComparator:^NSComparisonResult(HaogeCallRecorderRecording *a, HaogeCallRecorderRecording *b) {
        NSComparisonResult order = [b.haoge_callrecorder_date compare:a.haoge_callrecorder_date];
        return order == NSOrderedSame ? [a.haoge_callrecorder_name compare:b.haoge_callrecorder_name] : order;
    }];
    return records;
}
// Only generated, private temporary directories may be removed by this helper.
static void HaogeCallRecorderRemoveRecordingSnapshot(NSURL *url) {
    if (!url) return;
    NSURL *parent = url.URLByDeletingLastPathComponent;
    if ([parent.lastPathComponent hasPrefix:@"HaogeCallRecorder-Recording-"] &&
        [parent.URLByDeletingLastPathComponent.path.stringByStandardizingPath isEqualToString:NSTemporaryDirectory().stringByStandardizingPath])
        [[NSFileManager defaultManager] removeItemAtURL:parent error:NULL];
}
// Copy through an anchored, no-follow descriptor. Player/share never reopen a mutable source path.
static NSURL *HaogeCallRecorderRecordingSnapshot(HaogeCallRecorderRecording *record, NSError **error) {
    if (!HaogeCallRecorderOwnedRecordingName(record.haoge_callrecorder_name)) {
        if (error) *error = HaogeCallRecorderRecordingError(EINVAL);
        return nil;
    }
    int directory = HaogeCallRecorderOpenRecordingDirectory(error);
    if (directory < 0) return nil;
    int source = openat(directory, record.haoge_callrecorder_name.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    int code = source < 0 ? errno : 0;
    close(directory);
    struct stat before = {}, after = {};
    if (!code && fstat(source, &before) != 0) code = errno;
    if (!code && !HaogeCallRecorderRecordingMatches(record, &before)) code = ESTALE;
    if (code) {
        if (source >= 0) close(source);
        if (error) *error = HaogeCallRecorderRecordingError(code);
        return nil;
    }
    NSURL *folder = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[@"HaogeCallRecorder-Recording-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:NO
        attributes:@{NSFilePosixPermissions: @0700} error:error]) { close(source); return nil; }
    NSURL *copy = [folder URLByAppendingPathComponent:record.haoge_callrecorder_name isDirectory:NO];
    int destination = open(copy.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (destination < 0) code = errno;
    char buffer[65536];
    off_t total = 0;
    while (!code) {
        ssize_t count = read(source, buffer, sizeof(buffer));
        if (count < 0) { if (errno == EINTR) continue; code = errno; break; }
        if (!count) break;
        total += count;
        if (total > before.st_size) { code = EBUSY; break; }
        ssize_t written = 0;
        while (written < count) {
            ssize_t amount = write(destination, buffer + written, (size_t)(count - written));
            if (amount < 0 && errno == EINTR) continue;
            if (amount <= 0) { code = amount < 0 ? errno : EIO; break; }
            written += amount;
        }
    }
    if (!code && fstat(source, &after) != 0) code = errno;
    if (!code && (total != before.st_size || after.st_size != before.st_size ||
        after.st_mtimespec.tv_sec != before.st_mtimespec.tv_sec || after.st_mtimespec.tv_nsec != before.st_mtimespec.tv_nsec)) code = EBUSY;
    close(source);
    if (destination >= 0 && close(destination) != 0 && !code) code = errno;
    if (code) {
        HaogeCallRecorderRemoveRecordingSnapshot(copy);
        if (error) *error = HaogeCallRecorderRecordingError(code);
        return nil;
    }
    return copy;
}
static BOOL HaogeCallRecorderDeleteRecording(HaogeCallRecorderRecording *record, NSError **error) {
    if (!HaogeCallRecorderOwnedRecordingName(record.haoge_callrecorder_name)) {
        if (error) *error = HaogeCallRecorderRecordingError(EINVAL);
        return NO;
    }
    int directory = HaogeCallRecorderOpenRecordingDirectory(error);
    if (directory < 0) return NO;
    struct stat info;
    int code = 0;
    const char *name = record.haoge_callrecorder_name.fileSystemRepresentation;
    if (fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) != 0) code = errno;
    else if (!HaogeCallRecorderRecordingMatches(record, &info)) code = ESTALE;
    else if (unlinkat(directory, name, 0) != 0) code = errno; // Never recursive; never follows a link.
    close(directory);
    if (code && error) *error = HaogeCallRecorderRecordingError(code);
    return code == 0;
}

@interface HaogeCallRecorderRecordingListViewController : UIViewController
    <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, AVAudioPlayerDelegate> {
    UITableView *_haoge_callrecorder_table;
    UISearchController *_haoge_callrecorder_search;
    UILabel *_haoge_callrecorder_empty;
    UILabel *_haoge_callrecorder_nowPlaying;
    UILabel *_haoge_callrecorder_time;
    UISlider *_haoge_callrecorder_seek;
    UIButton *_haoge_callrecorder_play;
    UIButton *_haoge_callrecorder_stop;
    UIButton *_haoge_callrecorder_share;
    NSDateFormatter *_haoge_callrecorder_dates;
    NSArray<HaogeCallRecorderRecording *> *_haoge_callrecorder_records;
    NSArray<HaogeCallRecorderRecording *> *_haoge_callrecorder_filtered;
    HaogeCallRecorderRecording *_haoge_callrecorder_selected;
    AVAudioPlayer *_haoge_callrecorder_player;
    HaogeCallRecorderPlaybackSession *_haoge_callrecorder_audioSession;
    NSURL *_haoge_callrecorder_snapshot;
    NSTimer *_haoge_callrecorder_timer;
    dispatch_queue_t _haoge_callrecorder_io;
    NSUInteger _haoge_callrecorder_loadToken;
    NSUInteger _haoge_callrecorder_actionToken;
    NSString *_haoge_callrecorder_indexError;
}
- (void)haoge_callrecorder_openRecordingsFolder;
@end

@implementation HaogeCallRecorderRecordingListViewController
- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = @"通话录音";
        _haoge_callrecorder_records = @[];
        _haoge_callrecorder_filtered = @[];
        _haoge_callrecorder_io = dispatch_queue_create("com.haoge.springtwelve.recording.recordings.io", DISPATCH_QUEUE_SERIAL);
        _haoge_callrecorder_audioSession = [HaogeCallRecorderPlaybackSession new];
        __weak typeof(self) weakSelf = self;
        _haoge_callrecorder_audioSession.haoge_callrecorder_onRevoked = ^{
            [weakSelf haoge_callrecorder_stopPlayback];
        };
    }
    return self;
}
- (UIButton *)haoge_callrecorder_button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _haoge_callrecorder_dates = [NSDateFormatter new];
    _haoge_callrecorder_dates.dateStyle = NSDateFormatterMediumStyle;
    _haoge_callrecorder_dates.timeStyle = NSDateFormatterShortStyle;
    _haoge_callrecorder_search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _haoge_callrecorder_search.searchResultsUpdater = self;
    _haoge_callrecorder_search.obscuresBackgroundDuringPresentation = NO;
    _haoge_callrecorder_search.searchBar.placeholder = @"搜索文件名或日期";
    self.navigationItem.searchController = _haoge_callrecorder_search;
    // Keep the search bar out of scroll-driven collapse while the table follows the safe area.
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"打开录音目录"
        style:UIBarButtonItemStylePlain target:self action:@selector(haoge_callrecorder_openRecordingsFolder)];
    _haoge_callrecorder_table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _haoge_callrecorder_table.dataSource = self;
    _haoge_callrecorder_table.delegate = self;
    // Both edges already follow this controller's safe area; do not inset again for Phone's bars.
    _haoge_callrecorder_table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _haoge_callrecorder_table.rowHeight = UITableViewAutomaticDimension;
    _haoge_callrecorder_table.estimatedRowHeight = 68;
    _haoge_callrecorder_table.refreshControl = [UIRefreshControl new];
    [_haoge_callrecorder_table.refreshControl addTarget:self action:@selector(haoge_callrecorder_reload)
        forControlEvents:UIControlEventValueChanged];
    _haoge_callrecorder_empty = [UILabel new];
    _haoge_callrecorder_empty.numberOfLines = 0;
    _haoge_callrecorder_empty.textAlignment = NSTextAlignmentCenter;
    _haoge_callrecorder_empty.textColor = UIColor.secondaryLabelColor;
    _haoge_callrecorder_empty.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _haoge_callrecorder_empty.adjustsFontForContentSizeCategory = YES;
    _haoge_callrecorder_table.backgroundView = _haoge_callrecorder_empty;
    _haoge_callrecorder_nowPlaying = [UILabel new];
    _haoge_callrecorder_nowPlaying.numberOfLines = 2;
    _haoge_callrecorder_nowPlaying.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    _haoge_callrecorder_nowPlaying.adjustsFontForContentSizeCategory = YES;
    _haoge_callrecorder_time = [UILabel new];
    _haoge_callrecorder_time.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    _haoge_callrecorder_time.textAlignment = NSTextAlignmentCenter;
    _haoge_callrecorder_seek = [UISlider new];
    _haoge_callrecorder_seek.accessibilityLabel = @"播放进度";
    [_haoge_callrecorder_seek addTarget:self action:@selector(haoge_callrecorder_seekChanged)
        forControlEvents:UIControlEventValueChanged];
    _haoge_callrecorder_play = [self haoge_callrecorder_button:@"播放" action:@selector(haoge_callrecorder_togglePlayback)];
    _haoge_callrecorder_stop = [self haoge_callrecorder_button:@"停止" action:@selector(haoge_callrecorder_stopPlayback)];
    _haoge_callrecorder_share = [self haoge_callrecorder_button:@"分享" action:@selector(haoge_callrecorder_shareSelected)];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[_haoge_callrecorder_play, _haoge_callrecorder_stop, _haoge_callrecorder_share]];
    buttons.distribution = UIStackViewDistributionFillEqually;
    UIStackView *player = [[UIStackView alloc] initWithArrangedSubviews:@[_haoge_callrecorder_nowPlaying, _haoge_callrecorder_seek, _haoge_callrecorder_time, buttons]];
    player.axis = UILayoutConstraintAxisVertical;
    player.spacing = 4;
    player.layoutMarginsRelativeArrangement = YES;
    player.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(8, 16, 8, 16);
    _haoge_callrecorder_table.translatesAutoresizingMaskIntoConstraints = NO;
    player.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_haoge_callrecorder_table];
    [self.view addSubview:player];
    [NSLayoutConstraint activateConstraints:@[
        [_haoge_callrecorder_table.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_haoge_callrecorder_table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_haoge_callrecorder_table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_haoge_callrecorder_table.bottomAnchor constraintEqualToAnchor:player.topAnchor],
        [player.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [player.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [player.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [buttons.heightAnchor constraintGreaterThanOrEqualToConstant:44]
    ]];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(haoge_callrecorder_preferencesChanged:) name:HaogeSpringTwelvePreferencesChanged object:nil];
    [center addObserver:self selector:@selector(haoge_callrecorder_preferencesChanged:) name:HaogeCallRecorderRecordingStateChanged object:nil];
    [center addObserver:self selector:@selector(haoge_callrecorder_suspend:) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(haoge_callrecorder_preferencesChanged:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(haoge_callrecorder_reload) name:HaogeCallRecorderRecordingAccessReady object:nil];
    // PlaybackSession distinguishes our category change from external audio takeover.
    [self haoge_callrecorder_updatePlayer];
    // Initial content must not depend on a pull-to-refresh or a forwarded child appearance.
    [self haoge_callrecorder_reload];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self haoge_callrecorder_reload];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self haoge_callrecorder_stopPlayback];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_haoge_callrecorder_timer invalidate];
    _haoge_callrecorder_player.delegate = nil;
    [_haoge_callrecorder_player stop];
    _haoge_callrecorder_audioSession.haoge_callrecorder_onRevoked = nil;
    [_haoge_callrecorder_audioSession haoge_callrecorder_finish];
    HaogeCallRecorderRemoveRecordingSnapshot(_haoge_callrecorder_snapshot);
}
- (void)haoge_callrecorder_error:(NSString *)message {
    if (self.presentedViewController || !self.viewIfLoaded.window) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"通话录音" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)haoge_callrecorder_reload {
    NSUInteger token = ++_haoge_callrecorder_loadToken;
    BOOL enabled = HaogeSpringTwelveOn(@"callRecordingListEnabled");
    self.navigationItem.rightBarButtonItem.enabled = enabled;
    if (!enabled) {
        [self haoge_callrecorder_stopPlayback];
        _haoge_callrecorder_records = @[];
        _haoge_callrecorder_indexError = nil;
        [self haoge_callrecorder_filter];
        [_haoge_callrecorder_table.refreshControl endRefreshing];
        return;
    }
    __weak HaogeCallRecorderRecordingListViewController *weakSelf = self;
    dispatch_async(_haoge_callrecorder_io, ^{
        @autoreleasepool {
            NSError *error = nil;
            NSArray *records = HaogeCallRecorderReadRecordingIndex(&error);
            dispatch_async(dispatch_get_main_queue(), ^{
                HaogeCallRecorderRecordingListViewController *owner = weakSelf;
                if (!owner || token != owner->_haoge_callrecorder_loadToken) return;
                owner->_haoge_callrecorder_records = HaogeSpringTwelveOn(@"callRecordingListEnabled") ? records : @[];
                owner->_haoge_callrecorder_indexError = error.localizedDescription;
                [owner haoge_callrecorder_filter];
                [owner->_haoge_callrecorder_table.refreshControl endRefreshing];
            });
        }
    });
}
- (void)haoge_callrecorder_filter {
    NSString *query = [_haoge_callrecorder_search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *filtered = [NSMutableArray array];
    for (HaogeCallRecorderRecording *record in _haoge_callrecorder_records) {
        NSString *date = [_haoge_callrecorder_dates stringFromDate:record.haoge_callrecorder_date];
        if (!query.length || [record.haoge_callrecorder_name rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound ||
            [date rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) [filtered addObject:record];
    }
    _haoge_callrecorder_filtered = filtered;
    if (!HaogeSpringTwelveOn(@"callRecordingListEnabled")) _haoge_callrecorder_empty.text = @"录音列表已关闭";
    else if (_haoge_callrecorder_indexError.length) _haoge_callrecorder_empty.text = [@"无法读取录音目录：\n" stringByAppendingString:_haoge_callrecorder_indexError];
    else _haoge_callrecorder_empty.text = query.length ? @"没有匹配的录音" : @"暂无兼容录音\n此实验工程兼容已有 SpringTwelve 录音文件。";
    _haoge_callrecorder_empty.hidden = filtered.count != 0;
    [_haoge_callrecorder_table reloadData];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self haoge_callrecorder_filter]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _haoge_callrecorder_filtered.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HaogeCallRecorderRecording"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"HaogeCallRecorderRecording"];
    HaogeCallRecorderRecording *record = _haoge_callrecorder_filtered[(NSUInteger)indexPath.row];
    cell.textLabel.text = record.haoge_callrecorder_name;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@",
        [_haoge_callrecorder_dates stringFromDate:record.haoge_callrecorder_date],
        [NSByteCountFormatter stringFromByteCount:(long long)record.haoge_callrecorder_size countStyle:NSByteCountFormatterCountStyleFile],
        record.haoge_callrecorder_name.pathExtension.uppercaseString];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ((NSUInteger)indexPath.row < _haoge_callrecorder_filtered.count)
        [self haoge_callrecorder_prepare:_haoge_callrecorder_filtered[(NSUInteger)indexPath.row] share:NO];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row >= _haoge_callrecorder_filtered.count || !HaogeSpringTwelveOn(@"callRecordingListEnabled")) return nil;
    HaogeCallRecorderRecording *record = _haoge_callrecorder_filtered[(NSUInteger)indexPath.row];
    __weak HaogeCallRecorderRecordingListViewController *weakSelf = self;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除"
        handler:^(UIContextualAction *action, UIView *view, void (^complete)(BOOL)) {
            complete(NO); // Confirmation happens before any filesystem mutation.
            [weakSelf haoge_callrecorder_confirmDelete:record];
        }];
    UIContextualAction *share = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"分享"
        handler:^(UIContextualAction *action, UIView *view, void (^complete)(BOOL)) {
            complete(YES);
            [weakSelf haoge_callrecorder_prepare:record share:YES];
        }];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[remove, share]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}
- (void)haoge_callrecorder_confirmDelete:(HaogeCallRecorderRecording *)record {
    if (!HaogeSpringTwelveOn(@"callRecordingListEnabled") || self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除此录音？" message:record.haoge_callrecorder_name preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak HaogeCallRecorderRecordingListViewController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        HaogeCallRecorderRecordingListViewController *owner = weakSelf;
        if (!owner || !HaogeSpringTwelveOn(@"callRecordingListEnabled")) return;
        // Cancel pending playback/export too, so deletion cannot resurrect a stale selection.
        [owner haoge_callrecorder_stopPlayback];
        dispatch_async(owner->_haoge_callrecorder_io, ^{
            NSError *error = nil;
            if (HaogeSpringTwelveOn(@"callRecordingListEnabled")) HaogeCallRecorderDeleteRecording(record, &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf haoge_callrecorder_reload];
                if (error) [weakSelf haoge_callrecorder_error:error.localizedDescription];
            });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)haoge_callrecorder_preferencesChanged:(NSNotification *)note {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self haoge_callrecorder_preferencesChanged:note]; });
        return;
    }
    if (!HaogeSpringTwelveOn(@"callRecordingListEnabled")) [self haoge_callrecorder_stopPlayback];
    if (self.isViewLoaded) [self haoge_callrecorder_reload];
}
- (void)haoge_callrecorder_suspend:(NSNotification *)note {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self haoge_callrecorder_suspend:note]; });
        return;
    }
    [self haoge_callrecorder_stopPlayback];
}
- (void)haoge_callrecorder_prepare:(HaogeCallRecorderRecording *)record share:(BOOL)share {
    if (!HaogeSpringTwelveOn(@"callRecordingListEnabled") || self.presentedViewController) return;
    if (!share) [self haoge_callrecorder_stopPlayback];
    NSUInteger token = ++_haoge_callrecorder_actionToken;
    __weak HaogeCallRecorderRecordingListViewController *weakSelf = self;
    dispatch_async(_haoge_callrecorder_io, ^{
        @autoreleasepool {
            NSError *error = nil;
            NSURL *snapshot = HaogeSpringTwelveOn(@"callRecordingListEnabled") ? HaogeCallRecorderRecordingSnapshot(record, &error) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                HaogeCallRecorderRecordingListViewController *owner = weakSelf;
                if (!owner || token != owner->_haoge_callrecorder_actionToken || !HaogeSpringTwelveOn(@"callRecordingListEnabled") || !owner.viewIfLoaded.window) {
                    HaogeCallRecorderRemoveRecordingSnapshot(snapshot);
                    return;
                }
                if (!snapshot) { [owner haoge_callrecorder_error:error.localizedDescription ?: @"无法读取此录音，请刷新后重试。"]; return; }
                if (share) {
                    if (owner.presentedViewController) { HaogeCallRecorderRemoveRecordingSnapshot(snapshot); return; }
                    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[snapshot] applicationActivities:nil];
                    activity.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *activityError) {
                        HaogeCallRecorderRemoveRecordingSnapshot(snapshot);
                    };
                    activity.popoverPresentationController.sourceView = owner.view;
                    activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(owner.view.bounds), CGRectGetMaxY(owner.view.bounds) - 40, 1, 1);
                    [owner presentViewController:activity animated:YES completion:nil];
                } else {
                    // Runtime lookup avoids requiring an AVFoundation Makefile/linker change.
                    static Class HaogeCallRecorderAudioPlayerClass;
                    static dispatch_once_t once;
                    dispatch_once(&once, ^{
                        dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_LAZY | RTLD_LOCAL);
                        HaogeCallRecorderAudioPlayerClass = NSClassFromString(@"AVAudioPlayer");
                    });
                    NSError *playerError = nil;
                    AVAudioPlayer *player = [(AVAudioPlayer *)[HaogeCallRecorderAudioPlayerClass alloc] initWithContentsOfURL:snapshot error:&playerError];
                    if (!player) {
                        HaogeCallRecorderRemoveRecordingSnapshot(snapshot);
                        [owner haoge_callrecorder_error:playerError.localizedDescription ?: @"系统无法解码此录音。"];
                        return;
                    }
                    owner->_haoge_callrecorder_selected = record;
                    owner->_haoge_callrecorder_snapshot = snapshot;
                    owner->_haoge_callrecorder_player = player;
                    player.delegate = owner;
                    NSError *sessionError = nil;
                    BOOL ready = [owner->_haoge_callrecorder_audioSession haoge_callrecorder_begin:&sessionError];
                    // prepareToPlay may activate audio too; acquire Playback BEFORE it.
                    if (ready && token == owner->_haoge_callrecorder_actionToken)
                        ready = [player prepareToPlay];
                    if (ready && token == owner->_haoge_callrecorder_actionToken &&
                        [owner->_haoge_callrecorder_audioSession haoge_callrecorder_matches]) ready = [player play];
                    else ready = NO;
                    if (!ready || token != owner->_haoge_callrecorder_actionToken ||
                        ![owner->_haoge_callrecorder_audioSession haoge_callrecorder_matches]) {
                        [player stop]; // Also covers synchronous cancellation inside prepare/play.
                        BOOL report = token == owner->_haoge_callrecorder_actionToken;
                        [owner haoge_callrecorder_stopPlayback];
                        if (report) [owner haoge_callrecorder_error:sessionError.localizedDescription ?: @"无法开始播放；请确认电话音频会话当前可用。"];
                        return;
                    }
                    owner->_haoge_callrecorder_timer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
                        [weakSelf haoge_callrecorder_updatePlayer];
                    }];
                    [NSRunLoop.mainRunLoop addTimer:owner->_haoge_callrecorder_timer forMode:NSRunLoopCommonModes];
                    [owner haoge_callrecorder_updatePlayer];
                }
            });
        }
    });
}
- (void)haoge_callrecorder_togglePlayback {
    if (!HaogeSpringTwelveOn(@"callRecordingListEnabled")) { [self haoge_callrecorder_stopPlayback]; return; }
    if (_haoge_callrecorder_player.isPlaying) {
        [_haoge_callrecorder_player pause];
        [_haoge_callrecorder_audioSession haoge_callrecorder_finish];
    } else if (_haoge_callrecorder_player) {
        NSError *error = nil;
        AVAudioPlayer *player = _haoge_callrecorder_player;
        BOOL ready = [_haoge_callrecorder_audioSession haoge_callrecorder_begin:&error];
        if (!ready || player != _haoge_callrecorder_player || ![player play] ||
            ![_haoge_callrecorder_audioSession haoge_callrecorder_matches]) {
            [player pause];
            [_haoge_callrecorder_audioSession haoge_callrecorder_finish];
            [self haoge_callrecorder_error:error.localizedDescription ?: @"无法恢复播放。"];
        }
    }
    [self haoge_callrecorder_updatePlayer];
}
- (void)haoge_callrecorder_stopPlayback {
    ++_haoge_callrecorder_actionToken;
    [_haoge_callrecorder_timer invalidate];
    _haoge_callrecorder_timer = nil;
    _haoge_callrecorder_player.delegate = nil;
    [_haoge_callrecorder_player stop];
    [_haoge_callrecorder_audioSession haoge_callrecorder_finish];
    _haoge_callrecorder_player = nil;
    _haoge_callrecorder_selected = nil;
    HaogeCallRecorderRemoveRecordingSnapshot(_haoge_callrecorder_snapshot);
    _haoge_callrecorder_snapshot = nil;
    [self haoge_callrecorder_updatePlayer];
}
- (void)haoge_callrecorder_seekChanged {
    if (HaogeSpringTwelveOn(@"callRecordingListEnabled") && _haoge_callrecorder_player)
        _haoge_callrecorder_player.currentTime = _haoge_callrecorder_seek.value;
    [self haoge_callrecorder_updatePlayer];
}
- (void)haoge_callrecorder_shareSelected {
    if (_haoge_callrecorder_selected) [self haoge_callrecorder_prepare:_haoge_callrecorder_selected share:YES];
}
- (void)haoge_callrecorder_updatePlayer {
    BOOL available = _haoge_callrecorder_player != nil && HaogeSpringTwelveOn(@"callRecordingListEnabled");
    _haoge_callrecorder_play.enabled = available;
    _haoge_callrecorder_stop.enabled = available;
    _haoge_callrecorder_share.enabled = available;
    _haoge_callrecorder_seek.enabled = available;
    [_haoge_callrecorder_play setTitle:_haoge_callrecorder_player.isPlaying ? @"暂停" : @"播放" forState:UIControlStateNormal];
    _haoge_callrecorder_nowPlaying.text = _haoge_callrecorder_selected.haoge_callrecorder_name ?: @"选择录音以播放；左滑可分享或删除";
    NSTimeInterval duration = MAX(0, _haoge_callrecorder_player.duration);
    NSTimeInterval elapsed = MAX(0, _haoge_callrecorder_player.currentTime);
    if (!isfinite(duration)) duration = 0;
    if (!isfinite(elapsed)) elapsed = 0;
    _haoge_callrecorder_seek.maximumValue = (float)MAX(1, duration);
    if (!_haoge_callrecorder_seek.isTracking) _haoge_callrecorder_seek.value = (float)elapsed;
    _haoge_callrecorder_time.text = [NSString stringWithFormat:@"%02lld:%02lld / %02lld:%02lld",
        (long long)elapsed / 60, (long long)elapsed % 60, (long long)duration / 60, (long long)duration % 60];
}
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (player != self->_haoge_callrecorder_player) return;
        [self haoge_callrecorder_stopPlayback];
        if (!flag) [self haoge_callrecorder_error:@"录音播放未能完成。"];
    });
}
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (player != self->_haoge_callrecorder_player) return;
        [self haoge_callrecorder_stopPlayback];
        [self haoge_callrecorder_error:error.localizedDescription ?: @"录音解码失败。"];
    });
}
- (void)haoge_callrecorder_openRecordingsFolder {
    if (!HaogeSpringTwelveOn(@"callRecordingListEnabled") || self.presentedViewController) return;
    // Filza has its own sandbox/permissions. Do not gate its URL on Phone's directory access.
    NSURLComponents *components = [NSURLComponents new];
    components.scheme = @"filza";
    components.host = @"";
    components.path = haoge_callrecorder_recordingDirectory();
    [[UIApplication sharedApplication] openURL:components.URL options:@{} completionHandler:^(BOOL success) {
        if (!success) dispatch_async(dispatch_get_main_queue(), ^{
            [self haoge_callrecorder_error:@"无法打开 Filza，请确认已安装 Filza。"];
        });
    }];
}
@end

// Replace a real Phone tab entry, never a view laid over the native navigation stack.
// Private identity evidence: docs/phone-tabs.md and mutool-audit/list-tabs.md.
// The role values below are OUR enum, not Phone's private tab integers.
typedef NS_ENUM(NSInteger, HaogeCallRecorderRecordingTabRole) {
    HaogeCallRecorderRecordingTabUnknown,
    HaogeCallRecorderRecordingTabFavorites,
    HaogeCallRecorderRecordingTabVoicemail
};

@interface PhoneTabBarController : UITabBarController
@end

// This browser never pushes screens: playback is inline and share/folder UI is modal.
// Phone's reselect/reset code must not install its native root into our navigation controller.
@interface HaogeCallRecorderRecordingNavigationController : UINavigationController
@property(nonatomic, strong) UIViewController *haoge_callrecorder_recordingRoot;
@end
@implementation HaogeCallRecorderRecordingNavigationController
- (instancetype)initWithRootViewController:(UIViewController *)root {
    self = [super initWithRootViewController:root];
    if (self) _haoge_callrecorder_recordingRoot = root;
    return self;
}
- (void)setViewControllers:(NSArray<UIViewController *> *)controllers {
    [super setViewControllers:self.haoge_callrecorder_recordingRoot ? @[self.haoge_callrecorder_recordingRoot] : controllers];
}
- (void)setViewControllers:(NSArray<UIViewController *> *)controllers animated:(BOOL)animated {
    [super setViewControllers:self.haoge_callrecorder_recordingRoot ? @[self.haoge_callrecorder_recordingRoot] : controllers animated:animated];
}
- (void)pushViewController:(UIViewController *)controller animated:(BOOL)animated {
    if (!self.haoge_callrecorder_recordingRoot) [super pushViewController:controller animated:animated];
}
- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    if (self.haoge_callrecorder_recordingRoot) return nil;
    return [super popViewControllerAnimated:animated];
}
- (NSArray<UIViewController *> *)popToRootViewControllerAnimated:(BOOL)animated {
    if (self.haoge_callrecorder_recordingRoot) return @[];
    return [super popToRootViewControllerAnimated:animated];
}
- (NSArray<UIViewController *> *)popToViewController:(UIViewController *)controller animated:(BOOL)animated {
    if (self.haoge_callrecorder_recordingRoot) return @[];
    return [super popToViewController:controller animated:animated];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.interactivePopGestureRecognizer.enabled = NO;
}
@end

@class HaogeCallRecorderRecordingTabDelegate;
@interface HaogeCallRecorderRecordingTabEntry : NSObject
@property(nonatomic, strong) UIViewController *haoge_callrecorder_original;
@property(nonatomic, strong) UINavigationController *haoge_callrecorder_replacement;
@property(nonatomic) HaogeCallRecorderRecordingTabRole haoge_callrecorder_role;
@end
@implementation HaogeCallRecorderRecordingTabEntry
@end

@interface HaogeCallRecorderRecordingTabState : NSObject
@property(nonatomic, copy) NSArray<HaogeCallRecorderRecordingTabEntry *> *haoge_callrecorder_entries;
@property(nonatomic) BOOL haoge_callrecorder_applying;
@property(nonatomic, strong) UIViewController *haoge_callrecorder_pendingSelection;
@property(nonatomic, strong) HaogeCallRecorderRecordingTabDelegate *haoge_callrecorder_delegate;
@end
@implementation HaogeCallRecorderRecordingTabState
@end

static char HaogeCallRecorderRecordingTabStateKey;
static NSHashTable<UITabBarController *> *HaogeCallRecorderRecordingTabOwners;
static NSMutableArray *HaogeCallRecorderRecordingObservers;
static BOOL HaogeCallRecorderRecordingTabHooksInstalled;

static BOOL HaogeCallRecorderRecordingTabDisabled(HaogeCallRecorderRecordingTabRole role) {
    if (role == HaogeCallRecorderRecordingTabFavorites) return HaogeSpringTwelveOn(@"disablePhoneFavoritesTab");
    if (role == HaogeCallRecorderRecordingTabVoicemail) return HaogeSpringTwelveOn(@"disablePhoneVoicemailTab");
    return NO;
}
static BOOL HaogeCallRecorderRecordingShouldReplace(HaogeCallRecorderRecordingTabRole role) {
    if (!HaogeSpringTwelveOn(@"callRecordingListEnabled") || HaogeCallRecorderRecordingTabDisabled(role)) return NO;
    if (role == HaogeCallRecorderRecordingTabFavorites) return HaogeSpringTwelveOn(@"captureReplaceFavoritesTab");
    if (role == HaogeCallRecorderRecordingTabVoicemail) return HaogeSpringTwelveOn(@"captureReplaceVoicemailTab");
    return NO;
}
static HaogeCallRecorderRecordingTabRole HaogeCallRecorderRecordingRole(UIViewController *controller, NSUInteger depth) {
    if (!controller || depth > 4 || [controller isKindOfClass:HaogeCallRecorderRecordingListViewController.class])
        return HaogeCallRecorderRecordingTabUnknown;
    // These four concrete classes are backed by Capture's actual registration sites.
    NSArray *names = @[@"MPFavoritesTableViewController", @"MPVoicemailTableViewController",
        @"PHVoicemailInboxListViewController", @"VMVoicemailListViewController"];
    for (NSUInteger index = 0; index < names.count; index++) {
        Class target = NSClassFromString(names[index]);
        if (target && [controller isKindOfClass:target])
            return index == 0 ? HaogeCallRecorderRecordingTabFavorites : HaogeCallRecorderRecordingTabVoicemail;
    }
    // Evidence-backed semantic fallback, ONLY inside an actual Phone tab's root hierarchy.
    // No guessed private class list, translated titles, item tags, or tab integer mapping.
    NSString *name = NSStringFromClass(controller.class);
    NSString *bundle = [NSBundle bundleForClass:controller.class].bundleIdentifier;
    if ([bundle hasPrefix:@"com.apple."] && ![name containsString:@"CarPlay"]) {
        if ([name containsString:@"Voicemail"]) return HaogeCallRecorderRecordingTabVoicemail;
        if ([name containsString:@"Favorites"]) return HaogeCallRecorderRecordingTabFavorites;
    }
    NSArray *children = [controller isKindOfClass:UINavigationController.class]
        ? (((UINavigationController *)controller).viewControllers.firstObject
            ? @[((UINavigationController *)controller).viewControllers.firstObject] : @[])
        : controller.childViewControllers;
    HaogeCallRecorderRecordingTabRole result = HaogeCallRecorderRecordingTabUnknown;
    for (UIViewController *child in children) {
        HaogeCallRecorderRecordingTabRole role = HaogeCallRecorderRecordingRole(child, depth + 1);
        if (role && result && role != result) return HaogeCallRecorderRecordingTabUnknown; // Ambiguous wrapper: fail closed.
        if (role) result = role;
    }
    return result;
}
static HaogeCallRecorderRecordingTabState *HaogeCallRecorderRecordingState(UITabBarController *owner) {
    HaogeCallRecorderRecordingTabState *state = objc_getAssociatedObject(owner, &HaogeCallRecorderRecordingTabStateKey);
    if (!state && (HaogeCallRecorderRecordingShouldReplace(HaogeCallRecorderRecordingTabFavorites) ||
                   HaogeCallRecorderRecordingShouldReplace(HaogeCallRecorderRecordingTabVoicemail))) {
        state = [HaogeCallRecorderRecordingTabState new];
        state.haoge_callrecorder_entries = @[];
        objc_setAssociatedObject(owner, &HaogeCallRecorderRecordingTabStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}
static HaogeCallRecorderRecordingTabEntry *HaogeCallRecorderRecordingEntry(NSArray<HaogeCallRecorderRecordingTabEntry *> *entries,
                                                                    UIViewController *controller) {
    for (HaogeCallRecorderRecordingTabEntry *entry in entries)
        if (controller == entry.haoge_callrecorder_original || controller == entry.haoge_callrecorder_replacement) return entry;
    return nil;
}
static UIViewController *HaogeCallRecorderRecordingResolve(UIViewController *controller,
    NSArray<HaogeCallRecorderRecordingTabEntry *> *before, NSArray<HaogeCallRecorderRecordingTabEntry *> *after) {
    HaogeCallRecorderRecordingTabEntry *old = HaogeCallRecorderRecordingEntry(before, controller);
    UIViewController *original = old ? old.haoge_callrecorder_original : controller;
    HaogeCallRecorderRecordingTabEntry *entry = HaogeCallRecorderRecordingEntry(after, original);
    return entry ? entry.haoge_callrecorder_replacement : original;
}
@interface HaogeCallRecorderRecordingTabDelegate : NSObject <UITabBarControllerDelegate>
@property(nonatomic, weak) UITabBarController *haoge_callrecorder_owner;
@property(nonatomic, weak) id<UITabBarControllerDelegate> haoge_callrecorder_original;
@end
@implementation HaogeCallRecorderRecordingTabDelegate
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.haoge_callrecorder_original respondsToSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector {
    id original = self.haoge_callrecorder_original;
    return [original respondsToSelector:selector] ? original : [super forwardingTargetForSelector:selector];
}
- (BOOL)haoge_callrecorder_manages:(UIViewController *)controller {
    HaogeCallRecorderRecordingTabState *state = objc_getAssociatedObject(self.haoge_callrecorder_owner, &HaogeCallRecorderRecordingTabStateKey);
    HaogeCallRecorderRecordingTabEntry *entry = HaogeCallRecorderRecordingEntry(state.haoge_callrecorder_entries, controller);
    return entry && controller == entry.haoge_callrecorder_replacement;
}
- (BOOL)tabBarController:(UITabBarController *)owner shouldSelectViewController:(UIViewController *)controller {
    if (owner == self.haoge_callrecorder_owner && [self haoge_callrecorder_manages:controller])
        return owner.selectedViewController != controller; // Consume RESELECT before native pop/reset handlers.
    id<UITabBarControllerDelegate> original = self.haoge_callrecorder_original;
    return [original respondsToSelector:_cmd] ? [original tabBarController:owner shouldSelectViewController:controller] : YES;
}
- (void)tabBarController:(UITabBarController *)owner didSelectViewController:(UIViewController *)controller {
    if (owner == self.haoge_callrecorder_owner && [self haoge_callrecorder_manages:controller]) return;
    id<UITabBarControllerDelegate> original = self.haoge_callrecorder_original;
    if ([original respondsToSelector:_cmd]) [original tabBarController:owner didSelectViewController:controller];
}
- (id<UIViewControllerAnimatedTransitioning>)tabBarController:(UITabBarController *)owner
    animationControllerForTransitionFromViewController:(UIViewController *)from toViewController:(UIViewController *)to {
    if (owner == self.haoge_callrecorder_owner && ([self haoge_callrecorder_manages:from] || [self haoge_callrecorder_manages:to])) return nil;
    id<UITabBarControllerDelegate> original = self.haoge_callrecorder_original;
    return [original respondsToSelector:_cmd]
        ? [original tabBarController:owner animationControllerForTransitionFromViewController:from toViewController:to] : nil;
}
@end
static void HaogeCallRecorderUpdateRecordingDelegate(UITabBarController *owner, HaogeCallRecorderRecordingTabState *state) {
    HaogeCallRecorderRecordingTabDelegate *proxy = state.haoge_callrecorder_delegate;
    if (state.haoge_callrecorder_entries.count) {
        if (!proxy) {
            proxy = [HaogeCallRecorderRecordingTabDelegate new];
            proxy.haoge_callrecorder_owner = owner;
            proxy.haoge_callrecorder_original = owner.delegate;
            state.haoge_callrecorder_delegate = proxy;
        }
        if (owner.delegate != proxy) owner.delegate = proxy;
    } else if (proxy) {
        // Restoring nil is intentional. Native delegate is weak, exactly like UIKit's property.
        if (owner.delegate == proxy) owner.delegate = proxy.haoge_callrecorder_original;
        state.haoge_callrecorder_delegate = nil;
    }
}
static void HaogeCallRecorderRetireRecordingEntry(HaogeCallRecorderRecordingTabEntry *entry) {
    // Only our own UI is touched; the retained native controller/nav items were never edited.
    HaogeCallRecorderRecordingListViewController *list =
        (HaogeCallRecorderRecordingListViewController *)entry.haoge_callrecorder_replacement.viewControllers.firstObject;
    if (list.isViewLoaded) {
        list.navigationItem.searchController.active = NO;
        [list haoge_callrecorder_stopPlayback]; // Also invalidates an in-flight playback/share snapshot.
    }
    if (entry.haoge_callrecorder_replacement.presentedViewController)
        [entry.haoge_callrecorder_replacement dismissViewControllerAnimated:NO completion:nil];
}
static NSArray<UIViewController *> *HaogeCallRecorderRecordingTabs(
    NSArray<UIViewController *> *incoming, HaogeCallRecorderRecordingTabState *state) {
    NSMutableArray *tabs = [NSMutableArray array];
    NSMutableArray *next = [NSMutableArray array];
    for (UIViewController *controller in incoming) {
        HaogeCallRecorderRecordingTabEntry *entry = HaogeCallRecorderRecordingEntry(state.haoge_callrecorder_entries, controller);
        UIViewController *original = entry ? entry.haoge_callrecorder_original : controller;
        HaogeCallRecorderRecordingTabRole role = entry ? entry.haoge_callrecorder_role : HaogeCallRecorderRecordingRole(original, 0);
        // Never resurrect a tab removed by PhoneTabs; a disabled, currently installed replacement is removed too.
        if (role && HaogeCallRecorderRecordingTabDisabled(role)) continue;
        if (!HaogeCallRecorderRecordingShouldReplace(role)) {
            [tabs addObject:original];
            continue;
        }
        if (!entry) {
            entry = [HaogeCallRecorderRecordingTabEntry new];
            entry.haoge_callrecorder_original = original;
            entry.haoge_callrecorder_role = role;
            HaogeCallRecorderRecordingListViewController *list = [HaogeCallRecorderRecordingListViewController new];
            list.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
            HaogeCallRecorderRecordingNavigationController *navigation =
                [[HaogeCallRecorderRecordingNavigationController alloc] initWithRootViewController:list];
            [list loadViewIfNeeded]; // Starts the initial index load even before the first tab appearance.
            navigation.navigationBar.prefersLargeTitles = NO;
            // Root cannot pop. Native voicemail callbacks still own ONLY the detached native nav.
            navigation.interactivePopGestureRecognizer.enabled = NO;
            UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:@"录音"
                image:[UIImage systemImageNamed:@"waveform"] tag:original.tabBarItem.tag];
            item.accessibilityIdentifier = role == HaogeCallRecorderRecordingTabFavorites
                ? @"haoge.callrecorder.recordings.favorites" : @"haoge.callrecorder.recordings.voicemail";
            navigation.tabBarItem = item;
            entry.haoge_callrecorder_replacement = navigation;
        }
        if (![next containsObject:entry]) [next addObject:entry];
        if (![tabs containsObject:entry.haoge_callrecorder_replacement]) [tabs addObject:entry.haoge_callrecorder_replacement];
    }
    for (HaogeCallRecorderRecordingTabEntry *entry in state.haoge_callrecorder_entries)
        if (![next containsObject:entry]) HaogeCallRecorderRetireRecordingEntry(entry);
    state.haoge_callrecorder_entries = next;
    return [tabs isEqualToArray:incoming] ? incoming : (incoming ? tabs : nil);
}
static void HaogeCallRecorderSelectRecordingController(UITabBarController *owner, UIViewController *controller) {
    SEL selector = @selector(setSelectedViewController:);
    IMP implementation = class_getMethodImplementation(UITabBarController.class, selector);
    ((void (*)(id, SEL, UIViewController *))implementation)(owner, selector, controller);
}

static void HaogeCallRecorderSetRecordingTabs(UITabBarController *owner, NSArray<UIViewController *> *incoming,
                                           void (^apply)(NSArray<UIViewController *> *)) {
    if (!NSThread.isMainThread) { apply(incoming); return; }
    [HaogeCallRecorderRecordingTabOwners addObject:owner];
    HaogeCallRecorderRecordingTabState *state = HaogeCallRecorderRecordingState(owner);
    if (!state) { apply(incoming); return; }
    if (state.haoge_callrecorder_applying) {
        // UIKit may forward the filtered array to its other setter; Phone may instead rebuild a native array.
        // Normalize BOTH cases. Reentrancy suppresses nested repair, never identity filtering.
        apply(HaogeCallRecorderRecordingTabs(incoming, state));
        return;
    }
    NSArray *before = state.haoge_callrecorder_entries;
    UIViewController *selected = owner.selectedViewController;
    state.haoge_callrecorder_pendingSelection = nil;
    state.haoge_callrecorder_applying = YES;
    @try {
        NSArray *tabs = HaogeCallRecorderRecordingTabs(incoming, state);
        HaogeCallRecorderUpdateRecordingDelegate(owner, state);
        apply(tabs);
        // A Phone override can call super with a cached native array, bypassing our entry setter hooks.
        // Verify once, then repair through the public UIKit base implementation, NOT the Phone override.
        NSArray *actual = owner.viewControllers;
        NSArray *checked = HaogeCallRecorderRecordingTabs(actual, state);
        if (![actual isEqualToArray:checked]) {
            SEL selector = @selector(setViewControllers:animated:);
            IMP implementation = class_getMethodImplementation(UITabBarController.class, selector);
            ((void (*)(id, SEL, NSArray *, BOOL))implementation)(owner, selector, checked, NO);
        }
        HaogeCallRecorderUpdateRecordingDelegate(owner, state);
        UIViewController *intent = state.haoge_callrecorder_pendingSelection ?: selected ?: owner.selectedViewController;
        UIViewController *resolved = HaogeCallRecorderRecordingResolve(intent, before, state.haoge_callrecorder_entries);
        if (resolved && [owner.viewControllers containsObject:resolved] && owner.selectedViewController != resolved)
            owner.selectedViewController = resolved;
        else if (owner.viewControllers.count && ![owner.viewControllers containsObject:owner.selectedViewController])
            owner.selectedViewController = owner.viewControllers.firstObject;
    } @finally {
        state.haoge_callrecorder_pendingSelection = nil;
        state.haoge_callrecorder_applying = NO;
    }
}
static void HaogeCallRecorderRefreshRecordingTabs(UITabBarController *owner) {
    if (!NSThread.isMainThread) return;
    [HaogeCallRecorderRecordingTabOwners addObject:owner];
    HaogeCallRecorderRecordingTabState *state = HaogeCallRecorderRecordingState(owner);
    if (!state || state.haoge_callrecorder_applying) return; // Default OFF: do not even reset the native array.
    HaogeCallRecorderSetRecordingTabs(owner, owner.viewControllers, ^(NSArray<UIViewController *> *tabs) {
        if (![owner.viewControllers isEqualToArray:tabs]) [owner setViewControllers:tabs animated:NO];
    });
}

%group HaogeCallRecorderRecordingPhoneTabs
%hook PhoneTabBarController
// Matched iOS 16.6.1 Phone: currentTabViewType -> tabTypeForViewController:
// compares controller identity and asserts on our replacement nav (Evidence/Phone-crash-analysis.md).
// Preserve native classification/Handoff by translating only this owner's replacement object.
- (int)tabTypeForViewController:(UIViewController *)controller {
    if (NSThread.isMainThread) {
        HaogeCallRecorderRecordingTabState *state = objc_getAssociatedObject(self, &HaogeCallRecorderRecordingTabStateKey);
        HaogeCallRecorderRecordingTabEntry *entry = HaogeCallRecorderRecordingEntry(state.haoge_callrecorder_entries, controller);
        if (entry && controller == entry.haoge_callrecorder_replacement && entry.haoge_callrecorder_original)
            return %orig(entry.haoge_callrecorder_original);
    }
    return %orig(controller); // Native, nil, foreign-owner, retired and unknown inputs are unchanged.
}
- (void)setDelegate:(id<UITabBarControllerDelegate>)delegate {
    HaogeCallRecorderRecordingTabState *state = objc_getAssociatedObject(self, &HaogeCallRecorderRecordingTabStateKey);
    HaogeCallRecorderRecordingTabDelegate *proxy = state.haoge_callrecorder_delegate;
    if (NSThread.isMainThread && state.haoge_callrecorder_entries.count && proxy && delegate != proxy) {
        proxy.haoge_callrecorder_original = delegate;
        %orig(proxy);
        return;
    }
    %orig(delegate);
}
- (void)setViewControllers:(NSArray<UIViewController *> *)controllers {
    HaogeCallRecorderSetRecordingTabs(self, controllers, ^(NSArray<UIViewController *> *tabs) { %orig(tabs); });
}
- (void)setViewControllers:(NSArray<UIViewController *> *)controllers animated:(BOOL)animated {
    HaogeCallRecorderSetRecordingTabs(self, controllers, ^(NSArray<UIViewController *> *tabs) { %orig(tabs, animated); });
}
- (void)setSelectedViewController:(UIViewController *)controller {
    HaogeCallRecorderRecordingTabState *state = objc_getAssociatedObject(self, &HaogeCallRecorderRecordingTabStateKey);
    if (NSThread.isMainThread && state) {
        HaogeCallRecorderRecordingTabEntry *entry = HaogeCallRecorderRecordingEntry(state.haoge_callrecorder_entries, controller);
        if (entry) {
            UIViewController *replacement = entry.haoge_callrecorder_replacement;
            if ([self.viewControllers containsObject:replacement])
                HaogeCallRecorderSelectRecordingController(self, replacement);
            else if (state.haoge_callrecorder_applying)
                state.haoge_callrecorder_pendingSelection = replacement;
            return; // Phone's setter only accepts its own native tab controllers.
        }
        if (controller && ![self.viewControllers containsObject:controller] &&
            HaogeCallRecorderRecordingTabDisabled(HaogeCallRecorderRecordingRole(controller, 0))) return;
    }
    %orig(controller);
}
- (void)viewWillAppear:(BOOL)animated {
    HaogeCallRecorderRefreshRecordingTabs(self);
    %orig(animated);
    // A native appearance implementation may have rebuilt its tabs through UIKit.
    HaogeCallRecorderRefreshRecordingTabs(self);
}
%end
%end

static void HaogeCallRecorderInstallRecordingTabHooks(void) {
    if (HaogeCallRecorderRecordingTabHooksInstalled || !NSThread.isMainThread) return;
    Class target = NSClassFromString(@"PhoneTabBarController");
    if (!target || ![target isSubclassOfClass:UITabBarController.class]) return;
    // The only private hook is evidence-backed int(self, SEL, object), not NSInteger.
    // Fail closed BEFORE installing replacement hooks if another Phone build changes this ABI.
    Method identity = class_getInstanceMethod(target, NSSelectorFromString(@"tabTypeForViewController:"));
    if (!identity || method_getNumberOfArguments(identity) != 3) return;
    char *resultType = method_copyReturnType(identity);
    char *controllerType = method_copyArgumentType(identity, 2);
    BOOL identityABI = resultType && controllerType &&
        strcmp(resultType, "i") == 0 && strcmp(controllerType, "@") == 0;
    free(resultType);
    free(controllerType);
    if (!identityABI) return;
    %init(HaogeCallRecorderRecordingPhoneTabs);
    HaogeCallRecorderRecordingTabHooksInstalled = YES;
}
static void HaogeCallRecorderDiscoverRecordingTabs(UIViewController *controller, NSUInteger depth) {
    if (!controller || depth > 12) return;
    Class target = NSClassFromString(@"PhoneTabBarController");
    if (target && [controller isKindOfClass:target]) {
        HaogeCallRecorderRefreshRecordingTabs((UITabBarController *)controller);
        return;
    }
    for (UIViewController *child in controller.childViewControllers)
        HaogeCallRecorderDiscoverRecordingTabs(child, depth + 1);
    HaogeCallRecorderDiscoverRecordingTabs(controller.presentedViewController, depth + 1);
}
static void HaogeCallRecorderRefreshKnownRecordingTabs(void) {
    HaogeCallRecorderInstallRecordingTabHooks();
    if (!HaogeCallRecorderRecordingTabHooksInstalled) return;
    for (UITabBarController *owner in HaogeCallRecorderRecordingTabOwners.allObjects)
        HaogeCallRecorderRefreshRecordingTabs(owner); // Includes off-screen tabs: restoration never requires view.window.
    if (!HaogeCallRecorderRecordingShouldReplace(HaogeCallRecorderRecordingTabFavorites) &&
        !HaogeCallRecorderRecordingShouldReplace(HaogeCallRecorderRecordingTabVoicemail)) return;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            HaogeCallRecorderDiscoverRecordingTabs(window.rootViewController, 0);
    }
}
%ctor {
    @autoreleasepool {
        haoge_callrecorder_installRecordingAccess();
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.mobilephone"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            HaogeCallRecorderRecordingTabOwners = [NSHashTable weakObjectsHashTable];
            HaogeCallRecorderRecordingObservers = [NSMutableArray array];
            for (NSString *name in @[NSBundleDidLoadNotification, UIApplicationDidFinishLaunchingNotification,
                                     UIApplicationDidBecomeActiveNotification, HaogeSpringTwelvePreferencesChanged]) {
                id observer = [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) { HaogeCallRecorderRefreshKnownRecordingTabs(); }];
                [HaogeCallRecorderRecordingObservers addObject:observer];
            }
            HaogeCallRecorderRefreshKnownRecordingTabs();
        });
    }
}
