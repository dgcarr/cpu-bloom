// A photorealistic theme pre-rendered offline as a sequence of frames, one per
// step of openness, each saved with a dim and a bright backlight in
// data/<folder>/dim/ and bright/. Openness follows average CPU load and the
// backlight follows CPU temperature. The theme scrubs through the frames,
// crossfading neighbouring frames and the two light levels, so it moves
// smoothly both ways. PoppyTheme and OrchidTheme are the two subclasses.
//
// All the frames decoded would take ~1.6 GB, so a few worker threads decode
// them on demand into a small cache, always starting with the frame nearest
// the current position and looking further ahead in the direction of motion.

import java.util.concurrent.*;

abstract class FrameSequenceTheme extends Theme {
  final int CACHE = 24;           // decoded frames kept, both light levels together
  final int WORKERS = 3;
  final String[] LEVELS = { "dim", "bright" };
  final float TEMP_COOL = 45;     // °C shown with the dim backlight
  final float TEMP_HOT = 90;      // °C shown with the bright one

  String[][] files = new String[2][0];
  int n = 0;                      // frames per level
  final ConcurrentHashMap<Integer, PImage> decoded = new ConcurrentHashMap<Integer, PImage>();
  final Set<Integer> busy = ConcurrentHashMap.newKeySet();
  final Set<Integer> failed = ConcurrentHashMap.newKeySet();
  final Object wake = new Object();
  volatile boolean running = false, suspended = false;
  int runToken = 0, decodeRevision = 0;
  long cachedBytes = 0;
  final long CACHE_BYTES = 24L * 1280 * 1280 * 4;
  int requestedCenter = -1, requestedDirection = 0, requestedLevels = -1;
  volatile float wantPos = 0;     // frame position the workers decode around
  volatile int wantDir = 1;       // direction of motion, +1 opening
  volatile float wantLight = 0;   // bright level's weight, so workers skip an unused level
  volatile int decodeSize = 0;    // 0 = full size; smaller for small windows
  Thread[] workers;

  float load = 0, open = 0, speed = 0;  // filtered load, openness 0..1, its velocity
  float light = -1;                     // bright level's weight 0..1; -1 until first set
  int lastMs = -1;
  int bg;
  boolean bgKnown = false;

  // Frames are data/<folder>/{dim,bright}/<folder>_NNN.jpg.
  abstract String folder();

  // Maps openness (0-1) to a position in the sequence (0-1), so that equal
  // steps of load give roughly equal visible change. The default exponent
  // spends more of the load range on the early frames, where most of
  // Poppy's change is.
  float sequencePosition(float open) { return pow(open, 1.3); }

  // Whether the square frame sits on the window's bottom edge (where the
  // stem leaves it) rather than in the middle.
  boolean anchorBottom() { return true; }

  // The point the flower sways about, as fractions of the frame.
  float pivotX() { return 0.05; }
  float pivotY() { return 1.0; }

  // Spring rates while opening and closing (1/s).
  float openRate() { return 4.0; }
  float closeRate() { return 2.0; }

  // Shown before the first frame decodes and when the frames are missing.
  int fallbackBackground() { return color(4, 14, 13); }

  String legend() {
    float t = sampler.tempC;
    return "openness = average CPU · " + round(open * 100) + "% · light = CPU temp · "
      + (Float.isNaN(t) ? "no sensor" : round(t) + "°C");
  }

  void start() {
    synchronized (wake) {
      for (int level = 0; level < 2; level++) files[level] = findFrames(LEVELS[level]);
      // With only one level rendered, use it for both.
      if (files[0].length == 0) files[0] = files[1];
      if (files[1].length == 0) files[1] = files[0];
      n = min(files[0].length, files[1].length);
      decoded.clear();
      cachedBytes = 0;
      requestedCenter = -1;
      busy.clear();
      failed.clear();
      lastMs = -1;
      light = -1;
      if (n == 0) return;
      running = true;
      final int token = ++runToken;
      workers = new Thread[WORKERS];
      for (int i = 0; i < WORKERS; i++) {
        workers[i] = new Thread(() -> work(token), folder() + "-decoder-" + i);
        workers[i].setDaemon(true);
        workers[i].start();
      }
    }

  }

