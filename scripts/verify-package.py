#!/usr/bin/env python3
"""Verify non-recording SpringTwelve package, including arm64e prefs slice."""
from pathlib import Path
import sys, tempfile, subprocess, plistlib, struct, runpy
project=Path(__file__).resolve().parent.parent
# This script intentionally executes every power-helper and no-recording check.
verify=runpy.run_path(str(project/'scripts/verify-power-package.py'))['verify_macho']
package=Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='st-no-recording-') as folder:
    root=Path(folder)
    subprocess.run(['dpkg-deb','-x',str(package),str(root)],check=True)
    bundles=list(root.rglob('AxsSpringTwelvePrefs.bundle')); assert len(bundles)==1
    bundle=bundles[0]
    subprocess.run([sys.executable,str(project/'scripts/verify-preferences.py'),str(bundle)],check=True)
    data=(bundle/'AxsSpringTwelvePrefs').read_bytes()
    if data[:4]==b'\xcf\xfa\xed\xfe':
        verify(bundle/'AxsSpringTwelvePrefs')
    else:
        assert data[:4]==b'\xca\xfe\xba\xbe'
        count=struct.unpack_from('>I',data,4)[0]; slices=[]
        for i in range(count):
            cpu,subtype,off,size,align=struct.unpack_from('>IIIII',data,8+20*i)
            if (cpu,subtype)==(0x100000c,0x80000002): slices.append(data[off:off+size])
        assert len(slices)==1
        thin=root/'prefs.arm64e'; thin.write_bytes(slices[0]); verify(thin)
    assert not list(root.rglob('CallRecordings')), 'Never include user audio data'
    assert not list(root.rglob('MP3Relink'))
    assert not list(root.rglob('libmp3lame.a'))
    assert not list(root.rglob('lame-3.100.tar.gz'))
    print('Non-recording package + three menus + prefs ABI/signature PASS')
