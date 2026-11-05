# Writing a CPU Bloom theme

A theme is one Processing tab (`.pde` file) in `cpu_bloom/` that draws the whole window from live system stats. The app finds every theme automatically, so adding one takes three steps:

1. Create `cpu_bloom/MyTheme.pde` with a class that `extends Theme`.
2. Run `./install.sh`, which rebuilds and reinstalls the app.
3. Pick the theme with **N** in the window, from **Theme** in the top-bar menu, or with `cpu-bloom --theme=<id>`.

There is no registry to edit. `Themes.pde` finds every non-abstract `Theme` subclass by reflection.

## A complete example

This is a working theme. Save it as `cpu_bloom/BarsTheme.pde`:

```java
// Bars: one bar per CPU thread, coloured the same way as the other themes.

class BarsTheme extends Theme {
  float[] smooth;

  String id() { return "bars"; }
  String name() { return "Bars"; }

  void start() {
    smooth = new float[sampler.cpuCount];
  }

  void draw(boolean compact) {
    colorMode(HSB, 360, 100, 100, 100);
    background(232, 50, 7);
    int n = sampler.cpuCount;
    float gap = width * 0.1 / n;
    float w = (width * 0.9 - gap * (n - 1)) / n;
    float maxH = height * (compact ? 0.8 : 0.6);
    noStroke();
    for (int s = 0; s < n; s++) {
      int cpu = sampler.displayOrder[s];  // display order keeps SMT siblings together
      if (!paused) smooth[s] += (sampler.usage[cpu] - smooth[s]) * 0.15;
      float h = max(2, maxH * smooth[s]);
      float x = width * 0.05 + s * (w + gap);
      fill(threadHue(s), 70, 90);
      rect(x, height * 0.85 - h, w, h, w * 0.2);
      if (!compact) {
        fill(0, 0, 100, 80);
        useFont(14);
        textAlign(CENTER, TOP);
        text("cpu" + cpu, x + w / 2, height * 0.85 + 8);
      }
    }
  }
}
```

Inside a theme you write ordinary Processing: `width`, `height`, `rect()`, `noise()`, `millis()` and the rest all work as they do in a sketch. Each theme is an inner class of the sketch.

## The Theme API

Defined in [`cpu_bloom/Theme.pde`](cpu_bloom/Theme.pde).

| Method | Required | Purpose |
| --- | --- | --- |
| `String id()` | yes | A stable key for settings and `--theme=<id>`, such as `"bars"`. Use lowercase with no spaces. |
| `String name()` | yes | The label shown in the menu and HUD. |
| `void draw(boolean compact)` | yes | Draws the whole window, every frame. `compact` is true in the small overlay. |
| `void start()` | no | Runs when the theme becomes active. Allocate arrays and buffers here, not in the constructor. |
| `void stop()` | no | Runs when another theme takes over. Drop large buffers such as `PGraphics` here. |
| `String legend()` | no | A short line for the HUD explaining your encoding, such as `"height = load"`. |
| `String keyHelp()` | no | Your keys for the HUD help line, such as `"T trails"`. |
| `void keyPressed(char k)` | no | Receives lowercase keys the app doesn't use itself. The app keeps H, P, N, A, S and Space. |

**Avoid side effects in the constructor.** Every theme is constructed at startup, including for `--list-themes`, before `sampler` exists.

## Data you can read

Everything comes from the shared `sampler` (see `SystemSampler.pde`), which a background thread refreshes:

| Field | Meaning | Refresh |
| --- | --- | --- |
| `sampler.cpuCount` / `coreCount` | Logical threads and physical cores | once |
| `sampler.usage[cpu]` | Load of logical CPU `cpu`, 0 to 1 | 200 ms |
| `sampler.displayOrder[slot]` | The logical CPU shown in position `slot`, with SMT siblings adjacent | once |
| `sampler.coreRank[cpu]` | The physical core index of a logical CPU | once |
| `sampler.cpuModel` | For example "AMD Ryzen 5 3600X 6-Core Processor" | once |
| `sampler.memUsedGiB` / `memTotalGiB` | RAM | 500 ms |
| `sampler.loadAvg` | `"1.23 0.98 0.80"` | 1 s |
| `sampler.tempC` | CPU temperature, `Float.NaN` if no sensor | 1 s |
| `sampler.gpuSeen` | true if `nvidia-smi` works; the next row is only valid then | 2 s |
| `sampler.gpuUtil`, `gpuTempC`, `gpuMemUsedGiB`, `gpuMemTotalGiB` | GPU stats | 2 s |

