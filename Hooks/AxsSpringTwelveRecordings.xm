// Clean-room recording browser only: this module never captures calls or imports audio.
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
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
#import "AxsSpringTwelveSwitches.h"
#import "AxsSpringTwelvePaths.h"

@interface AxsSpringTwelveRecording : NSObject
@property(nonatomic, copy) NSString *axs_springtwelve_name;
@property(nonatomic, strong) NSDate *axs_springtwelve_date;
@property(nonatomic) unsigned long long axs_springtwelve_size;
@property(nonatomic) unsigned long long axs_springtwelve_device;
@property(nonatomic) unsigned long long axs_springtwelve_inode;
@end
@implementation AxsSpringTwelveRecording
@end

static NSString * const AxsSpringTwelveRecordingsChanged = @"com.axs.springtwelve.preferences-changed";
static NSURL *AxsSpringTwelveRecordingsURL(void) {
    // Documents is user data, not a rootless installation resource.
    NSString *path = @"/var/mobile/Documents/CallRecordings";
    return path.isAbsolutePath ? [NSURL fileURLWithPath:path isDirectory:YES] : nil;
}
static BOOL AxsSpringTwelveOwnedRecordingName(NSString *name) {
    if (!name.length || ![name isEqualToString:name.lastPathComponent] || [name containsString:@"/"]) return NO;
    if ([name hasPrefix:@"AxsSpringTwelve-"] && [name hasSuffix:@".m4a"])
        return name.length > @"AxsSpringTwelve-.m4a".length;
    // Legacy ownership still requires an audio extension; arbitrary prefixed documents are excluded.
    return [name hasPrefix:@"SpringTwelve-"] && name.stringByDeletingPathExtension.length > @"SpringTwelve-".length &&
        [@[@"m4a", @"caf", @"wav", @"aif", @"aiff", @"mp3", @"aac"] containsObject:name.pathExtension.lowercaseString];
}
static NSError *AxsSpringTwelveRecordingError(int code) {
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:code ?: EIO userInfo:nil];
}
static int AxsSpringTwelveOpenRecordingDirectory(NSError **error) {
    NSURL *url = AxsSpringTwelveRecordingsURL();
    int descriptor = url ? open(url.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) : -1;
    if (descriptor < 0 && error) *error = AxsSpringTwelveRecordingError(url ? errno : EINVAL);
    return descriptor;
}
static BOOL AxsSpringTwelveRecordingMatches(AxsSpringTwelveRecording *record, const struct stat *info) {
    return S_ISREG(info->st_mode) && info->st_nlink == 1 &&
        (unsigned long long)info->st_dev == record.axs_springtwelve_device &&
        (unsigned long long)info->st_ino == record.axs_springtwelve_inode;
}
static NSArray<AxsSpringTwelveRecording *> *AxsSpringTwelveReadRecordingIndex(NSError **error) {
    int directory = AxsSpringTwelveOpenRecordingDirectory(error);
    if (directory < 0) {
        if (error && (*error).code == ENOENT) *error = nil; // Missing folder is an empty index, not an import request.
        return @[];
    }
    DIR *stream = fdopendir(directory); // Owns the descriptor on success.
    if (!stream) {
        int code = errno; close(directory);
        if (error) *error = AxsSpringTwelveRecordingError(code);
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
            if (!AxsSpringTwelveOwnedRecordingName(name)) continue; // No metadata/content access for other names.
            struct stat info;
            if (fstatat(directory, entry->d_name, &info, AT_SYMLINK_NOFOLLOW) != 0 ||
                !S_ISREG(info.st_mode) || info.st_nlink != 1) continue;
            AxsSpringTwelveRecording *record = [AxsSpringTwelveRecording new];
            record.axs_springtwelve_name = name;
            record.axs_springtwelve_date = [NSDate dateWithTimeIntervalSince1970:info.st_mtimespec.tv_sec + info.st_mtimespec.tv_nsec / 1e9];
            record.axs_springtwelve_size = (unsigned long long)MAX((off_t)0, info.st_size);
            record.axs_springtwelve_device = (unsigned long long)info.st_dev;
            record.axs_springtwelve_inode = (unsigned long long)info.st_ino;
            [records addObject:record];
        }
    }
    closedir(stream);
    if (scanError && error) *error = AxsSpringTwelveRecordingError(scanError);
    [records sortUsingComparator:^NSComparisonResult(AxsSpringTwelveRecording *a, AxsSpringTwelveRecording *b) {
        NSComparisonResult order = [b.axs_springtwelve_date compare:a.axs_springtwelve_date];
        return order == NSOrderedSame ? [a.axs_springtwelve_name compare:b.axs_springtwelve_name] : order;
    }];
    return records;
}
// Only generated, private temporary directories may be removed by this helper.
static void AxsSpringTwelveRemoveRecordingSnapshot(NSURL *url) {
    if (!url) return;
    NSURL *parent = url.URLByDeletingLastPathComponent;
    if ([parent.lastPathComponent hasPrefix:@"AxsSpringTwelve-Recording-"] &&
        [parent.URLByDeletingLastPathComponent.path.stringByStandardizingPath isEqualToString:NSTemporaryDirectory().stringByStandardizingPath])
        [[NSFileManager defaultManager] removeItemAtURL:parent error:NULL];
}
// Copy through an anchored, no-follow descriptor. Player/share never reopen a mutable source path.
static NSURL *AxsSpringTwelveRecordingSnapshot(AxsSpringTwelveRecording *record, NSError **error) {
    if (!AxsSpringTwelveOwnedRecordingName(record.axs_springtwelve_name)) {
        if (error) *error = AxsSpringTwelveRecordingError(EINVAL);
        return nil;
    }
    int directory = AxsSpringTwelveOpenRecordingDirectory(error);
    if (directory < 0) return nil;
    int source = openat(directory, record.axs_springtwelve_name.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    int code = source < 0 ? errno : 0;
    close(directory);
    struct stat before = {}, after = {};
    if (!code && fstat(source, &before) != 0) code = errno;
    if (!code && !AxsSpringTwelveRecordingMatches(record, &before)) code = ESTALE;
    if (code) {
        if (source >= 0) close(source);
        if (error) *error = AxsSpringTwelveRecordingError(code);
        return nil;
    }
    NSURL *folder = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[@"AxsSpringTwelve-Recording-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:NO
        attributes:@{NSFilePosixPermissions: @0700} error:error]) { close(source); return nil; }
    NSURL *copy = [folder URLByAppendingPathComponent:record.axs_springtwelve_name isDirectory:NO];
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
        AxsSpringTwelveRemoveRecordingSnapshot(copy);
        if (error) *error = AxsSpringTwelveRecordingError(code);
        return nil;
    }
    return copy;
}
static BOOL AxsSpringTwelveDeleteRecording(AxsSpringTwelveRecording *record, NSError **error) {
    if (!AxsSpringTwelveOwnedRecordingName(record.axs_springtwelve_name)) {
        if (error) *error = AxsSpringTwelveRecordingError(EINVAL);
        return NO;
    }
    int directory = AxsSpringTwelveOpenRecordingDirectory(error);
    if (directory < 0) return NO;
    struct stat info;
    int code = 0;
    const char *name = record.axs_springtwelve_name.fileSystemRepresentation;
    if (fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) != 0) code = errno;
    else if (!AxsSpringTwelveRecordingMatches(record, &info)) code = ESTALE;
    else if (unlinkat(directory, name, 0) != 0) code = errno; // Never recursive; never follows a link.
    close(directory);
    if (code && error) *error = AxsSpringTwelveRecordingError(code);
    return code == 0;
}

