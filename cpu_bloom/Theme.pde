// A theme draws the whole window from the live stats in `sampler`. To add
// one, put a class that extends Theme in its own .pde tab in this folder and
// rebuild with ./install.sh: it is found automatically (see Themes.pde) and
// appears in the N-key cycle, the top-bar Theme menu and --theme=<id>.
// THEMES.md has the full guide and a copyable example.

abstract class Theme {
  // Stable key used in settings.properties and --theme=<id>, e.g. "bloom".
  abstract String id();

  // Label for the menu and HUD, e.g. "Bloom".
  abstract String name();

  // Called when the theme becomes active; allocate buffers here.
  void start() {}

  // Called when another theme takes over; drop large buffers here.
  void stop() {}

  // Thread-safe: called by the visibility watcher to suspend background work.
  void setSuspended(boolean suspended) {}

  // Called on the rendering thread after a hidden/paused interval.
  void resumeAnimation() {}

  // Fill the whole window. Called every frame inside pushStyle()/popStyle(),
  // so set your own colorMode, fill, stroke etc. `compact` is true in the
  // small overlay window, where labels and fine detail should be dropped.
  abstract void draw(boolean compact);

  // Optional one-line hint for the HUD, e.g. what an arc or colour means.
  String legend() { return ""; }

  // Optional theme-specific keys, as "K label" for the HUD help line.
  String keyHelp() { return ""; }

  // Keys the app doesn't use itself (H, P, N, A, S) are passed on here.
  void keyPressed(char k) {}
}

// Shared colour for display slot `slot` (HSB hue, 0..360): hues sweep teal ->
// violet -> magenta -> amber by physical core, and the second thread of a
// core is nudged so siblings read as a pair. Use it so every theme colours
// a given thread the same way.
float threadHue(int slot) {
  int core = sampler.coreRank[sampler.displayOrder[slot]];
  float h = 170 + 220 * (sampler.coreCount > 1 ? core / (float) (sampler.coreCount - 1) : 0);
  boolean sibling = slot > 0 && sampler.coreRank[sampler.displayOrder[slot - 1]] == core;
  return (h + (sibling ? 12 : 0)) % 360;
}
