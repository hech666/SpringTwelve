#!/usr/bin/env python3
from pathlib import Path
import sys,shutil,struct
source=Path(__file__).resolve().parent
project=source.parent;obj=Path(sys.argv[1]);prefix=Path(sys.argv[2])
dest=project/'artifacts/RealtimeRelink';dest.mkdir(parents=True,exist_ok=True)
for stem,target in [('HaogeCallRecorderRealtime','HaogeCallRecorderRealtimeMain.o'),('HaogeCallRecorderPCM','HaogeCallRecorderPCM.o')]:
    paths=list(obj.rglob(stem+'.o'))
    if not paths:
        pattern='HaogeCallRecorderRealtime.mm.*.o' if stem=='HaogeCallRecorderRealtime' else 'HaogeCallRecorderPCM.cpp.*.o'
        paths=list(obj.rglob(pattern))
    paths=[p for p in paths if struct.unpack_from('<III',p.read_bytes())==(0xfeedfacf,0x100000c,0x80000002)]
    assert len(paths)==1,(stem,paths)
    shutil.copy2(paths[0],dest/target)
for name in ['HaogeCallRecorderRealtime.mm','HaogeCallRecorderValidation.h','HaogeCallRecorderPCM.h','HaogeCallRecorderPCM.cpp','Makefile','entitlements.plist','relink.sh']:
    shutil.copy2(source/name,dest/name)
shutil.copy2(project/'Sources/HaogeCallRecorderControl.h',dest/'HaogeCallRecorderControl.h')
shutil.copy2(prefix/'lib/libmp3lame.a',dest/'libmp3lame.a')
shutil.copy2(prefix/'include/lame/lame.h',dest/'lame.h')
for name in ['LAME-COPYING','README.md']:
    shutil.copy2(project/'MP3Helper'/name,dest/name)
shutil.copy2(project/'MP3Helper/vendor/lame-3.100.tar.gz',dest/'lame-3.100.tar.gz')
print('Exact realtime helper relink objects, archive, full source and license exported:',dest)
