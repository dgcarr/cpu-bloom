// All theme/render actions run on Processing's animation thread. AWT owns the
// tray, while native window operations stay on windowOps to avoid GL deadlocks.
final java.util.concurrent.ConcurrentLinkedQueue<Runnable> desktopActions =
  new java.util.concurrent.ConcurrentLinkedQueue<Runnable>();
volatile java.awt.TrayIcon desktopTray;
volatile boolean desktopClosing = false, hiddenInTray = false;
boolean desktopMenuOpen = false, desktopPreferences = false;
boolean resizingNormal = false;
int resizeStartX, resizeStartY, resizeStartWidth, resizeStartHeight;
volatile int resizeTargetWidth, resizeTargetHeight;
final java.util.concurrent.atomic.AtomicBoolean resizeQueued = new java.util.concurrent.atomic.AtomicBoolean();
volatile boolean startupEnabled = false, startupBusy = false;
volatile String desktopStatus = "";

boolean windowsDesktop() { return System.getProperty("os.name").startsWith("Windows"); }

void queueDesktopAction(Runnable action) {
  desktopActions.add(action);
  requestAnimationFrame();
}

void runDesktopActions() {
  Runnable action;
  while ((action = desktopActions.poll()) != null) action.run();
}

void chooseDesktopTheme(String id) {
  requestedTheme = null;
  setTheme(id);
  saveSetting("theme", theme.id());
}

void initializeDesktopControls() {
  startupEnabled = !isStorePackage() && windowsDesktop() && startupShortcut().isFile();
  refreshPackagedStartup();
  if (canImportPortableSettings()) desktopStatus = "Portable settings available in Preferences";
  if (!windowsDesktop() || !java.awt.SystemTray.isSupported()) return;
  java.awt.EventQueue.invokeLater(() -> {
    if (desktopClosing) return;
    try {
      java.awt.image.BufferedImage icon = new java.awt.image.BufferedImage(32, 32, java.awt.image.BufferedImage.TYPE_INT_ARGB);
      java.awt.Graphics2D g = icon.createGraphics();
      g.setRenderingHint(java.awt.RenderingHints.KEY_ANTIALIASING, java.awt.RenderingHints.VALUE_ANTIALIAS_ON);
      for (int i = 0; i < 8; i++) {
        g.setColor(java.awt.Color.getHSBColor(i / 8.0f, 0.75f, 0.95f));
        g.fillOval(12 + (int)(9 * Math.cos(i * Math.PI / 4)), 12 + (int)(9 * Math.sin(i * Math.PI / 4)), 9, 9);
      }
      g.setColor(java.awt.Color.WHITE); g.fillOval(12, 12, 9, 9); g.dispose();
      java.awt.PopupMenu menu = new java.awt.PopupMenu();
      java.awt.MenuItem show = new java.awt.MenuItem("Show CPU Bloom");
      show.addActionListener(e -> restoreDesktopWindow()); menu.add(show);
      java.awt.Menu themeMenu = new java.awt.Menu("Theme");
      for (Theme t : themes) {
        java.awt.MenuItem item = new java.awt.MenuItem(t.name());
        item.addActionListener(e -> { queueDesktopAction(() -> chooseDesktopTheme(t.id())); restoreDesktopWindow(); });
        themeMenu.add(item);
      }
      menu.add(themeMenu);
      java.awt.MenuItem preferences = new java.awt.MenuItem("Preferences...");
      preferences.addActionListener(e -> {
        queueDesktopAction(() -> { desktopMenuOpen = true; desktopPreferences = true; refreshPackagedStartup(); });
        restoreDesktopWindow();
      });
      menu.add(preferences);
      java.awt.MenuItem hide = new java.awt.MenuItem("Minimize to tray");
      hide.addActionListener(e -> minimizeDesktopToTray()); menu.add(hide);
      menu.addSeparator();
      java.awt.MenuItem quit = new java.awt.MenuItem("Quit");
      quit.addActionListener(e -> { queueDesktopAction(() -> exit()); restoreDesktopWindow(); }); menu.add(quit);
      java.awt.TrayIcon tray = new java.awt.TrayIcon(icon, "CPU Bloom", menu);
      tray.setImageAutoSize(true);
      tray.addActionListener(e -> restoreDesktopWindow());
      java.awt.SystemTray.getSystemTray().add(tray);
      desktopTray = tray;
      // Hide only after the tray icon exists, so a failed tray initialization
      // always leaves a usable window. Normal manual launches remain visible.
      if (args != null && Arrays.asList(args).contains("--start-minimized")) minimizeDesktopToTray();
      requestAnimationFrame();
    } catch (Exception e) {
      desktopStatus = "System tray unavailable";
      println("Could not create system tray: " + e);
    }
  });
}

void removeDesktopTray() {
  desktopClosing = true;
  java.awt.EventQueue.invokeLater(() -> {
    if (desktopTray != null) java.awt.SystemTray.getSystemTray().remove(desktopTray);
    desktopTray = null;
  });
}

