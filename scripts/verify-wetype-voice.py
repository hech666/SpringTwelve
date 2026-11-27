#!/usr/bin/env python3
"""Check WeType integration contracts and synthetic control-flow models, not UIKit."""
from pathlib import Path
import itertools, json, plistlib
project = Path(__file__).resolve().parent.parent
source = (project/'Hooks/HaogeSpringTwelveWeTypeVoice.xm').read_text()
general = plistlib.loads((project/'HaogeSpringTwelvePrefs/Resources/HaogeSpringTwelveGeneral.plist').read_bytes())
item = [x for x in general['items'] if x.get('key') == 'weTypeVoiceNoJump']
assert len(item) == 1 and item[0]['default'] is False
assert item[0]['label'] == '微信输入法语音免跳转'
assert item[0]['defaults'] == 'com.haoge.springtwelve'
assert source.count('%hook ') == 2 and source.count('%orig') == 2
for marker in ['com.tencent.wetype', 'WXKBURL_STARTVOICERECORD',
               'objectForActivationSetting:5', 'flagForActivationSetting:42',
               'snapshotViewAfterScreenUpdates:NO', 'snapshot.userInteractionEnabled = NO;',
               'animateWithDuration:0.3 delay:0.3 options:0',
               'HaogeSpringTwelvePreferencesChanged',
               'haoge_springtwelve_wetypeFading addObject:snapshot',
               'haoge_springtwelve_wetypeFading removeObject:snapshot',
               'haoge_springtwelve_wetypeFading allObjects']:
    assert marker in source, marker
for forbidden in ['com.82flex.wtvrbgprefs', 'com.baidu.', 'com.sogou.', 'com.iflytek.',
                  'setFlag:', 'setObject:', 'initWithSuiteName:', 'writeToFile:']:
    assert forbidden not in source, forbidden
ctor = source[source.index('%ctor {'):]
assert ctor.index('@"com.apple.springboard"') < ctor.index('%init(')
assert ctor.index('@"SpringBoard"') < ctor.index('%init(')
assert 'HaogeSpringTwelveOn(@"weTypeVoiceNoJump")' not in ctor[:ctor.index('%init(')]
assert 'defaultValue:@NO' in (project/'Sources/HaogeSpringTwelveSwitches.h').read_text()
# Boolean model derived from the recovered predicates. This does not execute ObjC.
count = 0
for on,main,pe,ce,target,nsurl,scheme,host,src,flag,orig in itertools.product([False, True], repeat=11):
    result = orig
    save = False
    if on and main and pe and ce:
        if target and nsurl and scheme and host:
            result, save = True, True
        elif src and flag:
            result = True
    expected_save = on and main and pe and ce and target and nsurl and scheme and host
    expected = orig or expected_save or (on and main and pe and ce and src and flag)
    assert result == expected and save == expected_save
    count += 1
# Main-thread lifecycle model: cached and in-flight fades both removed on disable.
def clear(state):
    state['source'] = None
    state['visible'].discard(state['cached'])
    state['cached'] = None
    state['visible'].difference_update(state['fading'])
    state['fading'].clear()
for cache in [None, 'new']:
    for fades in [set(), {'old'}, {'old', 'older'}]:
        state = {'source':'app', 'cached':cache, 'fading':fades.copy(),
                 'visible': fades | ({cache} if cache else set())}
        clear(state)
        assert state == {'source':None,'cached':None,'fading':set(),'visible':set()}
# A late completion for an old fade must not remove a newer fade.
state = {'source':'app','cached':None,'fading':{'old'},'visible':{'old'}}
clear(state)
state['fading'].add('new'); state['visible'].add('new')
state['fading'].discard('old'); state['visible'].discard('old')
assert state['visible'] == {'new'} and state['fading'] == {'new'}
print(f'PASS WeType integration: General default-OFF key, 2 SB-only hooks, exact constants; synthetic predicate cases={count}, lifecycle cases=7 (not iOS runtime tests)')
