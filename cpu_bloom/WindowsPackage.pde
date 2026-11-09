// The packaged launcher supplies paths obtained from Windows APIs. Portable
// launches keep their existing storage and startup implementation.
boolean isStorePackage() { return "1".equals(System.getenv("CPU_BLOOM_PACKAGED")); }

File applicationDirectory() {
  String supplied = System.getenv("CPU_BLOOM_APP_DIR");
  if (supplied != null) return new File(supplied);
  try {
    File jar = new File(cpu_bloom.class.getProtectionDomain().getCodeSource().getLocation().toURI());
    return jar.getParentFile().getParentFile();
  } catch (Exception e) { throw new IllegalStateException("Cannot locate application", e); }
}

File packageDirectory(String variable) {
  String value = System.getenv(variable);
  if (value == null || !new File(value).isAbsolute())
    throw new IllegalStateException("Packaged launcher did not supply " + variable);
  return new File(value);
}

String packagedStartupState(String operation) throws Exception {
  if (!Arrays.asList("startup-query", "startup-enable", "startup-disable").contains(operation))
    throw new IllegalArgumentException("Invalid startup operation");
  File helper = new File(applicationDirectory(), "store-bridge.exe");
  Process process = new ProcessBuilder(helper.getAbsolutePath(), operation).redirectErrorStream(true).start();
  if (!process.waitFor(15, java.util.concurrent.TimeUnit.SECONDS)) {
    process.destroyForcibly(); throw new IOException("Windows startup request timed out");
  }
  String result = new String(process.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8).trim();
  if (process.exitValue() != 0) throw new IOException("Windows startup request failed: " + result);
  if (!Arrays.asList("Enabled", "Disabled", "EnabledByPolicy", "DisabledByPolicy", "DisabledByUser").contains(result))
    throw new IOException("Unknown Windows startup state");
  return result;
}

void updatePackagedStartupState(String state) {
  startupEnabled = state.equals("Enabled") || state.equals("EnabledByPolicy");
  if (state.equals("DisabledByUser")) desktopStatus = "Enable in Windows Settings > Apps > Startup";
  else if (state.endsWith("ByPolicy")) desktopStatus = "Startup is managed by your organization";
}

void refreshPackagedStartup() {
  if (!isStorePackage() || startupBusy) return;
  startupBusy = true;
  windowOps.submit(() -> {
    try { updatePackagedStartupState(packagedStartupState("startup-query")); }
    catch (Exception e) { desktopStatus = "Windows startup state unavailable"; println(e); }
    finally { startupBusy = false; requestAnimationFrame(); }
  });
}

File screenshotsDirectory() {
  String path = System.getenv("CPU_BLOOM_PICTURES");
  if (windowsDesktop() && path != null) return new File(path, "CPU Bloom");
  if (windowsDesktop()) {
    // Known folders also respect OneDrive and user relocation for portable builds.
    try { return new File(com.sun.jna.platform.win32.Shell32Util.getKnownFolderPath(
      com.sun.jna.platform.win32.KnownFolders.FOLDERID_Pictures), "CPU Bloom"); }
    catch (Exception e) { println("Could not locate Pictures: " + e); }
  }
  String home = System.getenv("SNAP_REAL_HOME");
  return new File(home != null ? home : System.getProperty("user.home"), "Pictures/CPU Bloom");
}

