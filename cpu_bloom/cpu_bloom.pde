// CPU Bloom: a live system monitor for Linux with switchable themes. This
// tab is the host: it samples the system, runs the window (normal or
// overlay), draws the HUD and hands the rest of each frame to the active
// Theme. Themes live in their own tabs; see Theme.pde and THEMES.md.
//
// Arguments: --overlay, --theme=<id>, --list-themes.

import java.io.*;
import java.nio.file.*;
import java.util.*;

SystemSampler sampler;

// Font name as Java sees it; createFont falls back to a default font if missing.
final String UI_FONT = "Ubuntu Sans Regular";
HashMap<Integer, PFont> fontCache = new HashMap<Integer, PFont>();

boolean showHud = true;
volatile boolean paused = false;
RenderActivity renderActivity;
String requestedTheme = null;  // from --theme=<id>

// Set CPU_BLOOM_SNAPSHOT=/path/out.png to save one frame after warm-up and quit.
String snapshotPath = System.getenv("CPU_BLOOM_SNAPSHOT");
int snapshotAt = -1;

// Set CPU_BLOOM_RECORD=/some/dir to save a frame every 100 ms for 15 s and
// quit, for checking motion (pair it with CPU_BLOOM_FAKE_LOAD).
String recordDir = System.getenv("CPU_BLOOM_RECORD");
int nextRecordAt = 0;

void settings() {
  List<String> argList = args == null ? new ArrayList<String>() : Arrays.asList(args);
  discoverThemes();
  if (argList.contains("--list-themes")) {
    printThemes();
    System.exit(0);
  }
  for (String a : argList) {
    if (a.startsWith("--theme=")) requestedTheme = a.substring("--theme=".length());
  }

  overlay = argList.contains("--overlay");
  if (overlay) {
    loadOverlayGeometry();
    size(overlaySize, overlaySize, P2D);
  } else {
    size(1280, 820, P2D);
  }
  smooth(4);
}

void setup() {
  surface.setTitle(overlay ? "CPU Bloom Overlay" : "CPU Bloom");
  surface.setResizable(!overlay);
  colorMode(HSB, 360, 100, 100, 100);
  if (overlay) showHud = false;

  println("OpenGL: " + PGraphicsOpenGL.OPENGL_RENDERER + " / " + PGraphicsOpenGL.OPENGL_VERSION);

  sampler = new SystemSampler();
  Runtime.getRuntime().addShutdownHook(new Thread(() -> sampler.close(), "sampler-shutdown"));
  Thread t = new Thread(sampler, "system-sampler");
  t.setDaemon(true);
  t.start();

  String saved = loadSettings().getProperty("theme", DEFAULT_THEME);
  setTheme(requestedTheme != null ? requestedTheme : saved);
  println("Theme: " + theme.id() + " (available: " + themes.size() + ")");
  if (snapshotPath != null) snapshotAt = millis() + 8000;
}

void draw() {
  if (frameCount == 2) {  // the native window exists by now
    setWindowClass();
    if (overlay) configureOverlayWindow();
    renderActivity = new RenderActivity();
    renderActivity.start();
  }
  if (renderActivity != null) renderActivity.beforeFrame();
  syncSettings();

  pushStyle();
  blendMode(BLEND);
  theme.draw(overlay);
  blendMode(BLEND);
  popStyle();
  if (showHud) drawHud();
  if (renderActivity != null) renderActivity.afterFrame();

  if (recordDir != null && millis() >= nextRecordAt) {
    if (millis() > 15000) exit();
    save(recordDir + "/frame-" + nf(millis(), 5) + ".jpg");
    nextRecordAt = millis() + 100;
  }

  if (snapshotAt > 0 && millis() >= snapshotAt) {
    save(snapshotPath);
    println("snapshot " + snapshotPath + "  theme " + theme.id() + "  fps " + nf(frameRate, 0, 1));
    exit();
  }
}

// Bitmap fonts look jagged or blurry when scaled with textSize(), so each
// font is rasterised at the exact pixel size it is drawn at and cached.
void useFont(float px) {
  int size = max(6, round(px));
  PFont f = fontCache.get(size);
  if (f == null) {
    f = createFont(UI_FONT, size, true);
    fontCache.put(size, f);
  }
  textFont(f, size);
}

