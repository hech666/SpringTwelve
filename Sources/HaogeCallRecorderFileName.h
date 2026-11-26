#pragma once
#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/stdio.h>
#include <unistd.h>
#include <errno.h>

// Names are enrichment only. The unchanged helper always records/finalizes its UUID path first.
static inline NSString *HaogeCallRecorderNormalizedPeerNumber(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length > 128) return nil;
    NSMutableString *number = [NSMutableString string];
    NSCharacterSet *spaces = NSCharacterSet.whitespaceCharacterSet;
    for (NSUInteger i = 0; i < value.length; ++i) {
        unichar c = [value characterAtIndex:i];
        if (c >= '0' && c <= '9') [number appendFormat:@"%C", c];
        else if (c == '+' && !number.length) [number appendString:@"+"];
        else if (c == ' ' || c == '-' || c == '(' || c == ')' || c == '.' || [spaces characterIsMember:c]) continue;
        else return nil; // Do not turn a SIP address, hidden label or USSD string into a number.
    }
    NSUInteger digits = number.length - ([number hasPrefix:@"+"] ? 1 : 0);
    return digits >= 3 && digits <= 32 ? number : nil;
}
static inline NSString *HaogeCallRecorderSafeContactComponent(NSString *value) {
    if (![value isKindOfClass:NSString.class] || !value.length || value.length > 1024) return nil;
    NSString *normalized = value.precomposedStringWithCanonicalMapping;
    NSMutableCharacterSet *forbidden = [NSCharacterSet.controlCharacterSet mutableCopy];
    [forbidden formUnionWithCharacterSet:NSCharacterSet.illegalCharacterSet];
    [forbidden addCharactersInString:@"/\\:*?\"<>|\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069"];
    NSMutableString *name = [NSMutableString string];
    [normalized enumerateSubstringsInRange:NSMakeRange(0, normalized.length)
        options:NSStringEnumerationByComposedCharacterSequences
        usingBlock:^(NSString *part, NSRange range, NSRange enclosing, BOOL *stop) {
            (void)range; (void)enclosing;
            NSString *safe = [part rangeOfCharacterFromSet:forbidden].location == NSNotFound ? part : @"_";
            if ([[name stringByAppendingString:safe] lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 80) { *stop = YES; return; }
            [name appendString:safe];
        }];
    NSMutableCharacterSet *trim = [NSCharacterSet.whitespaceAndNewlineCharacterSet mutableCopy];
    [trim addCharactersInString:@"._"];
    NSString *result = [name stringByTrimmingCharactersInSet:trim];
    return result.length ? result : nil;
}
static inline BOOL HaogeCallRecorderReadableRecordingName(NSString *name) {
    if (![name isKindOfClass:NSString.class] || !name.length || [name hasPrefix:@"."] ||
        [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 220 ||
        ![name isEqualToString:name.lastPathComponent]) return NO;
    static NSRegularExpression *pattern; static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [NSRegularExpression regularExpressionWithPattern:
            @"^(?:[^/\\\\:\\p{C}]{1,96}_)?(?:\\+?[0-9]{3,32}|未知号码)(?:_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{3})?(?:-[1-9][0-9]{0,2})?\\.mp3$"
            options:0 error:NULL];
    });
    NSRange whole = NSMakeRange(0, name.length);
    return NSEqualRanges([pattern rangeOfFirstMatchInString:name options:0 range:whole], whole);
}
static inline NSString *HaogeCallRecorderPublishReadableRecording(NSString *path, NSString *number,
                                                          NSString *contact) {
    NSString *peer = HaogeCallRecorderNormalizedPeerNumber(number) ?: @"未知号码";
    NSString *person = [peer isEqualToString:@"未知号码"] ? nil : HaogeCallRecorderSafeContactComponent(contact);
    NSString *base = person.length ? [NSString stringWithFormat:@"%@_%@", person, peer] : peer;
    int directory = open(path.stringByDeletingLastPathComponent.fileSystemRepresentation,
                         O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (directory < 0) return path;
    const char *old = path.lastPathComponent.fileSystemRepresentation;
    struct stat info = {};
    if (fstatat(directory, old, &info, AT_SYMLINK_NOFOLLOW) || !S_ISREG(info.st_mode) ||
        info.st_nlink != 1 || info.st_uid != getuid() || info.st_size <= 0) { close(directory); return path; }
    NSString *result = path;
    for (NSUInteger attempt = 0; attempt < 1000; ++attempt) {
        NSString *name = attempt ? [NSString stringWithFormat:@"%@-%lu.mp3", base, (unsigned long)attempt]
                                 : [base stringByAppendingPathExtension:@"mp3"];
        if (!HaogeCallRecorderReadableRecordingName(name)) break;
        if (renameatx_np(directory, old, directory, name.fileSystemRepresentation, RENAME_EXCL) == 0) {
            result = [path.stringByDeletingLastPathComponent stringByAppendingPathComponent:name]; break;
        }
        if (errno != EEXIST) break; // Original audio survives every naming/permission failure.
    }
    close(directory);
    return result;
}
