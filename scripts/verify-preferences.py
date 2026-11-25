#!/usr/bin/env python3
"""Check the exact three navigation pages and the unchanged 5acb437 key contract."""
from pathlib import Path
import json, plistlib, sys
project = Path(__file__).resolve().parent.parent
resources = Path(sys.argv[1]) if len(sys.argv) > 1 else project/'AxsSpringTwelvePrefs/Resources'
contract = json.loads((project/'scripts/preferences-contract.json').read_text())
root = plistlib.loads((resources/'AxsSpringTwelveRoot.plist').read_bytes())
pages = [('Phone','电话设置',4),('DisableHide','禁用和隐藏',12),('General','常规设置',7)]
assert len(root['items']) == 3
seen = {}
for link,(name,title,count) in zip(root['items'], pages):
    cls = 'AxsSpringTwelve'+name+'ListController'
    assert link == {'cell':'PSLinkCell','label':title,'detail':cls}, link
    resource = 'AxsSpringTwelve'+name
    page = plistlib.loads((resources/(resource+'.plist')).read_bytes())
    assert page['title'] == title
    values = [d for d in page['items'] if 'key' in d]
    assert len(values) == count, (title, len(values))
    for item in values:
        key = item['key']; assert key not in seen, ('Duplicate key',key)
        seen[key] = {k:item[k] for k in ['cell','defaults','default','PostNotification'] if k in item}
    controller = (project/'AxsSpringTwelvePrefs'/(cls+'.m')).read_text()
    assert '@interface '+cls+' : AxsSpringTwelveRootListController' in controller
    assert '@"'+resource+'"' in controller
assert seen == contract, ('Lost/added/changed keys', set(contract)-set(seen),set(seen)-set(contract))
for path in resources.glob('*.plist'):
    plistlib.loads(path.read_bytes())
print('Preferences PASS: root=3 real links; child switches=4/12/7; all 23 non-recording keys unique; cell/default/domain/notification unchanged; plist parse PASS')
