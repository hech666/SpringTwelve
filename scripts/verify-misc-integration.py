#!/usr/bin/env python3
"""Check startup integration structure; this does not execute private iOS hooks."""
from pathlib import Path
import hashlib, plistlib, re
R=Path(__file__).resolve().parent.parent
entry=(R/'Hooks/HaogeSpringTwelveMisc.xm').read_text()
assert entry.count('%ctor') == 1
assert 'HaogeSpringTwelveConfig' not in entry
assert 'haoge_springtwelve_readPreferences()' in entry
for bit, installer in [('HaogeSpringTwelveMiscIOS27','HaogeSpringTwelveInstallIOS27StatusBar'),
                       ('HaogeSpringTwelveMiscMotionX','HaogeSpringTwelveInstallMotionX')]:
    assert f'if (modules & {bit}) {installer}();' in entry
assert entry.index('haoge_springtwelve_readPreferences()') < entry.index('haoge_springtwelve_miscStartupModules(')
files=list((R/'Sources').glob('HaogeSpringTwelveI27*.mm'))
assert len(files)==4
motion=R/'Sources/HaogeSpringTwelveMotionX.mm'
for file in files+[motion]:
    source=file.read_text()
    assert not re.search(r'__attribute__\s*\(\(\s*constructor',source),file
    assert 'HaogeSpringTwelveConfig' not in source, file
hooks=(R/'Sources/HaogeSpringTwelveI27Hooks.mm').read_text()
assert 'extern "C" void HaogeSpringTwelveInstallIOS27StatusBar(void)' in hooks
assert 'dispatch_once(&installOnce' in hooks
assert 'else HaogeSpringTwelveI27SuppressNativeNetworkImage(view);' in hooks
mx=motion.read_text()
assert 'extern "C" void HaogeSpringTwelveInstallMotionX(void)' in mx
assert 'pthread_once(&HaogeSpringTwelveMotionXInstallOnce, HaogeSpringTwelveMotionXInitialize);' in mx
assert mx.index('HaogeSpringTwelveMotionXProcess("replayd")') < mx.index('HaogeSpringTwelveMotionXProcess("backboardd")')
for selector in ['systemRecording','setPreferredFrameRateRange:','RPMovieWriter','maximumFramesPerSecond']:
    assert selector in mx
mk=(R/'Makefile').read_text()
assert 'Sources/HaogeSpringTwelveMotionX.mm_CFLAGS += -fno-objc-arc' in mk
assert 'CoreMedia' in mk and 'HaogeSpringTwelve_LIBRARIES = substrate' in mk
assert re.findall(r'^TWEAK_NAME\s*=\s*(.+)',mk,re.M)==['HaogeSpringTwelve']
main=(R/'Hooks/HaogeSpringTwelveMain.xm').read_text()
for process in ['SpringBoard','MobilePhone','druid','pasted']:
    assert f'@"{process}"' in main
# Installation scripts must remain exactly the 45 baseline; no imported killall.
for rel, digest in {
    'layout/DEBIAN/postinst':'39835750365772a249603418baf4d6e4bbf7e5b90d2728b173fcdbb4e9998fc2',
    'layout/DEBIAN/postrm':'ABSENT',
}.items():
    p=R/rel
    if digest=='ABSENT': assert not p.exists(), rel
    else: assert hashlib.sha256(p.read_bytes()).hexdigest()==digest, rel
print('PASS Misc source integration: 2 startup-gated explicit installers; no imported constructor; 1 dylib; MRC scoped; original install scripts unchanged (not hook/device tests)')