Helpers from the host sketch:

- `threadHue(slot)` gives the shared HSB hue (0–360) for a display slot, so a thread is the same colour in every theme.
- `useFont(px)` sets a smooth Ubuntu Sans font rasterised at exactly `px` pixels. Use it instead of `textSize()`, which blurs.
- `paused` is true while P is toggled on. Stop advancing your animation then.

## Rules of thumb

- **Draw everything.** Start `draw()` with `background(…)`, because nothing is cleared for you.
- **Set your own style.** `draw()` runs inside `pushStyle()`/`popStyle()`, so set `colorMode`, fills and strokes yourself. The HUD is drawn on top afterwards.
- **Smooth the data.** Raw `usage` changes in steps every 200 ms. Ease towards it each frame, for example `v += (target - v) * 0.15`.
- **Scale with the window.** It can be anything from a 160 px overlay to a 6K screen. Derive sizes from `width` and `height`, or from a unit like `min(width, height) / 820f`.
- **Handle compact mode.** When `compact` is true, drop labels and fine detail, because the overlay is small and has no HUD.
- **Use the GPU for heavy work.** Prefer offscreen `PGraphics` layers and blend modes to per-pixel loops. The window is `P2D`, and the built-in themes hold 60 fps.

### 3D themes

The window renderer is `P2D`. For 3D, draw into your own `P3D` buffer and composite it:

```java
PGraphics g3;

void draw(boolean compact) {
  if (g3 == null || g3.width != width || g3.height != height) g3 = createGraphics(width, height, P3D);
  g3.beginDraw();
  g3.background(0);
  g3.lights();
  // … g3.camera(), g3.box(), g3.beginShape() …
  g3.endDraw();
  image(g3, 0, 0);
}

void stop() { g3 = null; }
```

[`RidgeTheme.pde`](cpu_bloom/RidgeTheme.pde) is a full example. It also uses `g3.screenX/Y` to place 2D labels over 3D points.

### Pre-rendered themes

For a look that needs real lighting, render it offline as a sequence of frames and scrub through them by load. [`PoppyTheme.pde`](cpu_bloom/PoppyTheme.pde) and [`OrchidTheme.pde`](cpu_bloom/OrchidTheme.pde) work this way. Both are short subclasses of [`FrameSequenceTheme`](cpu_bloom/FrameSequenceTheme.pde), which does the playback described below. A subclass names its `folder()` (frames are `data/<folder>/{dim,bright}/<folder>_NNN.jpg`) and can override:

- `sequencePosition(open)`: how openness maps to a position in the sequence, so that equal steps of load give roughly equal visible change.
- `anchorBottom()`: whether the frame sits on the window's bottom edge or in the middle.
- `pivotX()` / `pivotY()`: the point the flower sways about.
- `openRate()` / `closeRate()`: the spring rates.
- `fallbackBackground()`: the colour shown before the first frame loads.

The frames come from procedural Blender scenes, [`poppy/poppy.py`](poppy/poppy.py) and [`orchid/orchid.py`](orchid/orchid.py), in which one parameter (openness, 0 to 1) drives the whole pose. Helpers that don't depend on the scene live in [`blender/common.py`](blender/common.py): render setup, relighting by light group, lights, and building meshes and hair.

