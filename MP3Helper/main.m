// CLI: AxsSpringTwelveMP3Mixer downstream.caf upstream.caf output.mp3
// Capture is unchanged. Inputs are never deleted by this helper.
#import <Foundation/Foundation.h>
#import <AVFAudio/AVFAudio.h>
#include <lame/lame.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>

static float axs_springtwelve_mono(AVAudioPCMBuffer *buffer, AVAudioFrameCount i) {
    if (i >= buffer.frameLength) return 0;
    float value = 0;
    for (AVAudioChannelCount c = 0; c < buffer.format.channelCount; c++)
        value += buffer.floatChannelData[c][i];
    value /= buffer.format.channelCount;
    return isfinite(value) ? fmaxf(-1, fminf(1, value)) : 0;
}

static BOOL axs_springtwelve_validateMP3(const char *path, uint64_t expected, double rate) {
    NSError *error = nil;
    AVAudioFile *audio = [[AVAudioFile alloc] initForReading:
        [NSURL fileURLWithFileSystemRepresentation:path isDirectory:NO relativeToURL:nil]
        commonFormat:AVAudioPCMFormatFloat32 interleaved:NO error:&error];
    if (!audio || audio.length <= 0 || audio.processingFormat.channelCount != 2 ||
        audio.processingFormat.sampleRate != rate) return NO;
    AVAudioPCMBuffer *probe = [[AVAudioPCMBuffer alloc] initWithPCMFormat:audio.processingFormat frameCapacity:8192];
    if (!probe) return NO;
    uint64_t decoded = 0;
    for (;;) {
        @autoreleasepool {
            probe.frameLength = 0;
            if (![audio readIntoBuffer:probe frameCount:8192 error:&error]) return NO;
            if (!probe.frameLength) break;
            decoded += probe.frameLength;
            // Bound decode to the captured duration plus MPEG padding/delay.
            if (decoded > expected + 4608) return NO;
        }
    }
    return decoded > 0 && decoded + 4608 >= expected;
}

static int axs_springtwelve_encode(char **argv) {
    NSError *error = nil;
    NSString *output = [NSString stringWithUTF8String:argv[3]];
    if (!output.isAbsolutePath || ![output.pathExtension.lowercaseString isEqualToString:@"mp3"] ||
        !strcmp(argv[1], argv[3]) || !strcmp(argv[2], argv[3])) return 2;
    struct stat existing;
    if (lstat(argv[3], &existing) == 0 || errno != ENOENT) return 2;
    AVAudioFile *down = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]
        commonFormat:AVAudioPCMFormatFloat32 interleaved:NO error:&error];
    AVAudioFile *up = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]]
        commonFormat:AVAudioPCMFormatFloat32 interleaved:NO error:&error];
    if (!down || !up || !down.processingFormat.channelCount || !up.processingFormat.channelCount) {
        fprintf(stderr, "input open failed\n"); return 3;
    }
    double rate = down.processingFormat.sampleRate;
    const int supported[] = {8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000};
    BOOL supportedRate = NO;
    for (size_t i = 0; i < sizeof(supported)/sizeof(*supported); i++)
        if (rate == supported[i]) supportedRate = YES;
    // MUtoolRecord is expected to use 44100 Hz. Reject mismatch, do not skew timing.
    if (!supportedRate || rate != up.processingFormat.sampleRate) return 4;
    enum { N = 8192, M = 17440 }; // M >= ceil(1.25*N) + 7200
    AVAudioPCMBuffer *a = [[AVAudioPCMBuffer alloc] initWithPCMFormat:down.processingFormat frameCapacity:N];
    AVAudioPCMBuffer *b = [[AVAudioPCMBuffer alloc] initWithPCMFormat:up.processingFormat frameCapacity:N];
    if (!a || !b || !a.floatChannelData || !b.floatChannelData) return 5;
    lame_t lame = lame_init();
    if (!lame) return 5;
    if (lame_set_in_samplerate(lame, (int)rate) < 0 || lame_set_out_samplerate(lame, (int)rate) < 0 ||
        lame_set_num_channels(lame, 2) < 0 || lame_set_mode(lame, JOINT_STEREO) < 0 ||
        lame_set_brate(lame, 96) < 0 || lame_set_quality(lame, 3) < 0 || lame_init_params(lame) < 0) {
        lame_close(lame); return 6;
    }
    NSString *pattern = [output.stringByDeletingLastPathComponent stringByAppendingPathComponent:
        [@"." stringByAppendingString:[output.lastPathComponent stringByAppendingString:@".part.XXXXXX"]]];
    char *temporary = strdup(pattern.fileSystemRepresentation);
    if (!temporary) { lame_close(lame); return 5; }
    int fd = mkstemp(temporary); // 0600, same filesystem as final name.
    FILE *file = fd >= 0 ? fdopen(fd, "w+b") : NULL;
    if (!file) {
        if (fd >= 0) { close(fd); unlink(temporary); }
        free(temporary); lame_close(lame); return 7;
    }
    uint64_t total = 0;
    float left[N], right[N]; unsigned char mp3[M];
    BOOL downEnded = NO, upEnded = NO, ok = YES;
    while (ok && !(downEnded && upEnded)) {
        @autoreleasepool {
            a.frameLength = 0; b.frameLength = 0;
            if (!downEnded && ![down readIntoBuffer:a frameCount:N error:&error]) ok = NO;
            if (!upEnded && ![up readIntoBuffer:b frameCount:N error:&error]) ok = NO;
            downEnded = downEnded || a.frameLength == 0;
            upEnded = upEnded || b.frameLength == 0;
            AVAudioFrameCount n = MAX(a.frameLength, b.frameLength);
            if (ok && n) {
                for (AVAudioFrameCount i = 0; i < n; i++) {
                    left[i] = axs_springtwelve_mono(a, i); right[i] = axs_springtwelve_mono(b, i);
                }
                int bytes = lame_encode_buffer_ieee_float(lame, left, right, (int)n, mp3, M);
                if (bytes < 0 || fwrite(mp3, 1, (size_t)bytes, file) != (size_t)bytes) ok = NO;
                total += n;
            }
        }
    }
    if (ok && total) {
        int bytes = lame_encode_flush(lame, mp3, M);
        ok = bytes >= 0 && fwrite(mp3, 1, (size_t)bytes, file) == (size_t)bytes;
        if (ok) {
            lame_mp3_tags_fid(lame, file);
            ok = !ferror(file) && fflush(file) == 0 && fsync(fd) == 0;
        }
    } else ok = NO;
    if (fclose(file) != 0) ok = NO;
    lame_close(lame);
    if (ok) ok = axs_springtwelve_validateMP3(temporary, total, rate);
    // Only a closed, fully decode-checked MP3 becomes visible under the final name.
    // RENAME_EXCL prevents collision/symlink overwrite. No input deletion on failure.
    int status = 8;
    if (ok && renamex_np(temporary, argv[3], RENAME_EXCL) == 0) status = 0;
    if (status) fprintf(stderr, "MP3 encode/validate/publish failed (errno=%d); CAF inputs retained\n", errno);
    unlink(temporary); free(temporary);
    return status;
}

int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "Usage: %s downstream.caf upstream.caf output.mp3\n", argv[0]); return 2; }
    @autoreleasepool { return axs_springtwelve_encode(argv); }
}