@interface AxsSpringTwelveRecordingListViewController : UIViewController
    <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, AVAudioPlayerDelegate, UIDocumentPickerDelegate> {
    UITableView *_axs_springtwelve_table;
    UISearchController *_axs_springtwelve_search;
    UILabel *_axs_springtwelve_empty;
    UILabel *_axs_springtwelve_nowPlaying;
    UILabel *_axs_springtwelve_time;
    UISlider *_axs_springtwelve_seek;
    UIButton *_axs_springtwelve_play;
    UIButton *_axs_springtwelve_stop;
    UIButton *_axs_springtwelve_share;
    NSDateFormatter *_axs_springtwelve_dates;
    NSArray<AxsSpringTwelveRecording *> *_axs_springtwelve_records;
    NSArray<AxsSpringTwelveRecording *> *_axs_springtwelve_filtered;
    AxsSpringTwelveRecording *_axs_springtwelve_selected;
    AVAudioPlayer *_axs_springtwelve_player;
    NSURL *_axs_springtwelve_snapshot;
    NSTimer *_axs_springtwelve_timer;
    dispatch_queue_t _axs_springtwelve_io;
    NSUInteger _axs_springtwelve_loadToken;
    NSUInteger _axs_springtwelve_actionToken;
    NSString *_axs_springtwelve_indexError;
}
- (void)axs_springtwelve_openRecordingsFolder;
@end