- **Rendering:** `poppy/render.sh` (or `orchid/render.sh`) renders 121 evenly spaced steps with Cycles into `cpu_bloom/data/poppy/` (or `data/orchid/`). Files in `data/` ship inside the exported app. A full Poppy run takes about 2.3 hours on a GTX 1660 SUPER. Keep other GPU apps closed while it runs, and resume a stopped run with `--start N`.
- **Relighting:** the poppy's backlight follows CPU temperature. Light adds up linearly, so one render can be relit afterwards: the backlights are one Cycles light group and the fill, world and backdrop another. The compositor denoises each group, then saves every frame twice, as `key × 0.5 + ambient` into `data/poppy/dim/` and `key × 1.6 + ambient` into `data/poppy/bright/`. The theme blends the two, from dim at 45 °C to bright at 90 °C. `poppy/render.sh --preview 0,0.5,1` renders a few quick stills into `poppy/preview/` for look development. The orchid works the same way: its front key light and fill are the ambient group, so the flower always reads clearly, and its back and rim lights are the key group, so the thin tepals glow as the CPU warms (`× 0.4` dim, `× 1.3` bright).
- **Moving between frames:** the theme eases its openness towards the load with a spring, draws the two nearest frames, and crossfades between them. That makes the motion smooth in both directions at any speed. With two light levels it blends four images; drawing each over the last with alpha `weight / (sum of weights so far)` gives every image exactly its weight.
- **Memory:** decoding all the frames at once would take about 1.6 GB. Only the active theme holds any. Worker threads instead decode them on demand into a cache of 24 frames, always starting with the one nearest the current position, and skip a light level while it is fully blended out. Frames are decoded at a smaller size for small windows, and the GL texture is released when a frame is evicted (`g.removeCache(img)`). The installed launcher caps the Java heap at 320 MB (`-Xmx320m`, set by `install.sh`), so a theme has to fit in that.

## Testing a theme

From the repo, without installing:

```bash
/opt/processing/bin/Processing cli --force --sketch="$PWD/cpu_bloom" --output="$PWD/out" --variant=linux-x86_64 --export
out/cpu_bloom --list-themes        # your id and name should be listed
out/cpu_bloom --theme=bars         # full window
out/cpu_bloom --theme=bars --overlay
CPU_BLOOM_SNAPSHOT=/tmp/bars.png out/cpu_bloom --theme=bars   # save a frame after 8 s, print fps, quit
```

These environment variables make motion testable without loading or heating the CPU:

| Variable | Effect |
| --- | --- |
| `CPU_BLOOM_FAKE_LOAD` | Replaces every thread's load. Either a constant (`0.5`), or `seconds:load` points from startup, interpolated and held after the last one (`0:0,2:1,8:1,10:0`). |
| `CPU_BLOOM_FAKE_TEMP` | Replaces the CPU temperature in °C, in the same format (`40`, or `0:40,10:90`). |
| `CPU_BLOOM_RECORD=<dir>` | Saves a JPEG every 100 ms for 15 s into `<dir>`, named by milliseconds since start, then quits. |

```bash
CPU_BLOOM_FAKE_LOAD=1 CPU_BLOOM_SNAPSHOT=/tmp/full.png out/cpu_bloom --theme=poppy
CPU_BLOOM_FAKE_LOAD=1 CPU_BLOOM_FAKE_TEMP=90 CPU_BLOOM_SNAPSHOT=/tmp/hot.png out/cpu_bloom --theme=poppy
mkdir -p /tmp/rec && CPU_BLOOM_FAKE_LOAD=0:0,2:1,8:1,10:0 CPU_BLOOM_RECORD=/tmp/rec out/cpu_bloom --theme=poppy
```

When it looks right, run `./install.sh` so the installed app and the top-bar menu pick it up. If the indicator is already running, the installer restarts it.

### Suspension

The host suspends rendering when a window is minimized and while paused, without
changing the visible frame-rate target. Themes with background workers can
implement `setSuspended(boolean)`; this callback is invoked from the visibility
watcher and must be thread-safe. An in-flight job may finish, but workers should
then sleep until needed. `resumeAnimation()` runs on the rendering thread before
the first restored frame and can reset time-integration state.

Use `animationMillis()` for animation phase and history timing. This clock excludes
suspended time, preventing a long hidden interval from causing a phase jump.
Use ordinary `millis()` only for real-time UI deadlines. `stop()` must release
workers and graphics buffers when switching themes or closing the application.
