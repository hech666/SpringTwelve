from pathlib import Path
import sys, shutil, struct
source = Path(__file__).resolve().parent
objects = list(Path(sys.argv[1]).rglob('main.m.*.o'))
objects = [p for p in objects if struct.unpack_from('<II', p.read_bytes(), 4) == (0x100000c, 0x80000002)]
assert len(objects) == 1, ('Expected one arm64e MP3 helper object', objects)
dest = Path(sys.argv[2]); dest.mkdir(parents=True, exist_ok=True)
shutil.copyfile(objects[0], dest/'AxsSpringTwelveMP3Mixer.o')
for name in ['LAME-COPYING', 'README.md', 'main.m', 'relink.sh', 'entitlements.plist', 'build-lame-macos.sh']:
    shutil.copyfile(source/name, dest/name)
shutil.copyfile(source/'vendor/lame-3.100.tar.gz', dest/'lame-3.100.tar.gz')
shutil.copyfile(source/'.build/arm64e/install/lib/libmp3lame.a', dest/'libmp3lame.a')