@implementation AxsSpringTwelveRecordingListViewController
- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = @"通话录音";
        _axs_springtwelve_records = @[];
        _axs_springtwelve_filtered = @[];
        _axs_springtwelve_io = dispatch_queue_create("com.axs.springtwelve.recordings.io", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
- (UIButton *)axs_springtwelve_button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _axs_springtwelve_dates = [NSDateFormatter new];
    _axs_springtwelve_dates.dateStyle = NSDateFormatterMediumStyle;
    _axs_springtwelve_dates.timeStyle = NSDateFormatterShortStyle;
    _axs_springtwelve_search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _axs_springtwelve_search.searchResultsUpdater = self;
    _axs_springtwelve_search.obscuresBackgroundDuringPresentation = NO;
    _axs_springtwelve_search.searchBar.placeholder = @"搜索文件名或日期";
    self.navigationItem.searchController = _axs_springtwelve_search;
    self.definesPresentationContext = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"文件夹"
        style:UIBarButtonItemStylePlain target:self action:@selector(axs_springtwelve_openRecordingsFolder)];
    _axs_springtwelve_table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _axs_springtwelve_table.dataSource = self;
    _axs_springtwelve_table.delegate = self;
    _axs_springtwelve_table.rowHeight = UITableViewAutomaticDimension;
    _axs_springtwelve_table.estimatedRowHeight = 68;
    _axs_springtwelve_table.refreshControl = [UIRefreshControl new];
    [_axs_springtwelve_table.refreshControl addTarget:self action:@selector(axs_springtwelve_reload)
        forControlEvents:UIControlEventValueChanged];
    _axs_springtwelve_empty = [UILabel new];
    _axs_springtwelve_empty.numberOfLines = 0;
    _axs_springtwelve_empty.textAlignment = NSTextAlignmentCenter;
    _axs_springtwelve_empty.textColor = UIColor.secondaryLabelColor;
    _axs_springtwelve_empty.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _axs_springtwelve_empty.adjustsFontForContentSizeCategory = YES;
    _axs_springtwelve_table.backgroundView = _axs_springtwelve_empty;
    _axs_springtwelve_nowPlaying = [UILabel new];
    _axs_springtwelve_nowPlaying.numberOfLines = 2;
    _axs_springtwelve_nowPlaying.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    _axs_springtwelve_nowPlaying.adjustsFontForContentSizeCategory = YES;
    _axs_springtwelve_time = [UILabel new];
    _axs_springtwelve_time.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    _axs_springtwelve_time.textAlignment = NSTextAlignmentCenter;
    _axs_springtwelve_seek = [UISlider new];
    _axs_springtwelve_seek.accessibilityLabel = @"播放进度";
    [_axs_springtwelve_seek addTarget:self action:@selector(axs_springtwelve_seekChanged)
        forControlEvents:UIControlEventValueChanged];
    _axs_springtwelve_play = [self axs_springtwelve_button:@"播放" action:@selector(axs_springtwelve_togglePlayback)];
    _axs_springtwelve_stop = [self axs_springtwelve_button:@"停止" action:@selector(axs_springtwelve_stopPlayback)];
    _axs_springtwelve_share = [self axs_springtwelve_button:@"分享" action:@selector(axs_springtwelve_shareSelected)];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[_axs_springtwelve_play, _axs_springtwelve_stop, _axs_springtwelve_share]];
    buttons.distribution = UIStackViewDistributionFillEqually;
    UIStackView *player = [[UIStackView alloc] initWithArrangedSubviews:@[_axs_springtwelve_nowPlaying, _axs_springtwelve_seek, _axs_springtwelve_time, buttons]];
    player.axis = UILayoutConstraintAxisVertical;
    player.spacing = 4;
    player.layoutMarginsRelativeArrangement = YES;
    player.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(8, 16, 8, 16);
    _axs_springtwelve_table.translatesAutoresizingMaskIntoConstraints = NO;
    player.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_axs_springtwelve_table];
    [self.view addSubview:player];
    [NSLayoutConstraint activateConstraints:@[
        [_axs_springtwelve_table.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_axs_springtwelve_table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_axs_springtwelve_table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_axs_springtwelve_table.bottomAnchor constraintEqualToAnchor:player.topAnchor],
        [player.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [player.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [player.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [buttons.heightAnchor constraintGreaterThanOrEqualToConstant:44]
    ]];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(axs_springtwelve_preferencesChanged:) name:AxsSpringTwelveRecordingsChanged object:nil];
    [center addObserver:self selector:@selector(axs_springtwelve_suspend:) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(axs_springtwelve_preferencesChanged:) name:UIApplicationDidBecomeActiveNotification object:nil];
    // Do not change the host Phone process's shared audio category, route, or activation state.
    for (NSString *name in @[@"AVAudioSessionInterruptionNotification", @"AVAudioSessionRouteChangeNotification", @"AVAudioSessionMediaServicesWereResetNotification"])
        [center addObserver:self selector:@selector(axs_springtwelve_suspend:) name:name object:nil];
    [self axs_springtwelve_updatePlayer];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self axs_springtwelve_reload];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self axs_springtwelve_stopPlayback];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_axs_springtwelve_timer invalidate];
    _axs_springtwelve_player.delegate = nil;
    [_axs_springtwelve_player stop];
    AxsSpringTwelveRemoveRecordingSnapshot(_axs_springtwelve_snapshot);
}
- (void)axs_springtwelve_error:(NSString *)message {
    if (self.presentedViewController || !self.viewIfLoaded.window) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"通话录音" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)axs_springtwelve_reload {
    NSUInteger token = ++_axs_springtwelve_loadToken;
    BOOL enabled = AxsSpringTwelveOn(@"callRecordingListEnabled");
    self.navigationItem.rightBarButtonItem.enabled = enabled;
    if (!enabled) {
        [self axs_springtwelve_stopPlayback];
        _axs_springtwelve_records = @[];
        _axs_springtwelve_indexError = nil;
        [self axs_springtwelve_filter];
        [_axs_springtwelve_table.refreshControl endRefreshing];
        return;
    }
    __weak AxsSpringTwelveRecordingListViewController *weakSelf = self;
    dispatch_async(_axs_springtwelve_io, ^{
        @autoreleasepool {
            NSError *error = nil;
            NSArray *records = AxsSpringTwelveReadRecordingIndex(&error);
            dispatch_async(dispatch_get_main_queue(), ^{
                AxsSpringTwelveRecordingListViewController *owner = weakSelf;
                if (!owner || token != owner->_axs_springtwelve_loadToken) return;
                owner->_axs_springtwelve_records = AxsSpringTwelveOn(@"callRecordingListEnabled") ? records : @[];
                owner->_axs_springtwelve_indexError = error.localizedDescription;
                [owner axs_springtwelve_filter];
                [owner->_axs_springtwelve_table.refreshControl endRefreshing];
            });
        }
    });
}
- (void)axs_springtwelve_filter {
    NSString *query = [_axs_springtwelve_search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *filtered = [NSMutableArray array];
    for (AxsSpringTwelveRecording *record in _axs_springtwelve_records) {
        NSString *date = [_axs_springtwelve_dates stringFromDate:record.axs_springtwelve_date];
        if (!query.length || [record.axs_springtwelve_name rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound ||
            [date rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) [filtered addObject:record];
    }
    _axs_springtwelve_filtered = filtered;
    if (!AxsSpringTwelveOn(@"callRecordingListEnabled")) _axs_springtwelve_empty.text = @"录音列表已关闭";
    else if (_axs_springtwelve_indexError.length) _axs_springtwelve_empty.text = [@"无法读取录音目录：\n" stringByAppendingString:_axs_springtwelve_indexError];
    else _axs_springtwelve_empty.text = query.length ? @"没有匹配的录音" : @"暂无 SpringTwelve 录音\n仅管理本插件命名的音频文件；不会自动录音或导入其他录音。";
    _axs_springtwelve_empty.hidden = filtered.count != 0;
    [_axs_springtwelve_table reloadData];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self axs_springtwelve_filter]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _axs_springtwelve_filtered.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AxsSpringTwelveRecording"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AxsSpringTwelveRecording"];
    AxsSpringTwelveRecording *record = _axs_springtwelve_filtered[(NSUInteger)indexPath.row];
    cell.textLabel.text = record.axs_springtwelve_name;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@",
        [_axs_springtwelve_dates stringFromDate:record.axs_springtwelve_date],
        [NSByteCountFormatter stringFromByteCount:(long long)record.axs_springtwelve_size countStyle:NSByteCountFormatterCountStyleFile],
        record.axs_springtwelve_name.pathExtension.uppercaseString];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ((NSUInteger)indexPath.row < _axs_springtwelve_filtered.count)
        [self axs_springtwelve_prepare:_axs_springtwelve_filtered[(NSUInteger)indexPath.row] share:NO];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row >= _axs_springtwelve_filtered.count || !AxsSpringTwelveOn(@"callRecordingListEnabled")) return nil;
    AxsSpringTwelveRecording *record = _axs_springtwelve_filtered[(NSUInteger)indexPath.row];
    __weak AxsSpringTwelveRecordingListViewController *weakSelf = self;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除"
        handler:^(UIContextualAction *action, UIView *view, void (^complete)(BOOL)) {
            complete(NO); // Confirmation happens before any filesystem mutation.
            [weakSelf axs_springtwelve_confirmDelete:record];
        }];
    UIContextualAction *share = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"分享"
        handler:^(UIContextualAction *action, UIView *view, void (^complete)(BOOL)) {
            complete(YES);
            [weakSelf axs_springtwelve_prepare:record share:YES];
        }];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[remove, share]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}