// A per-user lock and fixed activation signal avoid opening network ports. Each
// package's LocalState isolates Store and portable instances. No commands or
// paths are accepted over this channel: a change means only "show the window".
java.nio.channels.FileChannel normalInstanceChannel;
java.nio.channels.FileLock normalInstanceLock;
String normalActivationSeen = "";
File normalActivationFile() { return new File(configDir(), "activate.signal"); }
String readActivationSignal() {
  try { return Files.readString(normalActivationFile().toPath()); }
  catch (IOException e) { return ""; }
}
boolean acquireNormalInstance(boolean startMinimized) {
  if (overlay || !windowsDesktop()) return true;
  try {
    Files.createDirectories(configDir().toPath());
    normalActivationSeen = readActivationSignal();
    normalInstanceChannel = java.nio.channels.FileChannel.open(new File(configDir(), "normal.lock").toPath(),
      StandardOpenOption.CREATE, StandardOpenOption.WRITE);
    normalInstanceLock = normalInstanceChannel.tryLock();
    if (normalInstanceLock != null) return true;
    normalInstanceChannel.close(); normalInstanceChannel = null;
    if (!startMinimized) Files.writeString(normalActivationFile().toPath(), UUID.randomUUID().toString());
    return false;
  } catch (IOException e) {
    throw new IllegalStateException("Cannot coordinate CPU Bloom instances", e);
  }
}
void pollNormalActivation() {
  if (overlay || normalInstanceLock == null) return;
  String signal = readActivationSignal();
  if (!signal.equals(normalActivationSeen)) {
    normalActivationSeen = signal;
    restoreDesktopWindow();
  }
}
void releaseNormalInstance() {
  try {
    if (normalInstanceLock != null) normalInstanceLock.release();
    if (normalInstanceChannel != null) normalInstanceChannel.close();
  } catch (IOException e) { println(e); }
}

