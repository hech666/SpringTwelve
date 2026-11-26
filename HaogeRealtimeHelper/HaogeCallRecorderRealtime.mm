// HaogeCallRecorder realtime two-direction capture helper. LGPL-2.0-or-later.
#import <Foundation/Foundation.h>
#import <AVFAudio/AVFAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach_time.h>
#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>
#include <cerrno>
#include "HaogeCallRecorderPCM.h"
#include "HaogeCallRecorderControl.h"
#include "HaogeCallRecorderValidation.h"
struct HaogeCallRecorderControlGuard {
    int directory; const char *name;
    ~HaogeCallRecorderControlGuard(){if(directory>=0){unlinkat(directory,name,0);close(directory);}}
};
@protocol HaogeCallRecorderTapInitializers
- (instancetype)initTapInternalWithFormat:(AVAudioFormat *)format PIDs:(NSArray<NSNumber *> *)pids;
- (instancetype)initProcessTapInternalWithFormat:(AVAudioFormat *)format PID:(int)pid;
- (instancetype)initWithTapDescription:(id)description;
@end
using namespace HaogeCallRecorder;
static volatile sig_atomic_t haoge_callrecorder_stop=0;
static volatile sig_atomic_t haoge_callrecorder_aborted=0;
static void haoge_callrecorder_signal(int value){if(value==SIGTERM)haoge_callrecorder_aborted=1;haoge_callrecorder_stop=value;}
static int haoge_callrecorder_stopSignal(){return haoge_callrecorder_aborted?SIGTERM:haoge_callrecorder_stop;}
static double haoge_callrecorder_tickSeconds=0;
static void haoge_callrecorder_log(const char *stage,int value=0){fprintf(stderr,"[HaogeCallRecorderRealtime] stage=%s code=%d errno=%d\n",stage,value,errno);fflush(stderr);}
// Only selectors and argument registers proven by original MUtoolRecord are used.
static BOOL haoge_callrecorder_signature(Class cls,SEL sel,const char *types){
    Method method=class_getInstanceMethod(cls,sel);if(!method)return NO;
    NSMethodSignature *s=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if(s.methodReturnType[0]!=types[0] || s.numberOfArguments!=strlen(types)+1)return NO;
    for(NSUInteger i=1;i<strlen(types);i++)if([s getArgumentTypeAtIndex:i+1][0]!=types[i])return NO;
    return YES;
}
struct HaogeCallRecorderStream{
    Ring ring;AudioQueueRef queue=nullptr;AudioStreamBasicDescription format={};
    __strong id tap=nil;std::atomic<bool> accepting{true};
};
static void haoge_callrecorder_input(void *context,AudioQueueRef queue,AudioQueueBufferRef buffer,
    const AudioTimeStamp *stamp,UInt32 packets,const AudioStreamPacketDescription *descs){
    (void)packets;(void)descs;
    HaogeCallRecorderStream *s=(HaogeCallRecorderStream*)context;
    if(!s->accepting.load(std::memory_order_acquire))return;
    // No allocation, Objective-C, encoding, locking or file I/O on the audio callback.
    if(!stamp || !(stamp->mFlags&kAudioTimeStampHostTimeValid) || !(stamp->mFlags&kAudioTimeStampSampleTimeValid) ||
       buffer->mAudioDataByteSize%s->format.mBytesPerFrame){s->ring.error.store(21);return;}
    unsigned n=buffer->mAudioDataByteSize/s->format.mBytesPerFrame;
    if(!s->ring.push((const float*)buffer->mAudioData,n,s->format.mChannelsPerFrame,
            stamp->mHostTime*haoge_callrecorder_tickSeconds,stamp->mSampleTime))return;
    OSStatus status=AudioQueueEnqueueBuffer(queue,buffer,0,nullptr);
    if(status)s->ring.error.store(25);
}
static bool haoge_callrecorder_setup(HaogeCallRecorderStream &s,int pid,unsigned channels){
    if(!s.ring.allocate())return false;
    // 0x100004274 d0=44100; w2=1(Float32), w3=channel count, w4=1(interleaved).
    AVAudioFormat *format=[[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:44100 channels:channels interleaved:YES];
    if(!format)return false;s.format=*format.streamDescription;
    if(s.format.mFormatID!=kAudioFormatLinearPCM || !(s.format.mFormatFlags&kAudioFormatFlagIsFloat) ||
        s.format.mBitsPerChannel!=32 || s.format.mSampleRate!=Rate || s.format.mBytesPerFrame!=4*channels)return false;
    Class description=NSClassFromString(@"ATAudioTapDescription"),tapClass=NSClassFromString(@"ATAudioTap");
    SEL multi=NSSelectorFromString(@"initTapInternalWithFormat:PIDs:");
    SEL single=NSSelectorFromString(@"initProcessTapInternalWithFormat:PID:");
    SEL create=NSSelectorFromString(@"initWithTapDescription:");id desc=nil;
    if(!description||!tapClass||!haoge_callrecorder_signature(tapClass,create,"@@")){haoge_callrecorder_log("tap-class-or-ABI",11);return false;}
    if([description instancesRespondToSelector:multi]){
        if(!haoge_callrecorder_signature(description,multi,"@@@")){haoge_callrecorder_log("tap-multi-ABI",12);return false;}
        desc=[(id<HaogeCallRecorderTapInitializers>)[description alloc] initTapInternalWithFormat:format PIDs:@[@(pid)]];
    }else{
        if(!haoge_callrecorder_signature(description,single,"@@i")){haoge_callrecorder_log("tap-single-ABI",13);return false;}
        desc=[(id<HaogeCallRecorderTapInitializers>)[description alloc] initProcessTapInternalWithFormat:format PID:pid];
    }
    if(!desc)return false;
    s.tap=[(id<HaogeCallRecorderTapInitializers>)[tapClass alloc] initWithTapDescription:desc];if(!s.tap)return false;
    // 0x1000043cc: original flags 0x800, context now explicitly per-stream.
    OSStatus status=AudioQueueNewInput(&s.format,haoge_callrecorder_input,&s,nullptr,nullptr,0x800,&s.queue);
    if(status){haoge_callrecorder_log("AudioQueueNewInput",status);return false;}
    // 0x1000043dc..3f0: qtob=0x71746f62, x2=tap OBJECT itself, w3=8; NOT &tap.
    status=AudioQueueSetProperty(s.queue,0x71746f62,(__bridge const void*)s.tap,8);
    if(status){haoge_callrecorder_log("AudioQueueSetProperty-qtob",status);return false;}
    // Fail closed if the queue does not retain the negotiated PCM format.
    AudioStreamBasicDescription actual={};UInt32 size=sizeof(actual);
    status=AudioQueueGetProperty(s.queue,kAudioQueueProperty_StreamDescription,&actual,&size);
    if(status || actual.mSampleRate!=Rate || actual.mFormatID!=kAudioFormatLinearPCM || (actual.mFormatFlags&(kAudioFormatFlagIsNonInterleaved|kAudioFormatFlagIsBigEndian)) || !(actual.mFormatFlags&kAudioFormatFlagIsFloat) || actual.mBitsPerChannel!=32 || actual.mChannelsPerFrame!=channels || actual.mBytesPerFrame!=channels*4 || actual.mFramesPerPacket!=1 || actual.mBytesPerPacket!=channels*4){haoge_callrecorder_log("queue-format-mismatch",status);return false;}
    for(unsigned i=0;i<3;i++){
        AudioQueueBufferRef buffer=nullptr;status=AudioQueueAllocateBuffer(s.queue,BlockFrames*s.format.mBytesPerFrame,&buffer);
        if(!status)status=AudioQueueEnqueueBuffer(s.queue,buffer,0,nullptr);
        if(status){haoge_callrecorder_log("queue-buffer-init",status);return false;}
    }
    return true;
}
static void haoge_callrecorder_dispose(HaogeCallRecorderStream &s){
    s.accepting.store(false,std::memory_order_release);
    if(s.queue){AudioQueueStop(s.queue,true);AudioQueueDispose(s.queue,true);s.queue=nullptr;}
    s.tap=nil;
}
static bool haoge_callrecorder_validate(NSString *path,uint64_t frames){
    // ExtAudioFileRead exposes OSStatus and documents a successful 0-frame read
    // as EOF. Never interpret AVAudioFile's ambiguous NO/nil result as success.
    ExtAudioFileRef audio=nullptr;
    OSStatus status=ExtAudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],&audio);
    if(status || !audio){fprintf(stderr,"[HaogeCallRecorderValidate] stage=open status=%d expected=%llu\n",(int)status,(unsigned long long)frames);if(audio)ExtAudioFileDispose(audio);return false;}
    AudioStreamBasicDescription source={};UInt32 size=sizeof(source);
    status=ExtAudioFileGetProperty(audio,kExtAudioFileProperty_FileDataFormat,&size,&source);
    if(status || size!=sizeof(source) || source.mFormatID!=kAudioFormatMPEGLayer3 || source.mSampleRate!=Rate || source.mChannelsPerFrame!=2){
        fprintf(stderr,"[HaogeCallRecorderValidate] stage=source-format status=%d rate=%.0f channels=%u format=%u\n",(int)status,source.mSampleRate,(unsigned)source.mChannelsPerFrame,(unsigned)source.mFormatID);ExtAudioFileDispose(audio);return false;
    }
    // Preserve native rate and channel count: validation must not resample/downmix.
    AudioStreamBasicDescription client={};client.mSampleRate=Rate;client.mFormatID=kAudioFormatLinearPCM;
    client.mFormatFlags=kAudioFormatFlagsNativeFloatPacked;client.mBytesPerPacket=8;client.mFramesPerPacket=1;
    client.mBytesPerFrame=8;client.mChannelsPerFrame=2;client.mBitsPerChannel=32;
    status=ExtAudioFileSetProperty(audio,kExtAudioFileProperty_ClientDataFormat,sizeof(client),&client);
    if(status){fprintf(stderr,"[HaogeCallRecorderValidate] stage=client-format status=%d\n",(int)status);ExtAudioFileDispose(audio);return false;}
    float pcm[8192*2];
    auto result=HaogeCallRecorderValidation::decode(frames,pcm,8192,[&](float *samples,uint32_t &count,uint32_t &bytes)->int32_t{
        AudioBufferList buffers={};buffers.mNumberBuffers=1;buffers.mBuffers[0].mNumberChannels=2;
        buffers.mBuffers[0].mDataByteSize=bytes;buffers.mBuffers[0].mData=samples;
        UInt32 actual=count;OSStatus readStatus=ExtAudioFileRead(audio,&actual,&buffers);
        count=actual;bytes=buffers.mBuffers[0].mDataByteSize;
        if(!readStatus && (buffers.mNumberBuffers!=1 || buffers.mBuffers[0].mNumberChannels!=2 || buffers.mBuffers[0].mData!=samples))return kAudio_ParamError;
        return readStatus;
    });
    OSStatus closeStatus=ExtAudioFileDispose(audio);
    bool valid=result.ok() && closeStatus==noErr;
    fprintf(stderr,"[HaogeCallRecorderValidate] stage=%s reason=%d status=%d close=%d decoded=%llu expected=%llu reads=%llu\n",valid?"complete":"failed",(int)result.stage,(int)result.status,(int)closeStatus,(unsigned long long)result.decoded,(unsigned long long)frames,(unsigned long long)result.reads);
    fflush(stderr);return valid;
}
int main(int argc,char **argv){@autoreleasepool{
    if(argc!=2){fprintf(stderr,"Usage: %s /var/mobile/Documents/CallRecordings/HaogeSpringTwelve-UUID.mp3\n",argv[0]);return 2;}
    NSString *output=[NSString stringWithUTF8String:argv[1]];
    if(![output.stringByDeletingLastPathComponent isEqualToString:@"/var/mobile/Documents/CallRecordings"] || ![output.lastPathComponent hasPrefix:@"HaogeSpringTwelve-"] || ![output.pathExtension isEqualToString:@"mp3"])return 2;
    NSString *uuid=[output.lastPathComponent.stringByDeletingPathExtension substringFromIndex:@"HaogeSpringTwelve-".length];
    if(![[NSUUID alloc]initWithUUIDString:uuid])return 2;
    NSString *controlName=[output.lastPathComponent stringByAppendingString:@".control"];
    NSString *diagnostics=[output.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"Diagnostics"];
    int controlDirectory=open(diagnostics.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(controlDirectory<0){haoge_callrecorder_log("control-directory",50);return 50;}
    HaogeCallRecorderControlGuard controlGuard{controlDirectory,controlName.fileSystemRepresentation};
    struct stat info;if(lstat(argv[1],&info)==0||errno!=ENOENT)return 2;
    struct sigaction action={};action.sa_handler=haoge_callrecorder_signal;sigemptyset(&action.sa_mask);
    if(sigaction(SIGINT,&action,nullptr)||sigaction(SIGTERM,&action,nullptr)){haoge_callrecorder_log("signal-install",50);return 50;}
    NSString *ready=[output.stringByDeletingLastPathComponent stringByAppendingPathComponent:[@"Diagnostics/" stringByAppendingString:[output.lastPathComponent stringByAppendingString:@".ready"]]];
    if(![[NSData dataWithBytes:"ready" length:5] writeToFile:ready options:NSDataWritingAtomic error:nullptr]){haoge_callrecorder_log("ready-write",48);return 48;}
    chmod(ready.fileSystemRepresentation,0600);
    mach_timebase_info_data_t tb;mach_timebase_info(&tb);haoge_callrecorder_tickSeconds=(double)tb.numer/tb.denom/1e9;
    NSString *status=[output.stringByDeletingLastPathComponent stringByAppendingPathComponent:[@"Diagnostics/" stringByAppendingString:[output.lastPathComponent stringByAppendingString:@".status"]]];
    NSString *pattern=[output.stringByDeletingLastPathComponent stringByAppendingPathComponent:[NSString stringWithFormat:@".%@.part.XXXXXX.mp3",output.lastPathComponent]];
    char *temporary=strdup(pattern.fileSystemRepresentation);if(!temporary)return 3;
    int fd=mkstemps(temporary,4);FILE *file=fd>=0?fdopen(fd,"w+b"):nullptr;
    if(!file){if(fd>=0)close(fd);free(temporary);haoge_callrecorder_log("output-create",3);return 3;}
    HaogeCallRecorderStream down,up;int result=0;
    // Proven main mapping: speaker -> PID -2 (2 channels), mic -> PID -3 (1 channel).
    if(!haoge_callrecorder_setup(down,-2,2)||!haoge_callrecorder_setup(up,-3,1))result=10;
    Encoder encoder(down.ring,up.ring,file);
    if(!result && !encoder.initialize())result=encoder.error();
    if(!result){OSStatus s=AudioQueueStart(down.queue,nullptr);if(!s)s=AudioQueueStart(up.queue,nullptr);if(s){haoge_callrecorder_log("queue-start",s);result=14;}}
    double start=mach_absolute_time()*haoge_callrecorder_tickSeconds,lastPair=start,lastStatus=0;
    struct sigaction observed={};
    if(!sigaction(SIGINT,nullptr,&observed))haoge_callrecorder_log("SIGINT-handler-matches",observed.sa_handler==haoge_callrecorder_signal);
    bool stopped=false,normalStop=false;
    while(!result && !stopped){@autoreleasepool{
        int controlError=0;
        HaogeControl control=haoge_control_read(controlDirectory,controlName.fileSystemRepresentation,&controlError);
        int decision=haoge_control_decision(control,encoder.error(),haoge_callrecorder_stopSignal(),SIGINT,SIGTERM,0);
        if(decision>0){errno=controlError;haoge_callrecorder_log("control-abort-or-error",decision);result=decision;break;}
        if(decision<0){
            haoge_callrecorder_log(control==HaogeControlNormal?"control-observed-normal-stop":"signal-observed-normal-stop");
            // Drain no further device buffers after stop; retain already copied blocks.
            normalStop=true;haoge_callrecorder_dispose(down);haoge_callrecorder_dispose(up);stopped=true;
        }
        int pumped;while((pumped=encoder.pump(stopped))>0)lastPair=mach_absolute_time()*haoge_callrecorder_tickSeconds;
        if(pumped<0){result=encoder.error();break;}
        double now=mach_absolute_time()*haoge_callrecorder_tickSeconds;
        if(!stopped && now-lastPair>2.){
            // Re-read at the watchdog boundary: an explicit stop wins this race, never a missing stop.
            control=haoge_control_read(controlDirectory,controlName.fileSystemRepresentation,&controlError);
            decision=haoge_control_decision(control,encoder.error(),haoge_callrecorder_stopSignal(),SIGINT,SIGTERM,1);
            if(decision<0)continue;
            result=decision;errno=controlError;
            haoge_callrecorder_log("watchdog-control-state",(int)control);
            haoge_callrecorder_log("watchdog-signal-state",haoge_callrecorder_stop);
            haoge_callrecorder_log("watchdog-ready-present",access(ready.fileSystemRepresentation,F_OK)==0);
            haoge_callrecorder_log(result==41?"no-paired-audio-2s":"watchdog-control-error",result);break;
        }
        if(encoder.frames() && now-lastStatus>.5){
            NSString *value=[NSString stringWithFormat:@"%llu\n",(unsigned long long)encoder.frames()];
            NSData *data=[value dataUsingEncoding:NSUTF8StringEncoding];
            if(![data writeToFile:status options:NSDataWritingAtomic error:nullptr])haoge_callrecorder_log("status-write",42);
            chmod(status.fileSystemRepresentation,0600);lastStatus=now;
        }
        if(!stopped){CFRunLoopRunInMode(kCFRunLoopDefaultMode,.005,true);}
    }}
    haoge_callrecorder_dispose(down);haoge_callrecorder_dispose(up);
    if(!result && !normalStop){result=43;haoge_callrecorder_log("aborted-not-normal-stop",result);}
    if(!result && !encoder.finish())result=encoder.error();
    if(!result && fsync(fd))result=44;
    if(fclose(file)&&!result)result=45;file=nullptr;
    fprintf(stderr,"[HaogeCallRecorderRealtime] frames=%llu leadingTrim=%llu trailingTrim=%llu result=%d\n",(unsigned long long)encoder.frames(),(unsigned long long)encoder.leadingTrim(),(unsigned long long)encoder.trailingTrim(),result);
    if(!result){int code=0;HaogeControl control=haoge_control_read(controlDirectory,controlName.fileSystemRepresentation,&code);if(control==HaogeControlAbort||haoge_callrecorder_aborted)result=43;else if(control==HaogeControlInvalid)result=50;}
    if(!result && !haoge_callrecorder_validate([NSString stringWithUTF8String:temporary],encoder.frames()))result=46;
    if(!result){int code=0;HaogeControl control=haoge_control_read(controlDirectory,controlName.fileSystemRepresentation,&code);
        if(control==HaogeControlAbort||haoge_callrecorder_aborted)result=43;
        else if(control==HaogeControlInvalid)result=50;
        if(result){errno=code;haoge_callrecorder_log("finalize-abort-before-commit",result);}
    }
    // Exclusive rename is the publication commit point; cancellation after it cannot unpublish a file.
    if(!result && renamex_np(temporary,argv[1],RENAME_EXCL))result=47;
    // Incomplete temporary MP3 is retained for debugging, never presented as completed.
    if(!result)haoge_callrecorder_log("published-one-MP3");else haoge_callrecorder_log("failed-partial-retained",result);
    unlink(status.fileSystemRepresentation);unlink(ready.fileSystemRepresentation);free(temporary);return result;
}}
