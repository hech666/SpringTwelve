// HaogeCallRecorder realtime engine. LGPL-2.0-or-later; see ../MP3Helper/LAME-COPYING.
#pragma once
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <lame/lame.h>

namespace HaogeCallRecorder {
static_assert(std::atomic<uint64_t>::is_always_lock_free && std::atomic<int>::is_always_lock_free,"Realtime ring needs lock-free atomics");
constexpr unsigned BlockFrames=4096, Slots=64;
constexpr double Rate=44100.;
struct Block { uint32_t count,channels; double hostSeconds,sampleTime; float pcm[BlockFrames*2]; };
// Each AudioQueue is one producer, encoder is its only consumer. No callback allocation/locks/I/O.
struct Ring {
    Block *blocks=nullptr;
    std::atomic<uint64_t> read{0},write{0};
    std::atomic<int> error{0};
    std::atomic_flag producer=ATOMIC_FLAG_INIT;
    bool allocate() { blocks=(Block*)calloc(Slots,sizeof(Block)); return blocks; }
    ~Ring() { free(blocks); }
    bool push(const float *pcm,unsigned n,unsigned ch,double host,double sample) {
        if(producer.test_and_set(std::memory_order_acquire)){ error.store(22);return false; }
        bool ok=false; auto w=write.load(std::memory_order_relaxed);
        if(!n || n>BlockFrames || !ch || ch>2 || !std::isfinite(host) || !std::isfinite(sample)) error.store(23);
        else if(w-read.load(std::memory_order_acquire)>=Slots) error.store(24);
        else {
            Block &b=blocks[w%Slots]; b.count=n;b.channels=ch;b.hostSeconds=host;b.sampleTime=sample;
            memcpy(b.pcm,pcm,n*ch*sizeof(float)); write.store(w+1,std::memory_order_release);ok=true;
        }
        producer.clear(std::memory_order_release);return ok;
    }
    const Block *peek() { auto r=read.load(std::memory_order_relaxed); return r<write.load(std::memory_order_acquire)?&blocks[r%Slots]:nullptr; }
    void pop() { read.fetch_add(1,std::memory_order_release); }
};
class Encoder {
    Ring &a,&b; FILE *file; lame_t lame=nullptr;
    const Block *block[2]={nullptr,nullptr}; unsigned cursor[2]={0,0};
    int64_t start[2]={0,0},expected[2]={0,0}; double nextSample[2]={0,0}; bool seen[2]={false,false};
    double drift[2]={0,0},previousDrift[2]={0,0};
    bool aligned=false; uint64_t leading=0,trailing=0,total=0;
    int failure=0; unsigned char mp3[17440]; float left[BlockFrames],right[BlockFrames];
    bool load(unsigned s);
    void consume(unsigned s,unsigned n);
public:
    Encoder(Ring &down,Ring &up,FILE *output):a(down),b(up),file(output){}
    ~Encoder(){if(lame)lame_close(lame);}
    bool initialize();
    // Returns number of paired frames, 0 when waiting, -1 on failure. Main thread only.
    int pump(bool ended);
    bool finish();
    int error()const{return failure?failure:(a.error.load()?a.error.load():b.error.load());}
    uint64_t frames()const{return total;}
    uint64_t leadingTrim()const{return leading;}
    uint64_t trailingTrim()const{return trailing;}
};
}
