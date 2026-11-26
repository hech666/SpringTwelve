#pragma once
// Lifecycle only. This header contains no audio/tap/PCM/LAME changes.
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

enum HaogeControl { HaogeControlNone=0, HaogeControlNormal=1, HaogeControlAbort=2, HaogeControlInvalid=3 };
static inline enum HaogeControl haoge_control_parse(const char *bytes, size_t count) {
    if(count==12 && !memcmp(bytes,"normal-stop\n",12))return HaogeControlNormal;
    if(count==6 && !memcmp(bytes,"abort\n",6))return HaogeControlAbort;
    return HaogeControlInvalid;
}
// dirfd is an anchored, no-follow Diagnostics directory; name is the generated UUID basename.
static inline enum HaogeControl haoge_control_read(int dirfd,const char *name,int *code) {
    *code=0;
    int fd=openat(dirfd,name,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
    if(fd<0){*code=errno;return errno==ENOENT?HaogeControlNone:HaogeControlInvalid;}
    struct stat st;
    if(fstat(fd,&st)){*code=errno;close(fd);return HaogeControlInvalid;}
    if(!S_ISREG(st.st_mode)||st.st_nlink!=1||st.st_uid!=getuid()||(st.st_mode&0777)!=0600||st.st_size<1||st.st_size>12){*code=EACCES;close(fd);return HaogeControlInvalid;}
    char bytes[13];size_t total=0;
    while(total<sizeof(bytes)){
        ssize_t n=read(fd,bytes+total,sizeof(bytes)-total);
        if(n<0&&errno==EINTR)continue;
        if(n<0){*code=errno;close(fd);return HaogeControlInvalid;}
        if(!n)break;total+=(size_t)n;
    }
    close(fd);enum HaogeControl value=haoge_control_parse(bytes,total);
    if(value==HaogeControlInvalid)*code=EINVAL;return value;
}
static inline int haoge_control_write(int dirfd,const char *name,const char *temporary,enum HaogeControl value) {
    if(value!=HaogeControlNormal && value!=HaogeControlAbort)return EINVAL;
    struct stat st;
    if(fstatat(dirfd,name,&st,AT_SYMLINK_NOFOLLOW)==0){
        if(!S_ISREG(st.st_mode)||st.st_nlink!=1||st.st_uid!=getuid()||(st.st_mode&0777)!=0600)return EACCES;
    }else if(errno!=ENOENT)return errno;
    int fd=openat(dirfd,temporary,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if(fd<0)return errno;
    int code=fchmod(fd,0600)?errno:0;
    const char *bytes=value==HaogeControlNormal?"normal-stop\n":"abort\n";
    size_t count=strlen(bytes),total=0;
    while(!code&&total<count){ssize_t n=write(fd,bytes+total,count-total);if(n<0&&errno==EINTR)continue;if(n<=0){code=n<0?errno:EIO;break;}total+=(size_t)n;}
    if(!code&&fsync(fd))code=errno;
    if(close(fd)&&!code)code=errno;
    if(!code&&renameat(dirfd,temporary,dirfd,name))code=errno;
    if(code)unlinkat(dirfd,temporary,0);return code;
}
// Fatal errors always win. Missing stop never converts watchdog code 41 to success.
static inline int haoge_control_decision(enum HaogeControl value,int fatal,int signalValue,int normalSignal,int abortSignal,int watchdog) {
    if(fatal)return fatal;
    if(value==HaogeControlInvalid)return 50;
    if(value==HaogeControlAbort||signalValue==abortSignal)return 43;
    if(value==HaogeControlNormal||signalValue==normalSignal)return -1; // Dispose queues, drain, finish, validate, exclusive publish.
    return watchdog?41:0;
}
