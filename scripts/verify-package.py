#!/usr/bin/env python3
"""Verify the integrated HaogeSpringTwelve arm64e package and recording helper."""
from pathlib import Path
import hashlib, plistlib, re, runpy, struct, subprocess, sys, tarfile, tempfile

project = Path(__file__).resolve().parent.parent
verify_macho = runpy.run_path(str(project / 'scripts/verify-power-package.py'))['verify_macho']
package = Path(sys.argv[1]).resolve()
def field(name):
    return subprocess.check_output(['dpkg-deb', '-f', str(package), name], text=True).strip()
assert field('Package') == 'com.haoge.springtwelve'
assert field('Architecture') == 'iphoneos-arm64e'
assert re.fullmatch(r'5\.2\.0-[1-9][0-9]*', field('Version'))
assert field('Name') == '设置合集'
assert field('Description') == '多款桌面与电话小功能汇总，轻量自定义，原生风格。'

with tempfile.TemporaryDirectory(prefix='haoge-package-verify-') as folder:
    root = Path(folder)
    subprocess.run(['dpkg-deb', '-x', str(package), str(root)], check=True)
    bundles = list(root.rglob('HaogeSpringTwelvePrefs.bundle'))
    assert len(bundles) == 1
    bundle = bundles[0]
    subprocess.run([sys.executable, str(project / 'scripts/verify-preferences.py'), str(bundle)], check=True)
    prefs = bundle / 'HaogeSpringTwelvePrefs'
    data = prefs.read_bytes()
    assert data[:4] == b'\xcf\xfa\xed\xfe', 'Settings panel must be a thin arm64e Mach-O'
    verify_macho(prefs)

    dylibs = list(root.rglob('*.dylib'))
    assert len(dylibs) == 1 and dylibs[0].name == 'HaogeSpringTwelve.dylib'
    binary = dylibs[0].read_bytes()
    for marker in (b'HaogeCallRecorderCallRecorder', b'HaogeCallRecorderRecordingListViewController',
                   b'callRecordingEnabled', b'callRecordingListEnabled', b'captureReplaceFavoritesTab',
                   b'HaogeCallRecorderRealtime'):
        assert marker in binary, ('recording code missing from the single tweak dylib', marker)
    assert b'AxsCallRecorder' not in binary

    filters = list(root.rglob('HaogeSpringTwelve.plist'))
    assert len(filters) == 1
    assert plistlib.loads(filters[0].read_bytes()).get('Filter') == {
        'Bundles': ['com.apple.springboard', 'com.apple.mobilephone'],
        'Executables': ['druid', 'pasted'],
    }

    helpers = list(root.rglob('HaogeCallRecorderRealtime'))
    assert len(helpers) == 1
    helper = helpers[0]
    verify_macho(helper)
    assert helper.stat().st_mode & 0o7777 == 0o755
    ldid = subprocess.check_output(['which','ldid'], text=True).strip()
    ent = plistlib.loads(subprocess.check_output([ldid, '-e', str(helper)]))
    for key in ('platform-application','com.apple.coreaudio.CanRecordWithoutSessionActivation',
                'com.apple.coreaudio.CanTapTelephony','com.apple.coreaudio.app-tap',
                'com.apple.coreaudio.private.SystemWideTap','com.apple.private.security.no-container'):
        assert ent.get(key) is True, key
    assert 'kTCCServiceMicrophone' in ent.get('com.apple.private.tcc.allow', [])

    licenses = list(root.rglob('LAME-COPYING'))
    assert len(licenses) == 1
    assert not list(root.rglob('libmp3lame.a')) and not list(root.rglob('lame-3.100.tar.gz'))
    assert not list(root.rglob('CallRecordings')) and not list(root.rglob('*.mp3'))
    icon = bundle / 'icon@2x.png'
    png = icon.read_bytes()
    assert png[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack_from('>II', png, 16) == (60,60)
    assert hashlib.sha256(png).hexdigest() == '5cd386d9a35ff076a9ea2bb6962de10200ebabee5b35c0a8c01cc7b248438cbf'

    payload = subprocess.check_output(['dpkg-deb','--fsys-tarfile',str(package)])
    import io
    with tarfile.open(fileobj=io.BytesIO(payload), mode='r|*') as archive:
        for item in archive:
            assert item.uid == 0 and item.gid == 0, ('non-root package ownership', item.name)
    print('PASS one HaogeSpringTwelve injection dylib + separately signed realtime helper')
    print('PASS arm64e signatures, helper entitlements/mode, phone settings, icon, license, no user audio')
print('Package SHA256', hashlib.sha256(package.read_bytes()).hexdigest())
