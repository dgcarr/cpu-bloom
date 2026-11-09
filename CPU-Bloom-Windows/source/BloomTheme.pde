// The original CPU Bloom look: one petal per thread, particles shed into a
// noise flow field, a polar history ring, and a core coloured by temperature.
// The drawing lives in Bloom.pde and ParticleField.pde; this tab wires them
// into the Theme API and owns the particle trail layer.

class BloomTheme extends Theme {
  Bloom bloom;
  ParticleField particles;
  PGraphics trails;
  boolean showTrails = true;

  String id() { return "bloom"; }
  String name() { return "Bloom"; }

  void start() {
    if (bloom == null) bloom = new Bloom(sampler);
    if (particles == null) particles = new ParticleField(6000);
  }

  void stop() {
    if (trails != null) trails.dispose();
    trails = null;  // the full-window layer is the only large allocation
  }

  void draw(boolean compact) {
    float cx = width / 2f, cy = height / 2f;
    float u = min(width, height) / 820f;
    colorMode(HSB, 360, 100, 100, 100);

    bloom.compact = compact;
    if (!paused) bloom.update(sampler.usage);
    updateTrails(cx, cy, u);

    background(232, 50, 7);
    bloom.drawBackdrop(cx, cy, u);
    blendMode(ADD);
    image(trails, 0, 0);
    blendMode(BLEND);
    bloom.draw(cx, cy, u);
  }

  // Particles live on their own layer that fades a little each frame, which
  // turns their short streaks into trails without smearing the crisp UI.
  void updateTrails(float cx, float cy, float u) {
    if (trails == null || trails.width != width || trails.height != height) {
      if (trails != null) trails.dispose();
      trails = createGraphics(width, height, P2D);
      trails.beginDraw();
      trails.background(0);
      trails.endDraw();
    }
    if (paused) return;
    trails.beginDraw();
    trails.colorMode(HSB, 360, 100, 100, 100);
    trails.noStroke();
    if (showTrails) {
      trails.blendMode(SUBTRACT);
      trails.fill(0, 0, 4);
      trails.rect(0, 0, width, height);
    } else {
      trails.background(0);
    }
    trails.blendMode(ADD);
    if (!paused) {
      bloom.emit(particles, cx, cy, u);
      particles.update(u);
    }
    particles.draw(trails, u);
    trails.endDraw();
  }

  String legend() {
    return "inner arc RAM" + (sampler.gpuSeen ? " · outer arc GPU" : "");
  }

  String keyHelp() { return "T trails"; }

  void keyPressed(char k) {
    if (k == 't') showTrails = !showTrails;
  }
}