  void stop() {
    synchronized (wake) {
      running = false;
      runToken++;
      decodeRevision++;
      if (workers != null) for (Thread w : workers) w.interrupt();
      workers = null;
      busy.clear();
      for (PImage img : decoded.values()) g.removeCache(img);
      decoded.clear();
      cachedBytes = 0;
      wake.notifyAll();
    }
  }

  void setSuspended(boolean value) {
    synchronized (wake) {
      if (suspended == value) return;
      suspended = value;
      wake.notifyAll();
    }
  }

  void resumeAnimation() { lastMs = -1; }

  String[] findFrames(String level) {
    final String pattern = folder() + "_\\d+\\.jpg";
    File[] list = dataFile(folder() + "/" + level).listFiles((dir, name) -> name.matches(pattern));
    if (list == null) return new String[0];
    Arrays.sort(list);
    String[] paths = new String[list.length];
    for (int i = 0; i < list.length; i++) paths[i] = list[i].getPath();
    return paths;
  }

  // ------------------------------------------------------------ decoding

  int key(int level, int i) { return level * 100000 + i; }

  // Whether a light level is visible at the current blend.
  boolean needed(int level, float w) {
    if (files[0] == files[1]) return level == 0;
    return level == 0 ? w < 0.995 : w > 0.005;
  }

  void work(int token) {
    while (true) {
      int k, revision, size;
      String path;
      synchronized (wake) {
        while (true) {
          if (!running || token != runToken) return;
          k = suspended ? -1 : pickNext();
          if (k >= 0) break;
          try { wake.wait(); } catch (InterruptedException e) { return; }
        }
        revision = decodeRevision;
        size = decodeSize;
        path = files[k / 100000][k % 100000];
      }
      PImage img = null;
      try {
        img = loadFrameImage(path, size);
      } catch (Exception e) {
        println(name() + " decode failed: " + path + " " + e);
      }
      synchronized (wake) {
        // An old resize/theme job cannot publish or clear a new job's claim.
        if (token != runToken || revision != decodeRevision) continue;
        busy.remove(k);
        if (img == null || img.width <= 0) failed.add(k);
        else if (!suspended && wanted(k)) {
          PImage previous = decoded.put(k, img);
          cachedBytes += (long) img.width * img.height * 4;
          if (previous != null) cachedBytes -= (long) previous.width * previous.height * 4;
          if (paused) requestAnimationFrame();
        }
      }
    }
  }

  // Exactly the same working set as pickNext. Eviction must protect it;
  // distance-only eviction caused the far-ahead frames to be decoded again
  // immediately while old frames behind the playback position stayed cached.
  boolean wanted(int k) {
    if (paused) return needed(k / 100000, wantLight)
      && (k % 100000 == floor(wantPos) || k % 100000 == min(floor(wantPos) + 1, n - 1));
    int offset = (k % 100000 - round(wantPos)) * wantDir;
    return needed(k / 100000, wantLight) && offset >= -2 && offset <= 8;
  }

  // The nearest frame not yet decoded or claimed, in each visible light
  // level: up to 8 ahead in the direction of motion, but only 2 behind.
  int pickNext() {
    // A theme switch or resize while paused still needs its one visible frame.
    // Decode only those layers, wake one redraw, then sleep; no prefetch loop.
    if (paused) {
      for (int i = max(0, floor(wantPos)); i <= min(floor(wantPos) + 1, n - 1); i++) {
        for (int level = 0; level < 2; level++) {
          int k = key(level, i);
          if (needed(level, wantLight) && !decoded.containsKey(k) && !failed.contains(k) && busy.add(k)) return k;
        }
      }
      return -1;
    }
    int c = round(wantPos), dir = wantDir;
    float w = wantLight;
    for (int d = 0; d <= 8; d++) {
      for (int s = 0; s < 2; s++) {
        if (s == 1 && (d == 0 || d > 2)) continue;
        int i = c + (s == 0 ? dir : -dir) * d;
        if (i < 0 || i >= n) continue;
        for (int level = 0; level < 2; level++) {
          int k = key(level, i);
          if (!needed(level, w) || decoded.containsKey(k) || failed.contains(k)) continue;
          if (busy.add(k)) return k;
        }
      }
    }
    return -1;
  }

