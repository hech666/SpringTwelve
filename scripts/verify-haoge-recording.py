#!/usr/bin/env python3
"""Guard the imported standalone4 engine and Haoge single-dylib integration."""
from pathlib import Path
import hashlib, json, plistlib, re, sys
R=Path(__file__).resolve().parent.parent
EXPECTED={
 'HaogeRealtimeHelper/HaogeCallRecorderRealtime.mm':'579df8987cb518f47c6ccff4268f44b47a7527f8d07a85ca1d6d10edf1cadfb2',
 'HaogeRealtimeHelper/HaogeCallRecorderPCM.cpp':'ee2eac5ecc62a5a612f51f0aae97115ac4801e09a1f4daf57b91db2edf192eb4',
 'HaogeRealtimeHelper/HaogeCallRecorderPCM.h':'4ad90aeebd1fd0419c2e5b6bb7d24cec80665d9c2c2c433df48914f94d548b7f',
 'HaogeRealtimeHelper/HaogeCallRecorderValidation.h':'df1db2a49d95824f574fc1f5a7b62849d115fc0980019ec5d6c3fe5271e87083',
 'HaogeRealtimeHelper/entitlements.plist':'8179e6921467000438f487ec7979223f1954518003c88831f3ed208563043ec3',
 'Sources/HaogeCallRecorderControl.h':'9d1d7717d4981e2f6edd9ec7d915f1f053e8dd6855caa9e116cf85960f65277c',
}
for name,digest in EXPECTED.items():
 p=R/name; assert p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==digest, name
assert hashlib.sha256((R/'MP3Helper/vendor/lame-3.100.tar.gz').read_bytes()).hexdigest()=='ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e'
mk=(R/'Makefile').read_text(); assert mk.count('TWEAK_NAME =')==1 and 'TWEAK_NAME = HaogeSpringTwelve' in mk
assert 'Sources/*.mm' in mk and 'HaogeRealtimeHelper' in mk
assert 'HAOGE_CALLRECORDER_LAME_PREFIX' in (R/'HaogeRealtimeHelper/Makefile').read_text()
assert (R/'MP3Helper/README.md').is_file()
keys=['callRecordingEnabled','callRecordingListEnabled','captureReplaceFavoritesTab','captureReplaceVoicemailTab']
page=plistlib.loads((R/'HaogeSpringTwelvePrefs/Resources/HaogeSpringTwelvePhone.plist').read_bytes())
found={i['key']:i for i in page['items'] if 'key' in i}
for k in keys:
 assert k in found and found[k]['default'] is False and found[k]['defaults']=='com.haoge.springtwelve'
switch=(R/'Sources/HaogeCallRecorderSwitches.h').read_text()
assert 'return HaogeSpringTwelveOn(key);' in switch
for f in ['Hooks/HaogeCallRecording.xm','Hooks/HaogeRecordings.xm']:
 s=(R/f).read_text(); assert 'HaogeSpringTwelvePreferencesChanged' in s
 assert not re.search(r'\bAxsCallRecorder\b|\baxs_callrecorder\b|com\.axs\.callrecorder',s),f
paths=(R/'Sources/HaogeSpringTwelvePaths.h').read_text()
assert 'com.axs.springtwelve.plist' in paths and 'com.haoge.springtwelve.plist' in paths
assert 'AxsSpringTwelve-' in (R/'Hooks/HaogeRecordings.xm').read_text() # legacy audio filename read-only compatibility
control=(R/'control').read_text()
assert 'Package: com.haoge.springtwelve' in control and 'Conflicts: com.axs.springtwelve' in control
assert not any('AxsCallRecorder' in p.name for p in R.rglob('*'))
print('PASS exact renamed standalone4 engine/control hashes and pinned LAME source')
print('PASS one tweak dylib target, shared prefs, 4 default-OFF phone recording switches, Haoge names')
