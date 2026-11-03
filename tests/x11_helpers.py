"""Minimal X11 helpers for testing only CPU Bloom windows; no Python dependencies."""
import ctypes as C, subprocess, time, os, json, pathlib
x = C.CDLL('libX11.so.6')
x.XOpenDisplay.argtypes = [C.c_char_p]
x.XOpenDisplay.restype = C.c_void_p
d = x.XOpenDisplay(None)
if not d:
    raise RuntimeError('An X11/Xwayland display is required')
for name, args, ret in [('XDefaultRootWindow', [C.c_void_p], C.c_ulong), ('XInternAtom', [C.c_void_p, C.c_char_p, C.c_int], C.c_ulong), ('XGetWindowProperty', [C.c_void_p, C.c_ulong, C.c_ulong, C.c_long, C.c_long, C.c_int, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_int), C.POINTER(C.c_ulong), C.POINTER(C.c_ulong), C.POINTER(C.c_void_p)], C.c_int), ('XFree', [C.c_void_p], C.c_int), ('XIconifyWindow', [C.c_void_p, C.c_ulong, C.c_int], C.c_int), ('XMapRaised', [C.c_void_p, C.c_ulong], C.c_int), ('XFlush', [C.c_void_p], C.c_int)]:
    f = getattr(x, name)
    f.argtypes = args
    f.restype = ret
root = x.XDefaultRootWindow(d)

def prop(w, name):
    a = C.c_ulong()
    f = C.c_int()
    n = C.c_ulong()
    b = C.c_ulong()
    p = C.c_void_p()
    x.XGetWindowProperty(d, w, x.XInternAtom(d, name.encode(), 0), 0, 1024, 0, 0, C.byref(a), C.byref(f), C.byref(n), C.byref(b), C.byref(p))
    vals = list((C.c_ulong * n.value).from_address(p.value)) if p.value and f.value == 32 else []
    if p.value:
        x.XFree(p)
    return vals

def window(pid):
    for w in prop(root, '_NET_CLIENT_LIST'):
        if prop(w, '_NET_WM_PID') == [pid]:
            return w
    return None

class ClientData(C.Union):
    _fields_ = [('b', C.c_char * 20), ('s', C.c_short * 10), ('l', C.c_long * 5)]

class ClientMessage(C.Structure):
    _fields_ = [('type', C.c_int), ('serial', C.c_ulong), ('send_event', C.c_int), ('display', C.c_void_p), ('window', C.c_ulong), ('message_type', C.c_ulong), ('format', C.c_int), ('data', ClientData)]

class Event(C.Union):
    _fields_ = [('client', ClientMessage), ('pad', C.c_long * 24)]
x.XSendEvent.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_long, C.POINTER(Event)]

def message(w, name, values):
    e = Event()
    e.client.type = 33
    e.client.display = d
    e.client.window = w
    e.client.message_type = x.XInternAtom(d, name.encode(), 0)
    e.client.format = 32
    for i, v in enumerate(values):
        e.client.data.l[i] = v
    x.XSendEvent(d, root, 0, 1 << 20 | 1 << 19, C.byref(e))
    x.XFlush(d)

def restore(w):
    x.XMapRaised(d, w)
    message(w, '_NET_ACTIVE_WINDOW', [2, 0, 0])
    x.XFlush(d)

def ticks(pid):
    s = pathlib.Path(f'/proc/{pid}/stat').read_text().split(') ', 1)[1].split()
    return int(s[11]) + int(s[12])

def sample(pid, seconds=4):
    a = ticks(pid)
    t = time.monotonic()
    time.sleep(seconds)
    status = pathlib.Path(f'/proc/{pid}/status').read_text()
    return {'cpu_one_core_pct': round(100 * (ticks(pid) - a) / os.sysconf('SC_CLK_TCK') / (time.monotonic() - t), 2), 'rss_kib': int(status.split('VmRSS:')[1].split()[0])}
