// LGPL-2.0-or-later. Same portable engine is built by iOS helper and host tests.
#include "HaogeCallRecorderPCM.h"
#include <algorithm>
namespace HaogeCallRecorder {
bool Encoder::initialize(){
    lame=lame_init();
    if(!lame || lame_set_in_samplerate(lame,44100)<0 || lame_set_out_samplerate(lame,44100)<0 ||
       lame_set_num_channels(lame,2)<0 || lame_set_mode(lame,JOINT_STEREO)<0 ||
       lame_set_brate(lame,96)<0 || lame_set_quality(lame,3)<0 || lame_init_params(lame)<0){failure=30;return false;}
    return true;
}
bool Encoder::load(unsigned s){
    if(block[s])return true;
    Ring &ring=s?b:a;const Block *p=ring.peek();if(!p)return false;
    int64_t mapped=llround(p->hostSeconds*Rate);
    if(seen[s]){
        // SampleTime is local to THIS queue only. HostTime anchors both queues.
        // Reject gaps and drift; do not silently resample or synthesize missing audio.
        drift[s]=(double)(mapped-expected[s]);
        if(fabs(p->sampleTime-nextSample[s])>1.1 || fabs(drift[s]-previousDrift[s])>88){failure=31;return false;}
        previousDrift[s]=drift[s];
        start[s]=expected[s];
    }else{start[s]=mapped;seen[s]=true;}
    expected[s]=start[s]+p->count;nextSample[s]=p->sampleTime+p->count;
    block[s]=p;cursor[s]=0;return true;
}
void Encoder::consume(unsigned s,unsigned n){
    cursor[s]+=n;if(cursor[s]==block[s]->count){(s?b:a).pop();block[s]=nullptr;cursor[s]=0;}
}
int Encoder::pump(bool ended){
    if(error())return -1;
    bool hasA=load(0),hasB=load(1);if(error())return -1;
    if(!hasA || !hasB){
        if(ended && (hasA || hasB)){
            unsigned s=hasA?0:1,n=block[s]->count-cursor[s];
            trailing+=n;if(trailing>4410){failure=32;return -1;}
            consume(s,n);return (int)n; // Progress only; these frames are NOT encoded.
        }
        return 0;
    }
    int64_t pa=start[0]+cursor[0],pb=start[1]+cursor[1];
    if(pa!=pb){
        if(aligned){failure=33;return -1;}
        unsigned s=pa<pb?0:1;
        unsigned n=(unsigned)std::min<int64_t>(llabs(pa-pb),block[s]->count-cursor[s]);
        leading+=n;if(leading>11025){failure=34;return -1;} // At most 250ms startup skew.
        consume(s,n);return (int)n;
    }
    if(fabs(drift[0]-drift[1])>88){failure=49;return -1;}
    aligned=true;
    unsigned n=std::min(block[0]->count-cursor[0],block[1]->count-cursor[1]);
    for(unsigned i=0;i<n;i++){
        float vals[2]={0,0};
        for(unsigned s=0;s<2;s++){
            for(unsigned c=0;c<block[s]->channels;c++)vals[s]+=block[s]->pcm[(cursor[s]+i)*block[s]->channels+c];
            vals[s]/=block[s]->channels;
            if(!std::isfinite(vals[s])){failure=35;return -1;}
            vals[s]=std::max(-1.f,std::min(1.f,vals[s]));
        }
        left[i]=vals[0];right[i]=vals[1];
    }
    int bytes=lame_encode_buffer_ieee_float(lame,left,right,(int)n,mp3,sizeof(mp3));
    if(bytes<0 || fwrite(mp3,1,(size_t)bytes,file)!=(size_t)bytes){failure=36;return -1;}
    total+=n;consume(0,n);consume(1,n);return (int)n;
}
bool Encoder::finish(){
    if(error() || !total || !seen[0] || !seen[1]){if(!error())failure=37;return false;}
    if(a.peek()||b.peek()||block[0]||block[1]){failure=38;return false;}
    int bytes=lame_encode_flush(lame,mp3,sizeof(mp3));
    if(bytes<0 || fwrite(mp3,1,(size_t)bytes,file)!=(size_t)bytes){failure=39;return false;}
    lame_mp3_tags_fid(lame,file);
    if(ferror(file)||fflush(file)){failure=40;return false;}
    return true;
}
}
