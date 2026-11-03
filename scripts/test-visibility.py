#!/usr/bin/env python3
"""Live X11/Xwayland smoke test: pass exported launcher and log directory."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tests'))
import x11_helpers as b
import ctypes as C
import os
import pathlib
import time
import subprocess
import csv
import tempfile

class KeyEvent(C.Structure):
    _fields_ = [('type', C.c_int), ('serial', C.c_ulong), ('send_event', C.c_int), ('display', C.c_void_p), ('window', C.c_ulong), ('root', C.c_ulong), ('subwindow', C.c_ulong), ('time', C.c_ulong), ('x', C.c_int), ('y', C.c_int), ('x_root', C.c_int), ('y_root', C.c_int), ('state', C.c_uint), ('keycode', C.c_uint), ('same_screen', C.c_int)]

class Event(C.Union):
    _fields_ = [('key', KeyEvent), ('pad', C.c_long * 24)]
b.x.XStringToKeysym.argtypes = [C.c_char_p]
b.x.XStringToKeysym.restype = C.c_ulong
b.x.XKeysymToKeycode.argtypes = [C.c_void_p, C.c_ulong]
b.x.XKeysymToKeycode.restype = C.c_uint
b.x.XSendEvent.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_long, C.c_void_p]

def key(w, name):
    e = Event()
    e.key.display = b.d
    e.key.window = w
    e.key.root = b.root
    e.key.same_screen = 1
    e.key.keycode = b.x.XKeysymToKeycode(b.d, b.x.XStringToKeysym(name.encode()))
    for t in [2, 3]:
        e.key.type = t
        b.x.XSendEvent(b.d, w, 0, 1 << t - 2, C.byref(e))
        b.x.XFlush(b.d)
        time.sleep(0.1)

def state(path):
    rows = list(csv.DictReader(path.read_text().splitlines()))
    assert rows, 'no metrics'
    return rows[-1]

def stable(path, reason):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        a = state(path)
        if a['stopped'] == 'true':
            break
        time.sleep(0.3)
    time.sleep(2)
    c = state(path)
    assert a['frames'] == c['frames'], (reason, a, c)
    assert c['stopped'] == 'true', (reason, c)
    return c
if __name__ == '__main__':
    import sys
    launcher = sys.argv[1]
    output = pathlib.Path(sys.argv[2]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    for theme in sys.argv[3:] or ['bloom', 'poppy', 'ridge']:
        with tempfile.TemporaryDirectory() as tmp:
            config = pathlib.Path(tmp) / 'cpu-bloom'
            config.mkdir()
            settings = config / 'settings.properties'
            settings.write_text('theme=' + theme + '\n')
            metrics = output / (theme + '.csv')
            with open(output / (theme + '.log'), 'w') as log:
                p = subprocess.Popen([launcher], env={**os.environ, 'XDG_CONFIG_HOME': tmp, 'CPU_BLOOM_METRICS': str(metrics), 'CPU_BLOOM_FAKE_LOAD': '0.5', 'CPU_BLOOM_FAKE_TEMP': '60'}, stdout=log, stderr=subprocess.STDOUT)
                try:
                    time.sleep(6)
                    w = b.window(p.pid)
                    assert w, 'no window'
                    a = state(metrics)
                    time.sleep(2)
                    assert int(state(metrics)['frames']) > int(a['frames']), 'visible frames stopped'
                    b.x.XIconifyWindow(b.d, w, 0)
                    b.x.XFlush(b.d)
                    print(theme, 'minimized', stable(metrics, 'minimized'), flush=True)
                    b.restore(w)
                    time.sleep(2)
                    a = state(metrics)
                    time.sleep(2)
                    assert int(state(metrics)['frames']) > int(a['frames']), 'restore stalled'
                    key(w, 'p')
                    print(theme, 'paused', stable(metrics, 'pause'), flush=True)
                    key(w, 'h')
                    time.sleep(2)
                    print(theme, 'paused redraw', stable(metrics, 'HUD change'), flush=True)
                    settings.write_text('theme=' + ('ridge' if theme != 'ridge' else 'poppy') + '\n')
                    time.sleep(2)
                    s = state(metrics)
                    assert s['theme'] != theme, ('paused theme change failed', s)
                    key(w, 'p')
                    time.sleep(2)
                    a = state(metrics)
                    time.sleep(2)
                    assert int(state(metrics)['frames']) > int(a['frames']), 'unpause stalled'
                    current = (b.prop(b.root, '_NET_CURRENT_DESKTOP') or [0])[0]
                    count = (b.prop(b.root, '_NET_NUMBER_OF_DESKTOPS') or [0])[0]
                    if count > 1:
                        b.message(w, '_NET_WM_DESKTOP', [(current + 1) % count, 2])
                        print(theme, 'off workspace', stable(metrics, 'workspace'), flush=True)
                        b.message(w, '_NET_WM_DESKTOP', [current, 2])
                        b.restore(w)
                        time.sleep(2)
                    b.message(w, '_NET_CLOSE_WINDOW', [0, 2])
                    p.wait(timeout=8)
                    assert p.returncode == 0, ('close failed', p.returncode)
                    print(theme, 'PASS', flush=True)
                finally:
                    if p.poll() is None:
                        p.terminate()
                        p.wait(timeout=10)