void drawHud() {
  colorMode(HSB, 360, 100, 100, 100);
  // Grow the HUD with the window so it stays readable on large/HiDPI screens.
  float k = max(1, min(width, height) / 820f);
  float x = 24 * k, y = 22 * k, lh = 25 * k, pad = 16 * k;

  ArrayList<String> lines = new ArrayList<String>();
  ArrayList<Integer> colors = new ArrayList<Integer>();
  lines.add(sampler.cpuModel);
  colors.add(color(0, 0, 100, 92));
  lines.add(sampler.cpuCount + " threads · " + sampler.coreCount + " cores · load " + sampler.loadAvg);
  colors.add(color(0, 0, 100, 80));
  lines.add(String.format("RAM   %.1f / %.1f GiB", sampler.memUsedGiB, sampler.memTotalGiB));
  colors.add(color(210, 25, 100, 95));
  if (sampler.gpuSeen) {
    lines.add(String.format("GPU   %.0f%% · %.0f°C · %.1f / %.1f GiB", sampler.gpuUtil, sampler.gpuTempC,
                            sampler.gpuMemUsedGiB, sampler.gpuMemTotalGiB));
    colors.add(color(95, 60, 95, 95));
  }
  String legend = theme.legend();
  lines.add(theme.name() + (legend.isEmpty() ? "" : " · " + legend) + " · " + round(frameRate) + " fps"
            + (paused ? " · paused" : "") + (alwaysOnTop ? " · on top" : ""));
  colors.add(color(0, 0, 100, 60));

  useFont(17 * k);
  float w = 0;
  for (String l : lines) w = max(w, textWidth(l));
  noStroke();
  fill(232, 50, 5, 72);
  rect(x - pad, y - pad, w + 2 * pad, 34 * k + lines.size() * lh + pad * 1.4, 12 * k);

  textAlign(LEFT, TOP);
  useFont(21 * k);
  fill(0, 0, 100);
  text("CPU Bloom", x, y);
  y += 34 * k;
  useFont(17 * k);
  for (int i = 0; i < lines.size(); i++) {
    fill(colors.get(i));
    text(lines.get(i), x, y);
    y += lh;
  }

  textAlign(LEFT, BOTTOM);
  useFont(16 * k);
  fill(0, 0, 100, 60);
  String themeKeys = theme.keyHelp();
  text("H hud    P pause    N theme    A on top    S screenshot" + (themeKeys.isEmpty() ? "" : "    " + themeKeys),
       x, height - 20 * k);
}

void keyPressed() {
  // The overlay takes focus when it opens (often at login, mid-typing), so it
  // ignores keys; Esc still closes it because PApplet handles that itself.
  if (overlay) return;
  requestAnimationFrame();
  char k = Character.toLowerCase(key);
  switch (k) {
    case 'h': showHud = !showHud; break;
    case 'p': case ' ': paused = !paused; break;
    case 'n': nextTheme(); break;
    case 'a': if (!overlay) toggleAlwaysOnTop(); break;
    case 's':
      // ~/Pictures rather than the sketch folder, which is read-only-ish once installed.
      // In a snap, HOME is the snap's private one; SNAP_REAL_HOME is the user's.
      String home = System.getenv("SNAP_REAL_HOME");
      if (home == null) home = System.getProperty("user.home");
      String file = home + "/Pictures/CPU Bloom/cpu-bloom-"
                    + nf(year(), 4) + nf(month(), 2) + nf(day(), 2) + "-"
                    + nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2) + ".png";
      save(file);
      println("saved " + file);
      break;
    default:
      theme.keyPressed(k);
  }
}

// Wake a paused surface after an input/settings change without lowering the
// frame rate or leaving a GL swap loop running while nothing changes.
void requestAnimationFrame() {
  if (renderActivity != null) renderActivity.requestFrame();
}

public void dispose() {
  if (renderActivity != null) renderActivity.close();
  if (sampler != null) sampler.close();
  if (theme != null) theme.stop();
  windowOps.shutdownNow();
  super.dispose();
}

int animationMillis() {
  return renderActivity == null ? millis() : renderActivity.animationTime();
}