void minimizeDesktopToTray() {
  if (desktopTray == null || hiddenInTray || desktopClosing) return;
  hiddenInTray = true;
  windowOps.submit(() -> newtWindow().setVisible(false));
}

void restoreDesktopWindow() {
  if (desktopClosing) return;
  windowOps.submit(() -> {
    com.jogamp.newt.Window w = newtWindow();
    if (windowsDesktop()) {
      com.sun.jna.platform.win32.WinDef.HWND hwnd = new com.sun.jna.platform.win32.WinDef.HWND(new Pointer(w.getWindowHandle()));
      com.sun.jna.platform.win32.User32.INSTANCE.ShowWindow(hwnd, 9); // SW_RESTORE
    }
    w.setVisible(true);
    w.requestFocus();
    hiddenInTray = false;
    requestAnimationFrame();
  });
}

interface DesktopUser32 extends com.sun.jna.win32.StdCallLibrary {
  boolean IsIconic(com.sun.jna.platform.win32.WinDef.HWND hwnd);
}
DesktopUser32 desktopUser32;
void pollDesktopMinimize() {
  if (!windowsDesktop() || overlay || desktopTray == null || hiddenInTray || desktopClosing) return;
  if (desktopUser32 == null) desktopUser32 = Native.load("user32", DesktopUser32.class);
  if (desktopUser32.IsIconic(new com.sun.jna.platform.win32.WinDef.HWND(new Pointer(newtWindow().getWindowHandle())))) {
    minimizeDesktopToTray();
  }
}

String[] desktopMenuLabels() {
  if (desktopPreferences) return new String[] {
    "Preferences",
    "Start with Windows" + (startupBusy ? " ..." : ""),
    "Always on top",
    isStorePackage() ? "Import portable settings..." : "Export preferences...",
    "Back"
  };
  String[] labels = new String[themes.size() + 4];
  labels[0] = "Theme";
  for (int i = 0; i < themes.size(); i++) labels[i + 1] = (themes.get(i) == theme ? "* " : "  ") + themes.get(i).name();
  labels[themes.size() + 1] = "Preferences...";
  labels[themes.size() + 2] = desktopTray != null ? "Minimize to tray" : "System tray unavailable";
  labels[themes.size() + 3] = "Quit";
  return labels;
}

int desktopMenuRowHeight() {
  return constrain((height - 90) / desktopMenuLabels().length, 18, 38);
}

void drawDesktopControls() {
  pushStyle();
  colorMode(RGB, 255); blendMode(BLEND);
  rectMode(CORNER); textAlign(LEFT, CENTER); useFont(20);
  noStroke(); fill(30, 36, 48, 245); rect(width - 112, 12, 100, 38, 7);
  fill(240); text(desktopMenuOpen ? "Close" : "Menu", width - 96, 31);
  if (desktopMenuOpen) {
    String[] labels = desktopMenuLabels();
    int menuX = max(8, width - 320);
    int rowHeight = desktopMenuRowHeight();
    useFont(min(20, rowHeight - 4));
    fill(24, 29, 40, 250); rect(menuX, 58, 308, labels.length * rowHeight + 12, 8);
    for (int i = 0; i < labels.length; i++) {
      int rowY = 64 + i * rowHeight;
      int centerY = rowY + rowHeight / 2;
      if (i > 0 && mouseX >= menuX && mouseX < width - 12 && mouseY >= rowY && mouseY < rowY + rowHeight) {
        fill(55, 68, 88); rect(menuX + 4, rowY, 300, rowHeight, 4);
      }
      fill(i == 0 ? 150 : 240);
      boolean checkbox = desktopPreferences && (i == 1 || i == 2);
      text(labels[i], menuX + (checkbox ? 42 : 14), centerY);
      if (checkbox) {
        noFill(); stroke(200); strokeWeight(2); rect(menuX + 14, centerY - 8, 16, 16, 2);
        if (i == 1 ? startupEnabled : alwaysOnTop) {
          line(menuX + 17, centerY, menuX + 21, centerY + 4);
          line(menuX + 21, centerY + 4, menuX + 28, centerY - 5);
        }
        noStroke();
      }
    }
    if (!desktopStatus.isEmpty()) { useFont(14); fill(240); text(desktopStatus, menuX + 8, 86 + labels.length * rowHeight); }
  }
  // An explicit, generous hit target works even when Windows' thin native
  // resize border is difficult to grab on a high-DPI monitor.
  fill(30, 36, 48, 230); rect(width - 32, height - 32, 32, 32);
  stroke(200); strokeWeight(2);
  for (int i = 8; i <= 24; i += 8) line(width - i, height - 4, width - 4, height - i);
  popStyle();
}