- (void)axs_springtwelve_confirmDelete:(AxsSpringTwelveRecording *)record {
    if (!AxsSpringTwelveOn(@"callRecordingListEnabled") || self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除此录音？" message:record.axs_springtwelve_name preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak AxsSpringTwelveRecordingListViewController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        AxsSpringTwelveRecordingListViewController *owner = weakSelf;
        if (!owner || !AxsSpringTwelveOn(@"callRecordingListEnabled")) return;
        // Cancel pending playback/export too, so deletion cannot resurrect a stale selection.
        [owner axs_springtwelve_stopPlayback];
        dispatch_async(owner->_axs_springtwelve_io, ^{
            NSError *error = nil;
            if (AxsSpringTwelveOn(@"callRecordingListEnabled")) AxsSpringTwelveDeleteRecording(record, &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf axs_springtwelve_reload];
                if (error) [weakSelf axs_springtwelve_error:error.localizedDescription];
            });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)axs_springtwelve_preferencesChanged:(NSNotification *)note {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self axs_springtwelve_preferencesChanged:note]; });
        return;
    }
    if (!AxsSpringTwelveOn(@"callRecordingListEnabled")) [self axs_springtwelve_stopPlayback];
    if (self.isViewLoaded) [self axs_springtwelve_reload];
}
- (void)axs_springtwelve_suspend:(NSNotification *)note {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self axs_springtwelve_suspend:note]; });
        return;
    }
    [self axs_springtwelve_stopPlayback];
}
- (void)axs_springtwelve_prepare:(AxsSpringTwelveRecording *)record share:(BOOL)share {
    if (!AxsSpringTwelveOn(@"callRecordingListEnabled") || self.presentedViewController) return;
    if (!share) [self axs_springtwelve_stopPlayback];
    NSUInteger token = ++_axs_springtwelve_actionToken;
    __weak AxsSpringTwelveRecordingListViewController *weakSelf = self;
    dispatch_async(_axs_springtwelve_io, ^{
        @autoreleasepool {
            NSError *error = nil;
            NSURL *snapshot = AxsSpringTwelveOn(@"callRecordingListEnabled") ? AxsSpringTwelveRecordingSnapshot(record, &error) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                AxsSpringTwelveRecordingListViewController *owner = weakSelf;
                if (!owner || token != owner->_axs_springtwelve_actionToken || !AxsSpringTwelveOn(@"callRecordingListEnabled") || !owner.viewIfLoaded.window) {
                    AxsSpringTwelveRemoveRecordingSnapshot(snapshot);
                    return;
                }
                if (!snapshot) { [owner axs_springtwelve_error:error.localizedDescription ?: @"无法读取此录音，请刷新后重试。"]; return; }
                if (share) {
                    if (owner.presentedViewController) { AxsSpringTwelveRemoveRecordingSnapshot(snapshot); return; }
                    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[snapshot] applicationActivities:nil];
                    activity.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *activityError) {
                        AxsSpringTwelveRemoveRecordingSnapshot(snapshot);
                    };
                    activity.popoverPresentationController.sourceView = owner.view;
                    activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(owner.view.bounds), CGRectGetMaxY(owner.view.bounds) - 40, 1, 1);
                    [owner presentViewController:activity animated:YES completion:nil];
                } else {
                    // Runtime lookup avoids requiring an AVFoundation Makefile/linker change.
                    static Class AxsSpringTwelveAudioPlayerClass;
                    static dispatch_once_t once;
                    dispatch_once(&once, ^{
                        dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_LAZY | RTLD_LOCAL);
                        AxsSpringTwelveAudioPlayerClass = NSClassFromString(@"AVAudioPlayer");
                    });
                    NSError *playerError = nil;
                    AVAudioPlayer *player = [(AVAudioPlayer *)[AxsSpringTwelveAudioPlayerClass alloc] initWithContentsOfURL:snapshot error:&playerError];
                    if (!player || ![player prepareToPlay]) {
                        AxsSpringTwelveRemoveRecordingSnapshot(snapshot);
                        [owner axs_springtwelve_error:playerError.localizedDescription ?: @"系统无法解码此录音。"];
                        return;
                    }
                    owner->_axs_springtwelve_selected = record;
                    owner->_axs_springtwelve_snapshot = snapshot;
                    owner->_axs_springtwelve_player = player;
                    player.delegate = owner;
                    if (![player play]) {
                        [owner axs_springtwelve_stopPlayback];
                        [owner axs_springtwelve_error:@"无法开始播放；请确认电话音频会话当前可用。"];
                        return;
                    }
                    owner->_axs_springtwelve_timer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
                        [weakSelf axs_springtwelve_updatePlayer];
                    }];
                    [NSRunLoop.mainRunLoop addTimer:owner->_axs_springtwelve_timer forMode:NSRunLoopCommonModes];
                    [owner axs_springtwelve_updatePlayer];
                }
            });
        }
    });
}
- (void)axs_springtwelve_togglePlayback {
    if (!AxsSpringTwelveOn(@"callRecordingListEnabled")) { [self axs_springtwelve_stopPlayback]; return; }
    if (_axs_springtwelve_player.isPlaying) [_axs_springtwelve_player pause];
    else if (_axs_springtwelve_player && ![_axs_springtwelve_player play]) [self axs_springtwelve_error:@"无法恢复播放。"];
    [self axs_springtwelve_updatePlayer];
}
- (void)axs_springtwelve_stopPlayback {
    ++_axs_springtwelve_actionToken;
    [_axs_springtwelve_timer invalidate];
    _axs_springtwelve_timer = nil;
    _axs_springtwelve_player.delegate = nil;
    [_axs_springtwelve_player stop];
    _axs_springtwelve_player = nil;
    _axs_springtwelve_selected = nil;
    AxsSpringTwelveRemoveRecordingSnapshot(_axs_springtwelve_snapshot);
    _axs_springtwelve_snapshot = nil;
    [self axs_springtwelve_updatePlayer];
}
- (void)axs_springtwelve_seekChanged {
    if (AxsSpringTwelveOn(@"callRecordingListEnabled") && _axs_springtwelve_player)
        _axs_springtwelve_player.currentTime = _axs_springtwelve_seek.value;
    [self axs_springtwelve_updatePlayer];
}
- (void)axs_springtwelve_shareSelected {
    if (_axs_springtwelve_selected) [self axs_springtwelve_prepare:_axs_springtwelve_selected share:YES];
}
- (void)axs_springtwelve_updatePlayer {
    BOOL available = _axs_springtwelve_player != nil && AxsSpringTwelveOn(@"callRecordingListEnabled");
    _axs_springtwelve_play.enabled = available;
    _axs_springtwelve_stop.enabled = available;
    _axs_springtwelve_share.enabled = available;
    _axs_springtwelve_seek.enabled = available;
    [_axs_springtwelve_play setTitle:_axs_springtwelve_player.isPlaying ? @"暂停" : @"播放" forState:UIControlStateNormal];
    _axs_springtwelve_nowPlaying.text = _axs_springtwelve_selected.axs_springtwelve_name ?: @"选择录音以播放；左滑可分享或删除";
    NSTimeInterval duration = MAX(0, _axs_springtwelve_player.duration);
    NSTimeInterval elapsed = MAX(0, _axs_springtwelve_player.currentTime);
    if (!isfinite(duration)) duration = 0;
    if (!isfinite(elapsed)) elapsed = 0;
    _axs_springtwelve_seek.maximumValue = (float)MAX(1, duration);
    if (!_axs_springtwelve_seek.isTracking) _axs_springtwelve_seek.value = (float)elapsed;
    _axs_springtwelve_time.text = [NSString stringWithFormat:@"%02lld:%02lld / %02lld:%02lld",
        (long long)elapsed / 60, (long long)elapsed % 60, (long long)duration / 60, (long long)duration % 60];
}
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (player != self->_axs_springtwelve_player) return;
        [self axs_springtwelve_stopPlayback];
        if (!flag) [self axs_springtwelve_error:@"录音播放未能完成。"];
    });
}
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (player != self->_axs_springtwelve_player) return;
        [self axs_springtwelve_stopPlayback];
        [self axs_springtwelve_error:error.localizedDescription ?: @"录音解码失败。"];
    });
}
- (void)axs_springtwelve_openRecordingsFolder {
    if (!AxsSpringTwelveOn(@"callRecordingListEnabled") || self.presentedViewController) return;
    NSError *error = nil;
    int descriptor = AxsSpringTwelveOpenRecordingDirectory(&error);
    if (descriptor < 0 && error.code == ENOENT) {
        NSURL *url = AxsSpringTwelveRecordingsURL();
        if (url && [[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES
            attributes:@{NSFilePosixPermissions: @0700} error:&error]) descriptor = AxsSpringTwelveOpenRecordingDirectory(&error);
    }
    if (descriptor < 0) { [self axs_springtwelve_error:error.localizedDescription ?: @"无法打开录音目录。"]; return; }
    close(descriptor);
    dlopen("/System/Library/Frameworks/UniformTypeIdentifiers.framework/UniformTypeIdentifiers", RTLD_LAZY | RTLD_LOCAL);
    Class typeClass = NSClassFromString(@"UTType");
    UTType *folder = [typeClass respondsToSelector:@selector(typeWithIdentifier:)] ? [typeClass typeWithIdentifier:@"public.folder"] : nil;
    if (!folder || ![UIDocumentPickerViewController instancesRespondToSelector:@selector(initForOpeningContentTypes:asCopy:)]) {
        [self axs_springtwelve_error:@"此系统不提供可用的文件夹浏览器。"]; return;
    }
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[folder] asCopy:NO];
    picker.directoryURL = AxsSpringTwelveRecordingsURL();
    picker.allowsMultipleSelection = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    // Folder navigation only. Never access, import, persist, or enumerate the user's selection.
}
@end