boolean canImportPortableSettings() {
  String legacy = System.getenv("CPU_BLOOM_LEGACY_CONFIG");
  return isStorePackage() && legacy != null && new File(legacy, "settings.properties").isFile()
    && !loadSettings().containsKey("portableImport");
}
Properties portablePreferenceValues() {
  Properties source = loadSettings(), result = new Properties();
  result.setProperty("theme", source.getProperty("theme", DEFAULT_THEME));
  result.setProperty("alwaysOnTop", source.getProperty("alwaysOnTop", "false"));
  return result;
}
void exportPortableSettings(File archive) throws IOException {
  try (java.util.zip.ZipOutputStream out = new java.util.zip.ZipOutputStream(new FileOutputStream(archive))) {
    out.putNextEntry(new java.util.zip.ZipEntry("settings.properties"));
    portablePreferenceValues().store(out, "CPU Bloom preferences; startup consent is not exported");
    out.closeEntry();
    Properties geometry = new Properties();
    if (normalGeometryFile().isFile()) try (FileInputStream in = new FileInputStream(normalGeometryFile())) { geometry.load(in); }
    Properties safeGeometry = new Properties();
    for (String key : new String[]{"width", "height"}) if (geometry.containsKey(key)) safeGeometry.setProperty(key, geometry.getProperty(key));
    out.putNextEntry(new java.util.zip.ZipEntry("window.properties"));
    safeGeometry.store(out, "CPU Bloom normal window dimensions"); out.closeEntry();
  }
}
Properties readPreferenceArchive(File archive, String entryName) throws IOException {
  try (java.util.zip.ZipFile zip = new java.util.zip.ZipFile(archive)) {
    java.util.zip.ZipEntry entry = zip.getEntry(entryName);
    Properties result = new Properties();
    if (entry == null) {
      if (entryName.equals("settings.properties")) throw new IOException("Not a CPU Bloom preferences backup");
      return result;
    }
    // No extraction and no path traversal; reject oversized or malformed backups.
    try (InputStream in = zip.getInputStream(entry)) {
      byte[] bytes = in.readNBytes(65537);
      if (bytes.length > 65536) throw new IOException("Preferences backup is too large");
      result.load(new ByteArrayInputStream(bytes));
    }
    return result;
  }
}
void applyImportedPortableSettings(Properties preferences, Properties geometry) throws IOException {
  if (findTheme(preferences.getProperty("theme", "")) != null) chooseDesktopTheme(preferences.getProperty("theme"));
  boolean onTop = Boolean.parseBoolean(preferences.getProperty("alwaysOnTop", "false"));
  applyAlwaysOnTop(onTop); saveSetting("alwaysOnTop", str(onTop));
  if (!geometry.isEmpty()) {
    Properties safeGeometry = new Properties();
    for (String key : new String[]{"width", "height"}) if (geometry.containsKey(key)) safeGeometry.setProperty(key, geometry.getProperty(key));
    try (FileOutputStream out = new FileOutputStream(normalGeometryFile())) { safeGeometry.store(out, "Imported normal size"); }
    loadNormalGeometry();
    windowOps.submit(() -> newtWindow().setSize(normalWidth, normalHeight));
  }
  saveSetting("portableImport", "imported");
  desktopStatus = "Preferences imported; startup unchanged";
}
void offerPortableSettingsExport() {
  java.awt.EventQueue.invokeLater(() -> {
    javax.swing.JFileChooser chooser = new javax.swing.JFileChooser();
    chooser.setDialogTitle("Export CPU Bloom preferences");
    chooser.setSelectedFile(new File("CPU-Bloom-settings.zip"));
    if (chooser.showSaveDialog(null) != javax.swing.JFileChooser.APPROVE_OPTION) return;
    File destination = chooser.getSelectedFile();
    if (destination.exists() && javax.swing.JOptionPane.showConfirmDialog(null, "Replace the selected backup?",
      "CPU Bloom", javax.swing.JOptionPane.YES_NO_OPTION) != javax.swing.JOptionPane.YES_OPTION) return;
    try { exportPortableSettings(destination); desktopStatus = "Preferences exported"; }
    catch (IOException e) { desktopStatus = "Could not export preferences"; println(e); }
    requestAnimationFrame();
  });
}
void offerPortableSettingsImport() {
  if (loadSettings().containsKey("portableImport")) { desktopStatus = "Portable import already completed"; return; }
  if (!canImportPortableSettings()) {
    java.awt.EventQueue.invokeLater(() -> {
      javax.swing.JFileChooser chooser = new javax.swing.JFileChooser();
      chooser.setDialogTitle("Select a backup from Portable Menu > Preferences > Export preferences");
      chooser.setFileFilter(new javax.swing.filechooser.FileNameExtensionFilter("CPU Bloom preferences (*.zip)", "zip"));
      if (chooser.showOpenDialog(null) != javax.swing.JFileChooser.APPROVE_OPTION) return;
      try {
        Properties preferences = readPreferenceArchive(chooser.getSelectedFile(), "settings.properties");
        Properties geometry = readPreferenceArchive(chooser.getSelectedFile(), "window.properties");
        int choice = javax.swing.JOptionPane.showConfirmDialog(null,
          "Import theme, size and always-on-top settings? Windows startup stays unchanged.", "CPU Bloom", javax.swing.JOptionPane.YES_NO_OPTION);
        if (choice != javax.swing.JOptionPane.YES_OPTION) return;
        queueDesktopAction(() -> {
          try { applyImportedPortableSettings(preferences, geometry); }
          catch (IOException e) { desktopStatus = "Import failed; backup unchanged"; println(e); }
        });
      } catch (IOException | IllegalArgumentException e) { desktopStatus = "Invalid preferences backup"; println(e); }
      requestAnimationFrame();
    });
    return;
  }
  java.awt.EventQueue.invokeLater(() -> {
    int choice = javax.swing.JOptionPane.showOptionDialog(null,
      "Import the portable app's theme, window size and always-on-top preference?\n"
      + "Windows startup stays unchanged. The portable installation is kept.",
      "Import CPU Bloom settings", javax.swing.JOptionPane.DEFAULT_OPTION,
      javax.swing.JOptionPane.QUESTION_MESSAGE, null, new String[]{"Import", "Keep defaults", "Later"}, "Import");
    if (choice < 0 || choice == 2) return;
    queueDesktopAction(() -> {
      try {
        if (choice == 0) {
          File legacy = new File(System.getenv("CPU_BLOOM_LEGACY_CONFIG"));
          Properties p = new Properties();
          try (FileInputStream in = new FileInputStream(new File(legacy, "settings.properties"))) { p.load(in); }
          Properties geometry = new Properties();
          File geometryFile = new File(legacy, "window.properties");
          if (geometryFile.isFile()) try (FileInputStream in = new FileInputStream(geometryFile)) { geometry.load(in); }
          applyImportedPortableSettings(p, geometry);
        }
        saveSetting("portableImport", choice == 0 ? "imported" : "declined");
        desktopStatus = choice == 0 ? "Portable settings imported" : "Kept Store defaults";
      } catch (IOException | IllegalArgumentException e) { desktopStatus = "Import failed; portable files unchanged"; println(e); }
    });
    requestAnimationFrame();
  });
}