  // Drops the frames farthest from the current position, those of a light
  // level no longer visible first. Runs on the animation thread so the GL
  // textures can be released with them.
  void evict() {
    synchronized (wake) {
      if (decoded.size() <= CACHE && cachedBytes <= CACHE_BYTES) return;
      final int c = round(wantPos);
      ArrayList<Integer> keys = new ArrayList<Integer>(decoded.keySet());
      keys.sort((a, b) -> evictionScore(b, c) - evictionScore(a, c));
      for (int k : keys) {
        if (decoded.size() <= CACHE && cachedBytes <= CACHE_BYTES) break;
        PImage img = decoded.remove(k);
        if (img != null) {
          cachedBytes -= (long) img.width * img.height * 4;
          g.removeCache(img);
        }
      }
    }
  }

  int evictionScore(int k, int c) {
    return abs(k % 100000 - c) + (wanted(k) ? 0 : 100000);
  }

  // The frame at i in a light level or, while it decodes, the nearest one
  // decoded, preferring the same level.
  PImage frame(int level, int i, float pos) {
    PImage img = decoded.get(key(level, i));
    if (img != null) return img;
    PImage best = null;
    float bestD = Float.MAX_VALUE;
    for (Map.Entry<Integer, PImage> e : decoded.entrySet()) {
      int k = e.getKey();
      float d = abs(k % 100000 - pos) + (k / 100000 == level ? 0 : 0.5);
      if (d < bestD) {
        bestD = d;
        best = e.getValue();
      }
    }
    return best;
  }

  // ------------------------------------------------------------ motion

  void step(float dt) {
    float target = 0;
    float[] u = sampler.usage;
    for (float v : u) target += v;
    target /= u.length;
    // Smooth out the 200 ms sampling steps first.
    load += (target - load) * (1 - exp(-dt / 0.35));
    // A critically damped spring towards the load, by default quicker to open
    // (~1.2 s) than to close (~2.5 s), as real petals relax slowly.
    float w = load > open ? openRate() : closeRate();
    speed += (w * w * (load - open) - 2 * w * speed) * dt;
    speed = constrain(speed, -0.8, 0.8);
    open = constrain(open + speed * dt, 0, 1);
    if (open == 0 || open == 1) speed = 0;
  }

  // The backlight follows CPU temperature, which moves slowly anyway; ease it
  // over a few seconds so the 1 s sensor steps don't show. Without a sensor
  // it stays halfway.
  void stepLight(float dt) {
    float t = sampler.tempC;
    float target = Float.isNaN(t) ? 0.5 : constrain((t - TEMP_COOL) / (TEMP_HOT - TEMP_COOL), 0, 1);
    light = light < 0 ? target : light + (target - light) * (1 - exp(-dt / 3.0));
  }

  // ------------------------------------------------------------ drawing

