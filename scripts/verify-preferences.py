#!/usr/bin/env python3
"""Check all four navigation pages against the integrated preference contract."""
from pathlib import Path
import json, plistlib, sys
project = Path(__file__).resolve().parent.parent
resources = Path(sys.argv[1]) if len(sys.argv) > 1 else project/'HaogeSpringTwelvePrefs/Resources'
contract = json.loads((project/'scripts/preferences-contract.json').read_text())
root = plistlib.loads((resources/'HaogeSpringTwelveRoot.plist').read_bytes())
pages = [('Phone','电话设置',9),('DisableHide','禁用和隐藏',13),('General','常规设置',7),('Misc','杂七杂八',3)]
assert len(root['items']) == 4
seen = {}
for link,(name,title,count) in zip(root['items'], pages):
    cls = 'HaogeSpringTwelve'+name+'ListController'
    assert link == {'cell':'PSLinkCell','label':title,'detail':cls}, link
    resource = 'HaogeSpringTwelve'+name
    page = plistlib.loads((resources/(resource+'.plist')).read_bytes())
    assert page['title'] == title
    values = [d for d in page['items'] if 'key' in d]
    assert len(values) == count, (title, len(values))
    for item in values:
        key = item['key']; assert key not in seen, ('Duplicate key',key)
        seen[key] = {k:item[k] for k in ['cell','defaults','default','PostNotification'] if k in item}
    controller = (project/'HaogeSpringTwelvePrefs'/(cls+'.m')).read_text()
    assert '@interface '+cls+' : HaogeSpringTwelveRootListController' in controller
    assert '@"'+resource+'"' in controller
assert seen == contract, ('Lost/added/changed keys', set(contract)-set(seen),set(seen)-set(contract))
for path in resources.glob('*.plist'):
    plistlib.loads(path.read_bytes())
misc = plistlib.loads((resources/'HaogeSpringTwelveMisc.plist').read_bytes())
assert [(x['key'], x['label']) for x in misc['items'] if 'key' in x] == [
    ('ios27StatusBarEnabled', 'iOS27 状态栏'),
    ('motionX120HzRecordingEnabled', '120hz加120hz 录屏'),
    ('weTypeVoiceNoJump', '微信输入法语音免跳转'),
]
print('Preferences PASS: root=4 real links; child switches=9/13/7/3; all 32 keys unique; Misc names/order and cell/default/domain/notification match contract; plist parse PASS')
