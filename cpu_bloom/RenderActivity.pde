// A stopped JOGL animator does no periodic GL swaps. noLoop() alone still
// swaps buffers in Processing's DrawListener. Keep a cheap, independent
// watcher alive so minimizing never prevents restoration or settings updates.
// Focus is deliberately ignored: an unfocused window may still be visible.
class RenderActivity implements Runnable {
  final java.util.concurrent.atomic.AtomicLong requests = new java.util.concurrent.atomic.AtomicLong();
  volatile long renderedRequest = -1;
  volatile boolean running = true, resumePending = false;
  volatile long frames = 0;
  Thread watcher;
  com.jogamp.newt.Window window;
  Xlib x;
  Pointer display;
  NativeLong win, root, stateAtom, hiddenAtom, desktopAtom, currentDesktopAtom, wmStateAtom;
  long observedSettings = -1;
  boolean stopped = false;
  PrintWriter metrics;
  long lastMetricsAt = 0;
  long frozenAt = -1, excludedMs = 0;

  synchronized int animationTime() {
    long now = frozenAt >= 0 ? frozenAt : millis();
    return (int) (now - excludedMs);
  }

  synchronized void setClockRunning(boolean animate) {
    if (!animate && frozenAt < 0) frozenAt = millis();
    else if (animate && frozenAt >= 0) {
      excludedMs += millis() - frozenAt;
      frozenAt = -1;
    }
  }

  void start() {
    window = newtWindow();
    if (window == null) return;
    window.addWindowListener(new com.jogamp.newt.event.WindowAdapter() {
      public void windowResized(com.jogamp.newt.event.WindowEvent e) { requestFrame(); }
      public void windowRepaint(com.jogamp.newt.event.WindowUpdateEvent e) { requestFrame(); }
      public void windowDestroyNotify(com.jogamp.newt.event.WindowEvent e) {
        running = false;
        // Processing handles exit on the animation thread, even when paused.
        surface.resumeThread();
      }
    });
    window.addKeyListener(new com.jogamp.newt.event.KeyAdapter() {
      public void keyPressed(com.jogamp.newt.event.KeyEvent e) { requestFrame(); }
      public void keyReleased(com.jogamp.newt.event.KeyEvent e) { requestFrame(); }
    });
    window.addMouseListener(new com.jogamp.newt.event.MouseAdapter() {
      public void mousePressed(com.jogamp.newt.event.MouseEvent e) { requestFrame(); }
      public void mouseReleased(com.jogamp.newt.event.MouseEvent e) { requestFrame(); }
      public void mouseDragged(com.jogamp.newt.event.MouseEvent e) { requestFrame(); }
      public void mouseWheelMoved(com.jogamp.newt.event.MouseEvent e) { requestFrame(); }
    });
    watcher = new Thread(this, "render-activity");
    watcher.setDaemon(true);
    watcher.start();
  }

  void requestFrame() { requests.incrementAndGet(); }

  void beforeFrame() {
    if (resumePending) {
      resumePending = false;
      theme.resumeAnimation();
    }
  }

  void afterFrame() {
    renderedRequest = requests.get();
    frames++;
  }

  NativeLong atom(String name) { return x.XInternAtom(display, name, false); }

  long[] property(NativeLong target, NativeLong atom) {
    com.sun.jna.ptr.NativeLongByReference type = new com.sun.jna.ptr.NativeLongByReference();
    com.sun.jna.ptr.IntByReference format = new com.sun.jna.ptr.IntByReference();
    com.sun.jna.ptr.NativeLongByReference count = new com.sun.jna.ptr.NativeLongByReference();
    com.sun.jna.ptr.NativeLongByReference remaining = new com.sun.jna.ptr.NativeLongByReference();
    com.sun.jna.ptr.PointerByReference data = new com.sun.jna.ptr.PointerByReference();
    int result = x.XGetWindowProperty(display, target, atom, new NativeLong(0), new NativeLong(64),
      false, new NativeLong(0), type, format, count, remaining, data);
    Pointer p = data.getValue();
    try {
      if (result != 0 || format.getValue() != 32 || p == null) return new long[0];
      int n = (int) count.getValue().longValue();
      long[] values = new long[n];
      for (int i = 0; i < n; i++) values[i] = p.getNativeLong((long) i * NativeLong.SIZE).longValue() & 0xffffffffL;
      return values;
    } finally {
      if (p != null) x.XFree(p);
    }
  }

  boolean visible() {
    if (!window.isVisible()) return false;
    if (display == null) return true; // unsupported WMs fail open
    for (long state : property(win, stateAtom)) if (state == hiddenAtom.longValue()) return false;
    long[] wmState = property(win, wmStateAtom);
    if (wmState.length > 0 && wmState[0] == 3) return false; // ICCCM IconicState
    long[] desktop = property(win, desktopAtom), current = property(root, currentDesktopAtom);
    return desktop.length == 0 || current.length == 0 || desktop[0] == 0xffffffffL || desktop[0] == current[0];
  }

  public void run() {
    try {
      String metricsPath = System.getenv("CPU_BLOOM_METRICS");
      if (metricsPath != null) {
        metrics = new PrintWriter(new FileWriter(metricsPath));
        metrics.println("time_ms,frames,visible,paused,stopped,theme");
      }
      if (com.jogamp.nativewindow.NativeWindowFactory.TYPE_X11.equals(window.getScreen().getDisplay().getType())) {
        x = Native.load("libX11.so.6", Xlib.class);  // by soname, see WindowClass
        display = x.XOpenDisplay(null); // owned only by this thread
        if (display != null) {
          win = new NativeLong(window.getWindowHandle());
          root = x.XDefaultRootWindow(display);
          stateAtom = atom("_NET_WM_STATE"); hiddenAtom = atom("_NET_WM_STATE_HIDDEN");
          desktopAtom = atom("_NET_WM_DESKTOP"); currentDesktopAtom = atom("_NET_CURRENT_DESKTOP");
          wmStateAtom = atom("WM_STATE");
        }
      }
      while (running && window.isNativeValid()) {
        pollNormalActivation();
        pollDesktopMinimize();
        long stamp = settingsFile().lastModified();
        if (stamp != observedSettings) { observedSettings = stamp; requestFrame(); }
        boolean shown = visible();
        boolean animate = shown && !paused;
        setClockRunning(animate);
        theme.setSuspended(!shown);
        sampler.setGpuActive(animate);
        boolean shouldRun = shown && (!paused || requests.get() != renderedRequest);
        if (!shouldRun && !stopped) {
          surface.pauseThread();
          stopped = true;
        } else if (shouldRun && stopped) {
          resumePending = true;
          surface.resumeThread();
          stopped = false;
        }
        if (metrics != null && System.currentTimeMillis() - lastMetricsAt >= 1000) {
          lastMetricsAt = System.currentTimeMillis();
          metrics.println(lastMetricsAt + "," + frames + "," + shown + "," + paused + "," + stopped + "," + theme.id());
          metrics.flush();
        }
        Thread.sleep(200);
      }
    } catch (InterruptedException e) {
      // Normal shutdown.
    } catch (Throwable e) {
      println("Visibility monitoring unavailable: " + e);
    } finally {
      if (metrics != null) metrics.close();
      if (display != null) x.XCloseDisplay(display);
      if (running) { // monitoring failure must never strand a window
        setClockRunning(true);
        resumePending = true;
        theme.setSuspended(false);
        sampler.setGpuActive(true);
        surface.resumeThread();
      }
    }
  }

  void close() {
    running = false;
    if (watcher != null) watcher.interrupt();
  }
}
