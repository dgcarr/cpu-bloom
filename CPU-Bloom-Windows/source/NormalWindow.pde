// Normal-window dimensions are in logical desktop units, not framebuffer pixels.
// Keep these separate from overlay geometry and shared theme settings.
int normalWidth, normalHeight;
java.awt.Rectangle normalWorkArea;

File normalGeometryFile() {
  return new File(configDir(), "window.properties");
}

int savedNormalDimension(Properties p, String key, int fallback) {
  try {
    int value = Integer.parseInt(p.getProperty(key, ""));
    return value > 0 ? value : fallback;
  } catch (NumberFormatException e) {
    return fallback;
  }
}

void loadNormalGeometry() {
  normalWorkArea = new java.awt.Rectangle(0, 0, displayWidth, displayHeight);
  try {
    java.awt.GraphicsConfiguration gc = java.awt.GraphicsEnvironment
      .getLocalGraphicsEnvironment().getDefaultScreenDevice().getDefaultConfiguration();
    java.awt.Rectangle bounds = gc.getBounds();
    java.awt.Insets insets = java.awt.Toolkit.getDefaultToolkit().getScreenInsets(gc);
    normalWorkArea = new java.awt.Rectangle(bounds.x + insets.left, bounds.y + insets.top,
      bounds.width - insets.left - insets.right, bounds.height - insets.top - insets.bottom);
  } catch (Exception e) {
    println("Could not read desktop work area: " + e);
  }
  // Leave room for window borders, title bar and a little desktop around it.
  int maxWidth = max(1, normalWorkArea.width - 48);
  int maxHeight = max(1, normalWorkArea.height - 80);
  float scale = min(1.0f, min(normalWorkArea.width * 0.8f / 1280,
    normalWorkArea.height * 0.8f / 820));
  Properties p = new Properties();
  try (FileInputStream in = new FileInputStream(normalGeometryFile())) {
    p.load(in);
  } catch (IOException e) {
    // First launch: use a proportional default that fits the desktop.
  }
  normalWidth = constrain(savedNormalDimension(p, "width", round(1280 * scale)),
    min(320, maxWidth), maxWidth);
  normalHeight = constrain(savedNormalDimension(p, "height", round(820 * scale)),
    min(240, maxHeight), maxHeight);
}

synchronized void saveNormalGeometry(com.jogamp.newt.Window w) {
  if (overlay || w.getWidth() <= 0 || w.getHeight() <= 0 || !w.isVisible()) return;
  Properties p = new Properties();
  p.setProperty("width", str(w.getWidth()));
  p.setProperty("height", str(w.getHeight()));
  File f = normalGeometryFile();
  f.getParentFile().mkdirs();
  try (FileOutputStream out = new FileOutputStream(f)) {
    p.store(out, "CPU Bloom normal window size");
  } catch (IOException e) {
    println("Could not save normal window size: " + e);
  }
}

void configureNormalWindow() {
  final com.jogamp.newt.Window w = newtWindow();
  if (w == null) return;
  w.addWindowListener(new com.jogamp.newt.event.WindowAdapter() {
    public void windowResized(com.jogamp.newt.event.WindowEvent e) {
      // NEWT reports logical size even on scaled Windows displays. This also
      // persists resizes while rendering is paused, without relying on draw().
      saveNormalGeometry(w);
    }
  });
  windowOps.submit(() -> {
    w.setResizable(true);
    w.setPosition(normalWorkArea.x + (normalWorkArea.width - normalWidth) / 2,
      normalWorkArea.y + max(40, (normalWorkArea.height - normalHeight) / 2));
    saveNormalGeometry(w);
  });
}