  void draw(boolean compact) {
    colorMode(RGB, 255);
    if (n == 0) {
      drawMissing();
      return;
    }
    int now = animationMillis();
    // Integrate occasional slow frames in small substeps. The host clock
    // excludes suspension, and resumeAnimation resets the first interval.
    float dt = lastMs < 0 ? 0 : constrain((now - lastMs) / 1000f, 0, 1);
    lastMs = now;
    int steps = ceil(dt / 0.05);
    for (int k = 0; k < steps && !paused; k++) step(dt / steps);
    if (!paused || light < 0) stepLight(dt);

    // The frames are square; fit the window's shorter side.
    float side = min(width, height);
    int size = side > 960 ? 0 : side > 640 ? 960 : side > 400 ? 640 : 400;
    // Most of the change in the render happens early, so ease the mapping.
    float pos = sequencePosition(open) * (n - 1);
    synchronized (wake) {
      if (size != decodeSize) {
        decodeSize = size;
        decodeRevision++;
        busy.clear();
        failed.clear();
        for (PImage img : decoded.values()) g.removeCache(img);
        decoded.clear();
        cachedBytes = 0;
        requestedCenter = -1;
      }
      if (abs(speed) > 0.01) wantDir = speed > 0 ? 1 : -1;
      wantPos = pos;
      wantLight = light;
      int center = round(pos), levels = (needed(0, light) ? 1 : 0) | (needed(1, light) ? 2 : 0);
      if (center != requestedCenter || wantDir != requestedDirection || levels != requestedLevels) {
        requestedCenter = center;
        requestedDirection = wantDir;
        requestedLevels = levels;
        wake.notifyAll();
      }
    }

    // Up to four layers: the two frames either side of pos, in each light
    // level, weighted by position and light.
    int i0 = constrain(floor(pos), 0, n - 1), i1 = min(i0 + 1, n - 1);
    float f = pos - i0;
    ArrayList<PImage> layers = new ArrayList<PImage>();
    FloatList weights = new FloatList();
    for (int level = 0; level < 2; level++) {
      float lw = level == 0 ? 1 - light : light;
      if (!needed(level, light)) continue;
      if (files[0] == files[1]) lw = 1;
      addLayer(layers, weights, frame(level, i0, pos), lw * (1 - f));
      addLayer(layers, weights, frame(level, i1, pos), lw * f);
    }

    if (!layers.isEmpty() && !bgKnown) {
      // The render's backdrop fades to one flat colour at the frame edge,
      // the same in both light levels.
      PImage a = layers.get(0);
      bg = lerpColor(lerpColor(a.get(4, 4), a.get(a.width - 5, 4), 0.5), a.get(a.width - 5, a.height - 5), 0.33);
      bgKnown = true;
    }
    background(bgKnown ? bg : fallbackBackground());
    if (layers.isEmpty()) return;  // first frames still decoding

    float x = (width - side) / 2, y = anchorBottom() ? height - side : (height - side) / 2;
    float t = now / 1000f;
    // A slight sway about the pivot and a slow breath keep it alive at a
    // steady load.
    float sway = (noise(t * 0.12, 7.3) - 0.5) * radians(0.8);
    float breathe = 1 + 0.004 * sin(t * TWO_PI / 6.5);
    pushMatrix();
    translate(x + side * pivotX(), y + side * pivotY());
    rotate(sway);
    scale(breathe);
    translate(-side * pivotX(), -side * pivotY());
    // Drawing each layer over the last with alpha weight / (sum of weights so
    // far) leaves each one contributing exactly its weight.
    float sum = 0;
    for (int k = 0; k < layers.size(); k++) {
      sum += weights.get(k);
      tint(255, 255 * weights.get(k) / sum);
      image(layers.get(k), 0, 0, side, side);
    }
    noTint();
    popMatrix();
    fadeEdges(x, y, side);
    evict();
  }

  // Adds an image to the blend, merging repeats (a fallback can stand in for
  // more than one frame) and skipping ones too faint to see.
  void addLayer(ArrayList<PImage> layers, FloatList weights, PImage img, float w) {
    if (img == null || w < 0.004) return;
    int k = layers.indexOf(img);
    if (k >= 0) {
      weights.add(k, w);
    } else {
      layers.add(img);
      weights.append(w);
    }
  }

  // Blends the frame's edges into the background where the window is wider
  // or taller than the frame, so no seam shows.
  void fadeEdges(float x, float y, float side) {
    float f = side * 0.06;
    int clear = color(red(bg), green(bg), blue(bg), 0);
    noStroke();
    beginShape(QUADS);
    if (x > 0.5) {
      fill(bg); vertex(x - 2, y - 2); fill(clear); vertex(x + f, y - 2);
      vertex(x + f, height); fill(bg); vertex(x - 2, height);
      fill(clear); vertex(x + side - f, y - 2); fill(bg); vertex(x + side + 2, y - 2);
      vertex(x + side + 2, height); fill(clear); vertex(x + side - f, height);
    }
    if (y > 0.5) {
      fill(bg); vertex(x - 2, y - 2); vertex(x + side + 2, y - 2);
      fill(clear); vertex(x + side + 2, y + f); vertex(x - 2, y + f);
    }
    if (y + side < height - 0.5) {
      fill(clear); vertex(x - 2, y + side - f); vertex(x + side + 2, y + side - f);
      fill(bg); vertex(x + side + 2, height); vertex(x - 2, height);
    }
    endShape();
  }

  void drawMissing() {
    background(fallbackBackground());
    float k = min(width, height) / 820f;
    fill(255, 210);
    textAlign(CENTER, CENTER);
    useFont(max(11, 22 * k));
    text(name() + " frames not found", width / 2, height / 2 - 18 * k);
    useFont(max(9, 15 * k));
    fill(255, 150);
    text("Render them with " + folder() + "/render.sh, then run ./install.sh", width / 2, height / 2 + 16 * k);
  }
}
