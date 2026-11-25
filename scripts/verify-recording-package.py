#!/usr/bin/env python3
"""Package-only checks, not a runtime/call-recording test."""
from pathlib import Path
import sys, runpy, tempfile, subprocess, struct, plistlib, shutil, hashlib
project = Path(__file__).resolve().parent.parent
# Preserve every existing power-helper/ownership/original MUtool hash check.
verify = runpy.run_path(str(project/'scripts/verify-power-package.py'))['verify_macho']
package = Path(sys.argv[1]).resolve()

def verify_slice(path, temporary):
    data = path.read_bytes()
    if data[:4] == b'\xcf\xfa\xed\xfe':
        verify(path); return
    assert data[:4] == b'\xca\xfe\xba\xbe', ('Unexpected Mach-O',path)
    count = struct.unpack_from('>I',data,4)[0]
    slices = []
    for i in range(count):
        cpu, subtype, offset, size, align = struct.unpack_from('>IIIII',data,8+20*i)
        if cpu == 0x100000c and subtype == 0x80000002:
            slices.append(data[offset:offset+size])
    assert len(slices) == 1, ('Expected arm64e ABI v2 slice',path)
    thin = temporary/(path.name+'.arm64e')
    thin.write_bytes(slices[0]); verify(thin)

with tempfile.TemporaryDirectory(prefix='st-mp3-verify-') as folder:
    root = Path(folder)
    subprocess.run(['dpkg-deb','-x',str(package),str(root)],check=True)
    def one(name):
        matches = list(root.rglob(name)); assert len(matches) == 1,(name,matches)
        return matches[0]
    helper = one('AxsSpringTwelveMP3Mixer')
    assert helper.relative_to(root).as_posix() in ['usr/local/bin/AxsSpringTwelveMP3Mixer','var/jb/usr/local/bin/AxsSpringTwelveMP3Mixer']
    assert helper.stat().st_mode & 0o111 and not helper.stat().st_mode & 0o4000
    verify(helper)
    for name in ['MUtoolRecord','MUtoolMixer','AxsSpringTwelvePrefs']:
        verify_slice(one(name),root)
    ldid = shutil.which('ldid') or '/var/minis/shared/toolchains/ld64-arm64e/bin/ldid'
    entitlements = plistlib.loads(subprocess.check_output([ldid,'-e',str(helper)]))
    assert entitlements.get('platform-application') is True
    assert entitlements.get('com.apple.private.security.no-sandbox') is True
    assert not any('reboot' in k or 'CanTapTelephony' in k for k in entitlements)
    materials = one('MP3Relink')
    assert materials.relative_to(root).as_posix() in ['usr/share/SpringTwelve/MP3Relink','var/jb/usr/share/SpringTwelve/MP3Relink']
    for name in ['LAME-COPYING','README.md','main.m','relink.sh','entitlements.plist','build-lame-macos.sh','AxsSpringTwelveMP3Mixer.o','libmp3lame.a']:
        assert (materials/name).stat().st_size > 0, name
    archive = materials/'lame-3.100.tar.gz'
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == 'ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e'
    assert struct.unpack_from('<II',(materials/'AxsSpringTwelveMP3Mixer.o').read_bytes(),4) == (0x100000c,0x80000002)
    bundle = one('AxsSpringTwelvePrefs.bundle')
    subprocess.run([sys.executable,str(project/'scripts/verify-preferences.py'),str(bundle)],check=True)
    assert not list(root.rglob('CallRecordings')), 'Package must not install/delete user audio data'
    dylib = one('AxsSpringTwelve.dylib').read_bytes()
    assert b'/var/mobile/Documents/CallRecordings' in dylib
    assert b'AxsSpringTwelveMP3Mixer' in dylib
    print('MP3 helper ABI/signature/entitlements, LGPL source+object+archive, bundle plist contract, and real recording path string PASS')
