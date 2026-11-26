#pragma once
// Final-file validation only. No capture, synchronization, encoder or publish changes.
#include <cmath>
#include <cstdint>
#include <limits>
namespace HaogeCallRecorderValidation {
enum class Stage { Complete, InvalidExpected, ReadError, InvalidBuffer, NonFinite, TooLong, TooShort };
struct Result { Stage stage; int32_t status; uint64_t decoded, reads; bool ok() const {return stage==Stage::Complete;} };
// Reader returns OSStatus and actual PCM frame/byte counts. A successful short read
// is not EOF. Only a successful zero-frame read is EOF (ExtendedAudioFile.h).
template<class Reader>
Result decode(uint64_t expected,float *pcm,uint32_t capacity,Reader read) {
    constexpr uint64_t tolerance=4608;
    if(!expected || expected>std::numeric_limits<uint64_t>::max()-tolerance || !pcm || !capacity || capacity>UINT32_MAX/8)
        return {Stage::InvalidExpected,0,0,0};
    uint64_t decoded=0,reads=0;
    for(;;){
        uint32_t frames=capacity,bytes=capacity*8;
        int32_t status=read(pcm,frames,bytes);++reads;
        if(status)return {Stage::ReadError,status,decoded,reads};
        if(frames>capacity || bytes>capacity*8 || bytes<frames*8)return {Stage::InvalidBuffer,0,decoded,reads};
        if(!frames)return {decoded && (decoded>=expected || expected-decoded<=tolerance)?Stage::Complete:Stage::TooShort,0,decoded,reads};
        // Each successful nonempty read advances >=1 frame; reject excess before
        // addition to bound both total decoded frames and loop iterations.
        if(frames>expected+tolerance-decoded)return {Stage::TooLong,0,decoded,reads};
        for(uint32_t i=0;i<frames*2;++i)if(!std::isfinite(pcm[i]))return {Stage::NonFinite,0,decoded,reads};
        decoded+=frames;
    }
}
}
