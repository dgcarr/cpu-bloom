// Settings shared with the top-bar indicator through
// $XDG_CONFIG_HOME/cpu-bloom/settings.properties (~/.config by default):
//
//   alwaysOnTop=true|false   full window stays above others (A key / menu)
//   theme=<id>               active theme (N key / Theme menu)
//
// Both sides write the file and pick up each other's changes from it. (The
// overlay is always on top regardless of alwaysOnTop.)

boolean alwaysOnTop = false;
long settingsStamp = -1;
int lastSettingsCheck = -250;

// The per-user config directory, as GLib.get_user_config_dir() finds it in tray.js.
File configDir() {
  String xdg = System.getenv("XDG_CONFIG_HOME");
  File base = xdg != null && xdg.startsWith("/") ? new File(xdg) : new File(System.getProperty("user.home"), ".config");
  return new File(base, "cpu-bloom");
}

File settingsFile() {
  return new File(configDir(), "settings.properties");
}

Properties loadSettings() {
  Properties p = new Properties();
  try (FileInputStream in = new FileInputStream(settingsFile())) {
    p.load(in);
  } catch (IOException e) {
    // Missing or unreadable: defaults apply.
  }
  return p;
}

// Updates one key, keeping the others.
void saveSetting(String key, String value) {
  Properties p = loadSettings();
  p.setProperty(key, value);
  File f = settingsFile();
  f.getParentFile().mkdirs();
  try (FileOutputStream out = new FileOutputStream(f)) {
    p.store(out, "CPU Bloom settings");
  } catch (IOException e) {
    println("Could not save settings: " + e);
  }
  settingsStamp = f.lastModified();
}

// Called every frame; only re-reads the file when its timestamp changes.
void syncSettings() {
  if (!paused && millis() - lastSettingsCheck < 250) return;
  lastSettingsCheck = millis();
  long stamp = settingsFile().lastModified();  // 0 when the file is missing
  if (stamp == settingsStamp) return;
  settingsStamp = stamp;
  Properties p = loadSettings();
  if (!overlay) applyAlwaysOnTop(Boolean.parseBoolean(p.getProperty("alwaysOnTop", "false")));
  // A --theme=<id> on the command line pins the theme for this run.
  if (requestedTheme == null) setTheme(p.getProperty("theme", DEFAULT_THEME));
}

void applyAlwaysOnTop(final boolean on) {
  alwaysOnTop = on;
  final com.jogamp.newt.Window w = newtWindow();
  if (w != null) windowOps.submit(() -> w.setAlwaysOnTop(on));
}

void toggleAlwaysOnTop() {
  applyAlwaysOnTop(!alwaysOnTop);
  saveSetting("alwaysOnTop", str(alwaysOnTop));
}