// Guarded, process-scoped hooks. Unknown controllers/tab identities are deliberately left alone.
static NSMutableSet<NSString *> *AxsSpringTwelveHookedRecordingClasses;
static NSMutableArray *AxsSpringTwelveRecordingObservers;

static NSInteger AxsSpringTwelveRecordingTabRole(UIViewController *controller) {
    NSArray *favorites = @[@"FavoritesListViewController", @"PHFavoritesListViewController", @"PHFavoritesViewController", @"FavoritesViewController", @"MPFavoritesTableViewController"];
    NSArray *voicemail = @[@"VoicemailNavigationController", @"PHVoicemailNavigationController", @"VoicemailViewController",
        @"PHVoicemailViewController", @"MPVoicemailTableViewController", @"PHVoicemailInboxListViewController", @"VMVoicemailListViewController"];
    NSArray *candidates = [controller isKindOfClass:UINavigationController.class] && ((UINavigationController *)controller).viewControllers.firstObject
        ? @[controller, ((UINavigationController *)controller).viewControllers.firstObject] : @[controller];
    for (UIViewController *candidate in candidates) {
        for (NSString *name in favorites) {
            Class target = NSClassFromString(name);
            if (target && [target isSubclassOfClass:UIViewController.class] && [candidate isKindOfClass:target]) return 1;
        }
        for (NSString *name in voicemail) {
            Class target = NSClassFromString(name);
            if (target && [target isSubclassOfClass:UIViewController.class] && [candidate isKindOfClass:target]) return 2;
        }
    }
    return 0;
}

