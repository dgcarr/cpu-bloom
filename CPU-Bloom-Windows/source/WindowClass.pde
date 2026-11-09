// GNOME matches a window to its .desktop entry (dock icon, grouping, Alt+Tab)
// by the X11 WM_CLASS property. JOGL's NEWT windows don't set one, so set it
// here, along with _NET_WM_PID, by calling Xlib through JNA (code/jna-*.jar).

import com.sun.jna.Library;
import com.sun.jna.Native;
import com.sun.jna.NativeLong;
import com.sun.jna.Pointer;

final String WM_CLASS_NAME = "cpu-bloom";

interface Xlib extends Library {
  Pointer XOpenDisplay(String name);
  NativeLong XInternAtom(Pointer display, String name, boolean onlyIfExists);
  int XChangeProperty(Pointer display, NativeLong window, NativeLong property, NativeLong type,
                      int format, int mode, byte[] data, int nelements);
  int XChangeProperty(Pointer display, NativeLong window, NativeLong property, NativeLong type,
                      int format, int mode, long[] data, int nelements);
  NativeLong XDefaultRootWindow(Pointer display);
  int XGetWindowProperty(Pointer display, NativeLong window, NativeLong property,
      NativeLong offset, NativeLong length, boolean delete, NativeLong requestedType,
      com.sun.jna.ptr.NativeLongByReference actualType, com.sun.jna.ptr.IntByReference format,
      com.sun.jna.ptr.NativeLongByReference count, com.sun.jna.ptr.NativeLongByReference bytesAfter,
      com.sun.jna.ptr.PointerByReference value);
  int XFree(Pointer value);
  int XFlush(Pointer display);
  int XCloseDisplay(Pointer display);
}

void setWindowClass() {
  final long XA_CARDINAL = 6, XA_STRING = 31;
  final int PROP_MODE_REPLACE = 0;
  try {
    Object nativeWindow = surface.getNative();
    if (!(nativeWindow instanceof com.jogamp.newt.Window)) return;
    com.jogamp.newt.Window w = (com.jogamp.newt.Window) nativeWindow;
    if (!com.jogamp.nativewindow.NativeWindowFactory.TYPE_X11.equals(w.getScreen().getDisplay().getType())) return;

    // By soname, so dlopen finds it on LD_LIBRARY_PATH too (as in the snap).
    Xlib x = Native.load("libX11.so.6", Xlib.class);
    Pointer dpy = x.XOpenDisplay(null);
    if (dpy == null) return;
    NativeLong win = new NativeLong(w.getWindowHandle());

    // WM_CLASS is two NUL-terminated strings: instance name, then class name.
    byte[] cls = (WM_CLASS_NAME + "\0" + WM_CLASS_NAME + "\0").getBytes("US-ASCII");
    x.XChangeProperty(dpy, win, x.XInternAtom(dpy, "WM_CLASS", false), new NativeLong(XA_STRING),
                      8, PROP_MODE_REPLACE, cls, cls.length);
    long[] pid = { ProcessHandle.current().pid() };
    x.XChangeProperty(dpy, win, x.XInternAtom(dpy, "_NET_WM_PID", false), new NativeLong(XA_CARDINAL),
                      32, PROP_MODE_REPLACE, pid, 1);
    x.XFlush(dpy);
    x.XCloseDisplay(dpy);
  } catch (Throwable e) {
    println("Could not set WM_CLASS: " + e);
  }
}