void desktopMousePressed() {
  requestAnimationFrame();
  if (mouseButton != LEFT) return;
  if (mouseX >= width - 32 && mouseY >= height - 32) {
    resizingNormal = true;
    resizeStartX = mouseX; resizeStartY = mouseY;
    resizeStartWidth = newtWindow().getWidth(); resizeStartHeight = newtWindow().getHeight();
    return;
  }
  if (mouseX >= width - 112 && mouseY >= 12 && mouseY <= 50) {
    desktopMenuOpen = !desktopMenuOpen; desktopPreferences = false; return;
  }
  if (!desktopMenuOpen) return;
  int row = (mouseY - 64) / desktopMenuRowHeight();
  if (mouseX < max(8, width - 320) || mouseX >= width - 12 || mouseY < 64 || row >= desktopMenuLabels().length) {
    desktopMenuOpen = false; return;
  }
  if (desktopPreferences) {
    if (row == 1 && windowsDesktop() && !startupBusy) setDesktopStartup(!startupEnabled);
    if (row == 2) toggleAlwaysOnTop();
    if (row == 3 && isStorePackage()) offerPortableSettingsImport();
    if (row == 3 && !isStorePackage()) offerPortableSettingsExport();
    if (row == 4) desktopPreferences = false;
  } else {
    if (row >= 1 && row <= themes.size()) { chooseDesktopTheme(themes.get(row - 1).id()); desktopMenuOpen = false; }
    if (row == themes.size() + 1) { desktopPreferences = true; desktopStatus = ""; refreshPackagedStartup(); }
    if (row == themes.size() + 2) { desktopMenuOpen = false; minimizeDesktopToTray(); }
    if (row == themes.size() + 3) exit();
  }
}

void desktopMouseDragged() {
  if (!resizingNormal) return;
  resizeTargetWidth = max(320, resizeStartWidth + mouseX - resizeStartX);
  resizeTargetHeight = max(240, resizeStartHeight + mouseY - resizeStartY);
  if (resizeQueued.compareAndSet(false, true)) windowOps.submit(() -> {
    try {
      int w, h;
      do {
        w = resizeTargetWidth; h = resizeTargetHeight;
        newtWindow().setSize(w, h);
      } while (w != resizeTargetWidth || h != resizeTargetHeight);
    } finally { resizeQueued.set(false); }
  });
}

File startupShortcut() {
  return new File(System.getenv("APPDATA"), "Microsoft/Windows/Start Menu/Programs/Startup/CPU Bloom.lnk");
}

String powershellLiteral(String s) { return "'" + s.replace("'", "''") + "'"; }

void setDesktopStartup(final boolean enabled) {
  startupBusy = true;
  desktopStatus = "";
  windowOps.submit(() -> {
    try {
      if (isStorePackage()) {
        String state = packagedStartupState(enabled ? "startup-enable" : "startup-disable");
        desktopStatus = state.equals("Enabled") ? "Starts in tray at Windows login" : "Windows startup is off";
        updatePackagedStartupState(state);
        return;
      }
      File shortcut = startupShortcut();
      if (enabled) {
        File jar = new File(cpu_bloom.class.getProtectionDomain().getCodeSource().getLocation().toURI());
        File directory = jar.getParentFile().getParentFile();
        File launcher = new File(directory, "cpu_bloom.exe");
        if (!launcher.isFile()) throw new IOException("Windows launcher not found");
        shortcut.getParentFile().mkdirs();
        String script = "$ErrorActionPreference='Stop'; $shell=New-Object -ComObject WScript.Shell; $link=$shell.CreateShortcut(" + powershellLiteral(shortcut.getAbsolutePath()) + ");"
          + "$link.TargetPath=" + powershellLiteral(launcher.getAbsolutePath()) + ";$link.WorkingDirectory=" + powershellLiteral(directory.getAbsolutePath()) + ";$link.Arguments='--start-minimized';$link.Description='CPU Bloom';$link.Save()";
        String encoded = java.util.Base64.getEncoder().encodeToString(script.getBytes(java.nio.charset.StandardCharsets.UTF_16LE));
        File powershell = new File(System.getenv("SystemRoot"), "System32/WindowsPowerShell/v1.0/powershell.exe");
        Process process = new ProcessBuilder(powershell.getAbsolutePath(), "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-EncodedCommand", encoded).redirectErrorStream(true).start();
        if (!process.waitFor(20, java.util.concurrent.TimeUnit.SECONDS)) { process.destroyForcibly(); throw new IOException("Startup shortcut timed out"); }
        if (process.exitValue() != 0 || !shortcut.isFile()) throw new IOException("Could not create startup shortcut");
      } else {
        java.nio.file.Files.deleteIfExists(shortcut.toPath());
      }
      startupEnabled = shortcut.isFile();
      desktopStatus = enabled ? "Starts in tray at Windows login" : "Windows startup is off";
    } catch (Exception e) {
      desktopStatus = "Could not update Windows startup";
      println(desktopStatus + ": " + e);
    } finally { startupBusy = false; requestAnimationFrame(); }
  });
}
