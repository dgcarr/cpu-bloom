// Fixed-size pool of glowing particles that drift through a noise flow field.
// Each one is drawn as a short streak from its previous position, so the
// fading trail layer builds them up into smoke-like strands.

class ParticleField {
  final int cap;
  final float[] x, y, px, py, vx, vy, life, maxLife, hue, heat;
  int next = 0;
  float t = 0;

  ParticleField(int cap) {
    this.cap = cap;
    x = new float[cap];
    y = new float[cap];
    px = new float[cap];
    py = new float[cap];
    vx = new float[cap];
    vy = new float[cap];
    life = new float[cap];
    maxLife = new float[cap];
    hue = new float[cap];
    heat = new float[cap];
  }

  // Reuses the oldest slot when the pool is full.
  void spawn(float x0, float y0, float vx0, float vy0, float h, float load) {
    int i = next;
    next = (next + 1) % cap;
    x[i] = px[i] = x0;
    y[i] = py[i] = y0;
    vx[i] = vx0;
    vy[i] = vy0;
    maxLife[i] = life[i] = random(40, 80 + 70 * load);
    hue[i] = h;
    heat[i] = load;
  }

  void update(float u) {
    t += 0.004;
    float scale = 0.0022 / u;
    for (int i = 0; i < cap; i++) {
      if (life[i] <= 0) continue;
      px[i] = x[i];
      py[i] = y[i];
      float a = noise(x[i] * scale, y[i] * scale, t) * TWO_PI * 2;
      vx[i] = (vx[i] + cos(a) * 0.09 * u) * 0.965;
      vy[i] = (vy[i] + sin(a) * 0.09 * u) * 0.965;
      x[i] += vx[i];
      y[i] += vy[i];
      life[i]--;
    }
  }

  void draw(PGraphics g, float u) {
    g.strokeWeight(max(1, 1.6 * u));
    g.beginShape(LINES);
    for (int i = 0; i < cap; i++) {
      if (life[i] <= 0) continue;
      float f = life[i] / maxLife[i];
      // Hot (busy) particles burn whiter; all of them fade out with age.
      g.stroke(hue[i], 75 - 40 * heat[i], 100, 55 * f);
      g.vertex(px[i], py[i]);
      g.vertex(x[i], y[i]);
    }
    g.endShape();
  }

  int alive() {
    int n = 0;
    for (int i = 0; i < cap; i++) if (life[i] > 0) n++;
    return n;
  }
}
