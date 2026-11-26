#import <Foundation/Foundation.h>
#import "HaogeCallRecorderFileName.h"
#include <assert.h>
static unsigned HaogeCallRecorderTestCount;
static void HaogeCallRecorderCheck(BOOL pass) { ++HaogeCallRecorderTestCount; if (!pass) abort(); }
int main(void) { @autoreleasepool {
    HaogeCallRecorderCheck([HaogeCallRecorderNormalizedPeerNumber(@"+86 (138) 0013-8000") isEqualToString:@"+8613800138000"]);
    for (id value in @[@"", @"+", @"12", @"Anonymous", @"sip:123@example.invalid", @"*123#", @"123/456", @"123\n456", @"123_456", @"123456789012345678901234567890123"]) HaogeCallRecorderCheck(HaogeCallRecorderNormalizedPeerNumber(value) == nil);
    HaogeCallRecorderCheck(HaogeCallRecorderNormalizedPeerNumber(nil) == nil);
    NSString *person = HaogeCallRecorderSafeContactComponent(@" ../测试/联系人:\n ");
    HaogeCallRecorderCheck(person.length && ![person hasPrefix:@"."] && [person rangeOfString:@"/"].location == NSNotFound && [person rangeOfString:@"\n"].location == NSNotFound);
    NSMutableString *longName=[NSMutableString string]; for(int i=0;i<100;++i)[longName appendString:@"测试😀"];
    NSString *bounded=HaogeCallRecorderSafeContactComponent(longName);
    HaogeCallRecorderCheck([bounded lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= 80);
    HaogeCallRecorderCheck(HaogeCallRecorderSafeContactComponent(@" /\\.._ ") == nil);
    for(NSString *name in @[@"13800138000_2026-11-26_18-21-00-000.mp3", @"测试联系人_+8613800138000_2026-11-26_18-21-00-000.mp3", @"未知号码_2026-11-26_18-21-00-000-1.mp3", @"10086.mp3", @"10086-1.mp3", @"测试联系人_+8613800138000.mp3", @"测试联系人_+8613800138000-999.mp3", @"未知号码.mp3", @"未知号码-1.mp3"]) HaogeCallRecorderCheck(HaogeCallRecorderReadableRecordingName(name));
    for(NSString *name in @[@"random.mp3", @"10086.mp3.part", @"../10086.mp3", @".10086.mp3", @"10086-0.mp3", @"10086-1000.mp3", @"10086.mp3\n", @"../13800138000_2026-11-26_18-21-00-000.mp3", @".13800138000_2026-11-26_18-21-00-000.mp3", @"13800138000_2026-11-26_18-21-00-000.mp3.part", @"abc_2026-11-26_18-21-00-000.mp3", @"13800138000_2026-11-26_18-21-00-000.mp3\n"]) HaogeCallRecorderCheck(!HaogeCallRecorderReadableRecordingName(name));
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"HaogeCallRecorder-NameTests-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    HaogeCallRecorderCheck([fm createDirectoryAtPath:directory withIntermediateDirectories:NO attributes:nil error:NULL]);
    NSMutableSet *published=[NSMutableSet set];
    for(unsigned i=0;i<50;++i) {
        NSString *source=[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"HaogeSpringTwelve-%@.mp3",NSUUID.UUID.UUIDString]];
        NSData *bytes=[[NSString stringWithFormat:@"test-%u",i] dataUsingEncoding:NSUTF8StringEncoding];
        HaogeCallRecorderCheck([bytes writeToFile:source atomically:NO]);
        NSString *dest=HaogeCallRecorderPublishReadableRecording(source,@"13800138000",@"测试联系人");
        NSString *expected=i ? [NSString stringWithFormat:@"测试联系人_13800138000-%u.mp3",i] : @"测试联系人_13800138000.mp3";
        HaogeCallRecorderCheck([dest.lastPathComponent isEqualToString:expected] && HaogeCallRecorderReadableRecordingName(dest.lastPathComponent));
        HaogeCallRecorderCheck(![published containsObject:dest] && [[NSData dataWithContentsOfFile:dest] isEqualToData:bytes]);
        HaogeCallRecorderCheck(![fm fileExistsAtPath:source]); [published addObject:dest];
    }
    HaogeCallRecorderCheck(published.count==50);
    NSString *first=published.anyObject,*symlink=[directory stringByAppendingPathComponent:@"link.mp3"];
    HaogeCallRecorderCheck(symlinkat(first.fileSystemRepresentation,AT_FDCWD,symlink.fileSystemRepresentation)==0);
    HaogeCallRecorderCheck([HaogeCallRecorderPublishReadableRecording(symlink,@"12345",nil) isEqualToString:symlink]);
    NSString *source=[directory stringByAppendingPathComponent:@"unknown.mp3"];
    [@"unknown" writeToFile:source atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    NSString *unknown=HaogeCallRecorderPublishReadableRecording(source,nil,@"MustNotAppear");
    HaogeCallRecorderCheck([unknown.lastPathComponent isEqualToString:@"未知号码.mp3"]);
    for(unsigned i=0;i<2;++i) {
        NSString *plainSource=[directory stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [@"number-only" writeToFile:plainSource atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        NSString *plain=HaogeCallRecorderPublishReadableRecording(plainSource,@"10086",nil);
        HaogeCallRecorderCheck([plain.lastPathComponent isEqualToString:i ? @"10086-1.mp3" : @"10086.mp3"]);
    }
    for(NSString *dest in published) HaogeCallRecorderCheck([[NSData dataWithContentsOfFile:dest] length]>0);
    HaogeCallRecorderCheck([fm removeItemAtPath:directory error:NULL]);
    printf("PASS %u native filename normalization/Unicode/recognition/exclusive-rename checks\n",HaogeCallRecorderTestCount);
    return 0;
}}
