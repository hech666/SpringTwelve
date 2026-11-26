// Host-only deterministic fixtures; never captures device audio.
#include "HaogeCallRecorderPCM.h"
#include <cassert>
#include <string>
using namespace HaogeCallRecorder;
int main(int argc,char **argv){
    assert(argc==2); std::string root=argv[1];
    auto run=[&](const char *name,int scenario){
        Ring a,b;assert(a.allocate()&&b.allocate());
        FILE *f=fopen((root+"/"+name+".mp3").c_str(),"w+b");assert(f);
        Encoder e(a,b,f);assert(e.initialize());float l[1024],r[1024];
        int failure=0;
        for(unsigned j=0;j<90;j++){
            for(unsigned i=0;i<1024;i++){l[i]=.3f*sin(2*M_PI*440*(j*1024+i)/44100.);r[i]=.2f*sin(2*M_PI*880*(j*1024+i)/44100.);}
            double host=100.+j*1024/44100.;
            if(!a.push(l,1024,1,host,j*1024)){failure=a.error;break;}
            if(scenario!=1)assert(b.push(r,1024,1,host+(scenario==2&&j==30?.02:0),j*1024));
            if(scenario==3)continue;
            int result;while((result=e.pump(false))>0){}if(result<0){failure=e.error();break;}
        }
        int result;while((result=e.pump(true))>0){}if(result<0)failure=e.error();
        bool ok=e.finish();if(scenario==0)assert(ok&&e.frames()==90*1024);else assert(!ok);
        printf("%s ok=%d frames=%llu error=%d leading=%llu trailing=%llu\n",name,ok,(unsigned long long)e.frames(),failure?failure:e.error(),(unsigned long long)e.leadingTrim(),(unsigned long long)e.trailingTrim());
        fclose(f);if(!ok)remove((root+"/"+name+".mp3").c_str());
    };
    run("stereo",0);run("missing-upstream",1);run("timestamp-drift",2);
    Ring overflow;assert(overflow.allocate());float sample=0;
    for(unsigned i=0;i<Slots;i++)assert(overflow.push(&sample,1,1,i/44100.,i));
    assert(!overflow.push(&sample,1,1,1.,1.)&&overflow.error==24);
    printf("overflow: PASS safe failure code24\n");
    Ring emptyA,emptyB;assert(emptyA.allocate()&&emptyB.allocate());FILE *f=tmpfile();Encoder empty(emptyA,emptyB,f);assert(empty.initialize());assert(!empty.finish());fclose(f);
    printf("empty-stop: PASS no successful output\n");
}