// Guarded, process-scoped tab replacement. Mirrors the clean-room MUtool
// approach: hook the known Favorites/Voicemail controllers' appearance and
// mount the recording list as a child view controller, instead of swapping the
// tab controller's viewControllers array (which depends on private class names
// and signatures that are not stable across builds).
static char AxsSpringTwelveRecordingMountKey;
static char AxsSpringTwelveRecordingRoleKey;
static char AxsSpringTwelveOriginalTabItemKey;
static char AxsSpringTwelveOriginalNavTitleKey;
static char AxsSpringTwelveOriginalNavLeftKey;
static char AxsSpringTwelveOriginalNavRightKey;
static char AxsSpringTwelveOriginalNavSearchKey;
static NSHashTable *AxsSpringTwelveMountedRecordingHosts;

static BOOL AxsSpringTwelveRecordingShouldReplace(NSInteger role) {
    if (!AxsSpringTwelveOn(@"callRecordingListEnabled")) return NO;
    if (role == 1) return AxsSpringTwelveOn(@"captureReplaceFavoritesTab");
    if (role == 2) return AxsSpringTwelveOn(@"captureReplaceVoicemailTab");
    return NO;
}

static void AxsSpringTwelveUnmountRecordingChild(UIViewController *host) {
    if (!host) return;
    UIViewController *list = objc_getAssociatedObject(host, &AxsSpringTwelveRecordingMountKey);
    if ([list isKindOfClass:UIViewController.class]) {
        [list willMoveToParentViewController:nil];
        [list.view removeFromSuperview];
        [list removeFromParentViewController];
    }
    objc_setAssociatedObject(host, &AxsSpringTwelveRecordingMountKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UITabBarItem *originalItem = objc_getAssociatedObject(host, &AxsSpringTwelveOriginalTabItemKey);
    if ([originalItem isKindOfClass:UITabBarItem.class]) host.tabBarItem = originalItem;
    NSString *originalTitle = objc_getAssociatedObject(host, &AxsSpringTwelveOriginalNavTitleKey);
    if ([originalTitle isKindOfClass:NSString.class]) host.navigationItem.title = originalTitle;
    NSArray *left = objc_getAssociatedObject(host, &AxsSpringTwelveOriginalNavLeftKey);
    if ([left isKindOfClass:NSArray.class]) host.navigationItem.leftBarButtonItems = left;
    NSArray *right = objc_getAssociatedObject(host, &AxsSpringTwelveOriginalNavRightKey);
    if ([right isKindOfClass:NSArray.class]) host.navigationItem.rightBarButtonItems = right;
    UISearchController *search = objc_getAssociatedObject(host, &AxsSpringTwelveOriginalNavSearchKey);
    if ([search isKindOfClass:UISearchController.class] || search == nil)
        host.navigationItem.searchController = search;

    objc_setAssociatedObject(host, &AxsSpringTwelveOriginalTabItemKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host, &AxsSpringTwelveOriginalNavTitleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host, &AxsSpringTwelveOriginalNavLeftKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host, &AxsSpringTwelveOriginalNavRightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host, &AxsSpringTwelveOriginalNavSearchKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void AxsSpringTwelveMountRecordingChild(UIViewController *host, NSInteger role) {
    if (!host) return;
    if (![host isViewLoaded] || !host.view.window) {
        // Not yet on screen; the viewDidAppear hook retries.
        return;
    }
    BOOL shouldReplace = AxsSpringTwelveRecordingShouldReplace(role);
    NSInteger mountedRole = [objc_getAssociatedObject(host, &AxsSpringTwelveRecordingRoleKey) integerValue];
    if (!shouldReplace || role != mountedRole) {
        AxsSpringTwelveUnmountRecordingChild(host);
        objc_setAssociatedObject(host, &AxsSpringTwelveRecordingRoleKey, @(role), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!shouldReplace) return;
    }
    if (objc_getAssociatedObject(host, &AxsSpringTwelveRecordingMountKey)) return;

    AxsSpringTwelveRecordingListViewController *list = [AxsSpringTwelveRecordingListViewController new];
    [list view]; // Force viewDidLoad so the search controller / folder button exist.

    UITabBarItem *originalItem = host.tabBarItem;
    if (originalItem) {
        objc_setAssociatedObject(host, &AxsSpringTwelveOriginalTabItemKey, originalItem, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:@"录音"
            image:[UIImage systemImageNamed:@"waveform"] tag:originalItem.tag];
        item.accessibilityIdentifier = role == 1 ? @"axs.springtwelve.recordings.favorites" : @"axs.springtwelve.recordings.voicemail";
        host.tabBarItem = item;
    }
    objc_setAssociatedObject(host, &AxsSpringTwelveOriginalNavTitleKey, host.navigationItem.title, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host, &AxsSpringTwelveOriginalNavLeftKey, host.navigationItem.leftBarButtonItems, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host, &AxsSpringTwelveOriginalNavRightKey, host.navigationItem.rightBarButtonItems, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host, &AxsSpringTwelveOriginalNavSearchKey, host.navigationItem.searchController, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Adopt the list's search bar and folder button on the host's navigation bar.
    host.navigationItem.title = @"通话录音";
    host.navigationItem.leftBarButtonItems = @[];
    host.navigationItem.rightBarButtonItems = list.navigationItem.rightBarButtonItems;
    host.navigationItem.searchController = list.navigationItem.searchController;

    [host addChildViewController:list];
    list.view.frame = host.view.bounds;
    list.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host.view addSubview:list.view];
    [list didMoveToParentViewController:host];
    objc_setAssociatedObject(host, &AxsSpringTwelveRecordingMountKey, list, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host, &AxsSpringTwelveRecordingRoleKey, @(role), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [AxsSpringTwelveMountedRecordingHosts addObject:host];
}

static void AxsSpringTwelveUpdateRecordingTab(UIViewController *controller) {
    if (!NSThread.isMainThread || !controller) return;
    NSInteger role = AxsSpringTwelveRecordingTabRole(controller);
    if (role == 0) return;
    AxsSpringTwelveMountRecordingChild(controller, role);
}

static void AxsSpringTwelveSwizzleAppearance(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    IMP original = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    IMP replacement = imp_implementationWithBlock(^(UIViewController *vc, BOOL animated) {
        ((void (*)(id, SEL, BOOL))original)(vc, selector, animated);
        AxsSpringTwelveUpdateRecordingTab(vc);
    });
    if (!class_addMethod(cls, selector, replacement, types))
        class_replaceMethod(cls, selector, replacement, types);
}

static void AxsSpringTwelveInstallRecordingTabHooks(void) {
    if (!NSThread.isMainThread || ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.mobilephone"]) return;
    NSArray *concrete = @[@"MPFavoritesTableViewController", @"MPVoicemailTableViewController",
                          @"PHVoicemailInboxListViewController", @"VMVoicemailListViewController"];
    for (NSString *name in concrete) {
        Class cls = NSClassFromString(name);
        if (!cls || ![cls isSubclassOfClass:UIViewController.class]) continue;
        if ([AxsSpringTwelveHookedRecordingClasses containsObject:name]) continue;
        AxsSpringTwelveSwizzleAppearance(cls, @selector(viewWillAppear:));
        AxsSpringTwelveSwizzleAppearance(cls, @selector(viewDidAppear:));
        [AxsSpringTwelveHookedRecordingClasses addObject:name];
    }
    // Global UIViewController fallback (MUtool does the same). Role detection
    // returns 0 for unrelated controllers, so this is cheap and idempotent.
    if (![AxsSpringTwelveHookedRecordingClasses containsObject:@"__global__"]) {
        Class base = UIViewController.class;
        AxsSpringTwelveSwizzleAppearance(base, @selector(viewWillAppear:));
        AxsSpringTwelveSwizzleAppearance(base, @selector(viewDidAppear:));
        [AxsSpringTwelveHookedRecordingClasses addObject:@"__global__"];
    }
}

%ctor {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.mobilephone"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                AxsSpringTwelveMountedRecordingHosts = [NSHashTable weakObjectsHashTable];
                AxsSpringTwelveHookedRecordingClasses = [NSMutableSet set];
                AxsSpringTwelveRecordingObservers = [NSMutableArray array];
                AxsSpringTwelveInstallRecordingTabHooks();
                for (NSString *name in @[NSBundleDidLoadNotification, UIApplicationDidFinishLaunchingNotification, AxsSpringTwelveRecordingsChanged]) {
                    id observer = [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *note) {
                            AxsSpringTwelveInstallRecordingTabHooks();
                            for (UIViewController *host in AxsSpringTwelveMountedRecordingHosts.allObjects) {
                                NSInteger role = [objc_getAssociatedObject(host, &AxsSpringTwelveRecordingRoleKey) integerValue];
                                AxsSpringTwelveMountRecordingChild(host, role);
                            }
                        }];
                    [AxsSpringTwelveRecordingObservers addObject:observer];
                }
            });
        }
    }
}

