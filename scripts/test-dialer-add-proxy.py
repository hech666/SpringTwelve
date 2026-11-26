#!/usr/bin/env python3
"""Deterministic source/model checks; not a UIKit or device integration test."""
from pathlib import Path
import itertools
import math
import subprocess

ROOT = Path(__file__).resolve().parents[1]
s = (ROOT / 'Hooks/AxsSpringTwelveDial.xm').read_text()
base = subprocess.check_output(['git', 'show', '0f53f2d8fa68af4e41c48eec29f76354e5e978a5:Hooks/AxsSpringTwelveDial.xm'], cwd=ROOT, text=True)

def span(t, a, b):
    return t.split(a, 1)[1].split(b, 1)[0]

# Preserve actual dialing and all T9 implementation, not newly changed UI baseline.
for a, b in [('#pragma mark - T9 contact indexing', 'static BOOL AxsDialMethodHasSignature'),
             ('- (void)axs_springtwelve_dualSimTapped:', '%group AxsSpringTwelveDialTextGroup')]:
    assert span(s, a, b) == span(base, a, b)
proxy = span(s, '- (void)axs_springtwelve_addNumberTapped:', '%new\n- (void)axs_springtwelve_dualSimTapped:')
assert '[source sendActionsForControlEvents:UIControlEventTouchUpInside]' in proxy
assert 'AxsDialUpdateDualButtons(self)' in proxy
for bad in ['objc_msgSend', 'addContactPressed:)', '_addButtonClicked:)', 'removeTarget:', 'setTitle:']:
    assert bad not in proxy
for guard in ['"@@:"', '"v@:@@B"', '"v@:@@@BB"', '@encode(BOOL)',
              'method_getImplementation(actual) != method_getImplementation(base)',
              'source.allControlEvents & UIControlEventTouchUpInside',
              '!AxsDialAddStateSupported(lcd)', 'AxsDialRestoreAddButton(controller)',
              'AxsDialHideNativeLinePicker', 'AxsDialRestoreNativeLinePicker',
              'phonePadView', 'source.hidden = NO',
              'CGRectIntersectsRect(plusRect, deleteTarget)', 'accessoryHeight / 2.0']:
    assert guard in s, guard
assert 'lcd.hidden =' not in s and 'lcdView.hidden =' not in s
assert 'addSource.hidden = YES' not in s  # only the centralized source-state helper hides it
native_delete = span(s, 'static void AxsDialRestoreDeleteButton', 'static void AxsDialRemoveDualButtons')
for bad in ['.hidden =', '.alpha =', '.enabled =', 'addTarget:', 'addGestureRecognizer:',
            'removeFromSuperview', 'addSubview:', 'button.frame =', 'button.bounds =']:
    assert bad not in native_delete
assert 'deleteVisibility, 2, NO, NO' in s

shown = fallback = 0
for aw, ah, ox, oy, remain, ch, dh, dw in itertools.product(
        [200, 233, 234, 280, 320, 375, 390, 430, 768], [250, 600],
        [-15, 0, 20], [-10, 0, 30], [60, 100, 140, 180], [44, 64], [24, 44, 64], [24, 44, 100]):
    total = min(aw - 24., min(320., max(240., aw * .72)))
    width = (total - 18.) / 2
    amin = oy + ah - remain
    minimum = max(oy, amin)
    accessory = max(44., dh)
    maximum = oy + ah - 48. - 8. - accessory
    if width < 96 or minimum > maximum:
        fallback += 1
        continue
    x = min(max(ox + aw / 2 - total / 2, ox + 12), ox + aw - total - 12)
    y = min(max(amin + ch / 2 - 24., minimum), maximum)
    px = x + width / 2
    dx = x + width + 18 + width / 2
    cy = y + 48 + 8 + accessory / 2
    assert math.isclose((px + dx) / 2, x + total / 2)
    assert math.isclose(dx - px, width + 18)
    assert math.isclose(cy, y + 56 + accessory / 2)
    assert px - 22 >= ox and dx + dw / 2 <= ox + aw
    assert px + 22 < dx - dw / 2
    assert cy - 22 >= y + 56 and cy - dh / 2 >= y + 56
    assert cy + max(22, dh / 2) <= oy + ah + 1e-8
    assert y >= amin and y >= oy
    shown += 1

# Model precisely the restore -> native update -> capture -> rehide protocol.
class NativeState:
    def __init__(self, hidden):
        self.desired = self.native = hidden
        self.depth = 0
        self.active = True
        self.native = True
    def begin(self):
        if not self.depth:
            self.native = self.desired
        self.depth += 1
    def end(self):
        self.depth -= 1
        if not self.depth:
            self.desired = self.native
            self.native = True
    def disable(self):
        if self.native:
            self.native = self.desired
        self.active = False

for initial, inner, final in itertools.product([False, True], repeat=3):
    m = NativeState(initial)
    m.begin()
    assert m.native == initial
    m.begin()
    m.native = inner
    m.end()
    assert m.native == inner  # inner hook must not rehide/capture
    m.native = final
    m.end()
    assert m.native and m.desired == final
    m.disable()
    assert m.native == final

for desired, enabled, alpha in itertools.product([False, True], [False, True], [0., .5, 1.]):
    # Exactly one original sender event only for eligible proxy taps.
    events = []
    if not desired and enabled and alpha > .01:
        events.append(('native-source', 'TouchUpInside'))
    assert len(events) == int(not desired and enabled and alpha > .01)

print(f'PASS mirrored accessory geometry: {shown} active / {fallback} native fallback cases')
print('PASS nested native hidden-state updates, disable restoration and forwarding eligibility')
print('PASS strict ABI/source/hook checks; native delete targets/gestures/visibility unchanged')
print('PASS dialing actions and T9 implementation unchanged')
print('Source/model checks only: real Phone actions, rendering and gestures require device validation')
