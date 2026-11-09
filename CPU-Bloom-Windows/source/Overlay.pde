// Overlay mode (`--overlay`): a small borderless window that stays on top of
// other windows and on every workspace. Drag it to move it, scroll to resize
// it, press Esc to close it. Its position and size persist in
// overlay.properties in the config directory (see configDir() in Settings.pde).

boolean overlay = false;
int overlayX = -1, overlayY = -1, overlaySize = -1;
int dragX, dragY;

// NEWT window calls block on JOGL's event thread, which in turn waits for the
// GL context held by Processing's animation thread, so calling them from
// draw() or an input handler deadlocks. Run them on a thread of their own.
java.util.concurrent.ExecutorService windowOps = java.util.concurrent.Executors.newSingleThreadExecutor(r -> {
  Thread t = new Thread(r, "window-ops");
  t.setDaemon(true);
  return t;
});

File overlayConfig() {
  return new File(configDir(), "overlay.properties");
}

void loadOverlayGeometry() {
  Properties p = new Properties();
  try (FileInputStream in = new FileInputStream(overlayConfig())) {
    p.load(in);
    overlayX = Integer.parseInt(p.getProperty("x", "-1"));
    overlayY = Integer.parseInt(p.getProperty("y", "-1"));
    overlaySize = Integer.parseInt(p.getProperty("size", "-1"));
  } catch (Exception e) {
    // First run or unreadable file: keep the defaults.
  }
  // Default to ~15% of the screen height so it suits both HD and 5K/6K screens.
  if (overlaySize <= 0) overlaySize = round(displayHeight * 0.15);
  overlaySize = clampOverlaySize(overlaySize);
}

int clampOverlaySize(int s) {
  return constrain(s, 160, max(160, displayHeight / 2));
}

void saveOverlayGeometry() {
  com.jogamp.newt.Window w = newtWindow();
  if (w == null) return;
  Properties p = new Properties();
  p.setProperty("x", str(w.getX()));
  p.setProperty("y", str(w.getY()));
  p.setProperty("size", str(overlaySize));
  File f = overlayConfig();
  f.getParentFile().mkdirs();
  try (FileOutputStream out = new FileOutputStream(f)) {
    p.store(out, "CPU Bloom overlay geometry");
  } catch (IOException e) {
    println("Could not save overlay geometry: " + e);
  }
}

com.jogamp.newt.Window newtWindow() {
  Object n = surface.getNative();
  return n instanceof com.jogamp.newt.Window ? (com.jogamp.newt.Window) n : null;
}

void configureOverlayWindow() {
  final com.jogamp.newt.Window w = newtWindow();
  if (w == null) return;
  windowOps.submit(() -> {
    w.setUndecorated(true);
    w.setAlwaysOnTop(true);
    w.setSticky(true);
    // Default spot: top-right corner, just below GNOME's top bar.
    int margin = round(overlaySize * 0.08);
    int x = overlayX >= 0 ? overlayX : w.getScreen().getWidth() - overlaySize - margin;
    int y = overlayY >= 0 ? overlayY : margin + round(displayHeight * 0.03);
    w.setPosition(x, y);
  });
}

void mousePressed() {
  if (!overlay) { desktopMousePressed(); return; }
  dragX = mouseX;
  dragY = mouseY;
}

void mouseDragged() {
  if (!overlay) { desktopMouseDragged(); return; }
  final com.jogamp.newt.Window w = newtWindow();
  // The window moves under the pointer, so the grab offset stays constant.
  final int dx = mouseX - dragX, dy = mouseY - dragY;
  if (w != null) windowOps.submit(() -> w.setPosition(w.getX() + dx, w.getY() + dy));
}

void mouseReleased() {
  resizingNormal = false;
  if (overlay) windowOps.submit(() -> saveOverlayGeometry());
}

void mouseWheel(processing.event.MouseEvent e) {
  if (!overlay) return;
  overlaySize = clampOverlaySize(overlaySize - e.getCount() * round(displayHeight * 0.01));
  final com.jogamp.newt.Window w = newtWindow();
  if (w == null) return;
  windowOps.submit(() -> {
    w.setSize(overlaySize, overlaySize);
    saveOverlayGeometry();
  });
}
