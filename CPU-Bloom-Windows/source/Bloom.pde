// The flower: one petal per logical CPU with SMT siblings side by side, a
// polar history ring outside the petals, and RAM/GPU arcs around a core orb
// coloured by CPU temperature. All radii are in units of `u` (1 unit = 1px
// when the shorter window side is 820px).

class Bloom {
  final float BASE_R = 100, MIN_LEN = 16, MAX_LEN = 180;
  final float RING_IN = 312, RING_OUT = 372, LABEL_R = 390;
  final float RAM_R = 74, GPU_R = 84;
  final int HISTORY = 90, HISTORY_MS = 500;  // 45 s of history

  final SystemSampler s;
  final int n;
  final float[] slotHue;
  final float[] load;        // smoothed, per slot
  final float[][] history;   // [slot][HISTORY] ring buffer
  float[] backdropR;
  float[][] backdropLines;
  float backdropCx = -1, backdropCy = -1, backdropU = -1;
  float[][] historyX, historyY, innerX, innerY;
  int cachedHistoryHead = -1;
  float cachedCx = -1, cachedCy = -1, cachedU = -1;
  final float[] petalProfile = new float[41];
  int historyHead = 0;
  int lastHistoryMs = 0;
  float avgLoad = 0, ramFrac = 0, gpuFrac = 0;
  boolean compact = false;   // overlay mode: no per-thread labels, larger centre text

  Bloom(SystemSampler s) {
    this.s = s;
    n = s.cpuCount;
    slotHue = new float[n];
    load = new float[n];
    history = new float[n][HISTORY];
    for (int i = 0; i < n; i++) slotHue[i] = threadHue(i);
    for (int k = 0; k <= 40; k++) {
      float t = k <= 20 ? k / 20f : (40 - k) / 20f;
      petalProfile[k] = pow(max(0, sin(PI * t)), 0.75) * (k <= 20 ? 1 : -1);
    }
  }

  float angle(int slot) {
    return -HALF_PI + TWO_PI * slot / n;
  }

  float petalLength(int slot) {
    return MIN_LEN + MAX_LEN * load[slot];
  }

  void update(float[] usage) {
    float sum = 0;
    for (int i = 0; i < n; i++) {
      load[i] += (usage[s.displayOrder[i]] - load[i]) * 0.12;
      sum += load[i];
    }
    avgLoad = sum / n;
    float ram = s.memTotalGiB > 0 ? s.memUsedGiB / s.memTotalGiB : 0;
    ramFrac += (ram - ramFrac) * 0.1;
    gpuFrac += (s.gpuUtil / 100f - gpuFrac) * 0.1;

    if (animationMillis() - lastHistoryMs >= HISTORY_MS) {
      lastHistoryMs = animationMillis();
      for (int i = 0; i < n; i++) history[i][historyHead] = load[i];
      historyHead = (historyHead + 1) % HISTORY;
    }
  }

  // Busy petals shed particles from their tips; idle ones only spark now and then.
  void emit(ParticleField pf, float cx, float cy, float u) {
    for (int i = 0; i < n; i++) {
      float l = load[i];
      float rate = l * l * 4 + l;
      int count = (int) rate + (random(1) < rate - (int) rate ? 1 : 0);
      float a = angle(i);
      float r = (BASE_R + petalLength(i)) * u;
      for (int k = 0; k < count; k++) {
        float aj = a + random(-0.12, 0.12);
        float rr = r * random(0.85, 1.0);
        float speed = (0.5 + l * 1.4) * u * random(0.7, 1.3);
        pf.spawn(cx + cos(aj) * rr, cy + sin(aj) * rr, cos(aj) * speed, sin(aj) * speed, slotHue[i], l);
      }
    }
  }

  // Faint guide rings at 25/50/75/100% petal length and a spoke per thread.
  void drawBackdrop(float cx, float cy, float u) {
    if (backdropR == null || cx != backdropCx || cy != backdropCy || u != backdropU) {
      backdropR = new float[4]; backdropLines = new float[n][4];
      for (int k = 1; k <= 4; k++) backdropR[k - 1] = (BASE_R + MIN_LEN + MAX_LEN * k / 4f) * u;
      for (int i = 0; i < n; i++) {
        float a = angle(i);
        backdropLines[i] = new float[] {cx + cos(a) * BASE_R * u, cy + sin(a) * BASE_R * u,
          cx + cos(a) * RING_OUT * u, cy + sin(a) * RING_OUT * u};
      }
      backdropCx = cx; backdropCy = cy; backdropU = u;
    }
    noFill(); strokeWeight(1);
    for (int k = 1; k <= 4; k++) {
      stroke(225, 30, 60, k == 4 ? 18 : 9);
      ellipse(cx, cy, 2 * backdropR[k - 1], 2 * backdropR[k - 1]);
    }
    for (int i = 0; i < n; i++) {
      stroke(slotHue[i], 30, 60, 8);
      float[] v = backdropLines[i]; line(v[0], v[1], v[2], v[3]);
    }
  }

  void draw(float cx, float cy, float u) {
    drawHistory(cx, cy, u);
    drawCorePairs(cx, cy, u);
    drawPetals(cx, cy, u);
    drawCore(cx, cy, u);
    if (!compact) drawLabels(cx, cy, u);
  }

  // Each thread's last 45 s as a polar area sparkline, oldest on the left.
  void drawHistory(float cx, float cy, float u) {
    if (historyX == null || cachedHistoryHead != historyHead || cachedCx != cx || cachedCy != cy || cachedU != u)
      cacheHistory(cx, cy, u);
    float span = TWO_PI / n * 0.82;
    float rin = RING_IN * u, rout = RING_OUT * u;
    for (int i = 0; i < n; i++) {
      float a0 = angle(i) - span / 2;
      float h = slotHue[i];

      noStroke();
      fill(h, 70, 85, 30);
      beginShape();
      for (int j = 0; j < HISTORY; j++) {
        vertex(historyX[i][j], historyY[i][j]);
      }
      for (int j = HISTORY - 1; j >= 0; j--) {
        vertex(innerX[i][j], innerY[i][j]);
      }
      endShape(CLOSE);

      noFill();
      stroke(h, 55, 100, 90);
      strokeWeight(1.4 * u);
      beginShape();
      for (int j = 0; j < HISTORY; j++) {
        vertex(historyX[i][j], historyY[i][j]);
      }
      endShape();

      strokeWeight(1);
      stroke(h, 30, 70, 35);
      arc(cx, cy, 2 * rin, 2 * rin, a0, a0 + span);
      stroke(h, 30, 70, 12);
      arc(cx, cy, 2 * rout, 2 * rout, a0, a0 + span);
    }
  }

  void cacheHistory(float cx, float cy, float u) {
    // Cache coordinates, keeping the original drawing path and rasterization.
    if (historyX == null) {
      historyX = new float[n][HISTORY]; historyY = new float[n][HISTORY];
      innerX = new float[n][HISTORY]; innerY = new float[n][HISTORY];
    }
    float span = TWO_PI / n * 0.82;
    float rin = RING_IN * u, rout = RING_OUT * u;
    for (int i = 0; i < n; i++) {
      float a0 = angle(i) - span / 2;
      for (int j = 0; j < HISTORY; j++) {
        float a = a0 + span * j / (HISTORY - 1);
        float radius = lerp(rin, rout, history[i][(historyHead + j) % HISTORY]);
        historyX[i][j] = cx + cos(a) * radius; historyY[i][j] = cy + sin(a) * radius;
        innerX[i][j] = cx + cos(a) * rin; innerY[i][j] = cy + sin(a) * rin;
      }
    }
    cachedHistoryHead = historyHead;
    cachedCx = cx; cachedCy = cy; cachedU = u;
  }

  // A short arc under each physical core ties its SMT threads together.
  void drawCorePairs(float cx, float cy, float u) {
    float step = TWO_PI / n;
    float r = (BASE_R - 9) * u;
    noFill();
    strokeWeight(2.5 * u);
    strokeCap(ROUND);
    int start = 0;
    for (int i = 1; i <= n; i++) {
      boolean sameCore = i < n && s.coreRank[s.displayOrder[i]] == s.coreRank[s.displayOrder[start]];
      if (sameCore) continue;
      stroke(slotHue[start], 45, 75, 55);
      arc(cx, cy, 2 * r, 2 * r, angle(start) - step * 0.35, angle(i - 1) + step * 0.35);
      start = i;
    }
  }

  void drawPetals(float cx, float cy, float u) {
    noStroke();
    blendMode(ADD);
    for (int i = 0; i < n; i++) {
      float len = petalLength(i) * u;
      petal(cx, cy, angle(i), BASE_R * u, len * 1.08, petalWidth(i, u) * 1.5, slotHue[i], load[i], 0.12);
    }
    blendMode(BLEND);
    for (int i = 0; i < n; i++) {
      petal(cx, cy, angle(i), BASE_R * u, petalLength(i) * u, petalWidth(i, u), slotHue[i], load[i], 1);
    }
    // A bright bead at the tip of every petal makes the current value easy to read.
    blendMode(ADD);
    for (int i = 0; i < n; i++) {
      float a = angle(i), r = (BASE_R + petalLength(i)) * u;
      float d = (5 + 7 * load[i]) * u;
      fill(slotHue[i], 35, 100, 35 + 50 * load[i]);
      ellipse(cx + cos(a) * r, cy + sin(a) * r, d, d);
    }
    blendMode(BLEND);
  }

  float petalWidth(int slot, float u) {
    float len = petalLength(slot);
    return min((BASE_R + len * 0.5) * sin(PI / n) * 0.8, len * 0.45) * u;
  }

  // Leaf-shaped fan, dark at the base and bright towards the tip.
  void petal(float cx, float cy, float a, float r0, float len, float halfW,
             float h, float l, float alphaScale) {
    float dx = cos(a), dy = sin(a);
    float px = -dy, py = dx;
    int steps = 20;
    beginShape(TRIANGLE_FAN);
    fill(h, 85, 30 + 20 * l, 90 * alphaScale);
    vertex(cx + dx * r0, cy + dy * r0);
    for (int k = 0; k <= steps * 2; k++) {
      boolean left = k <= steps;
      float t = left ? k / (float) steps : (2 * steps - k) / (float) steps;
      float w = halfW * petalProfile[k];
      float r = r0 + len * t;
      fill(h, lerp(85, 40, t * l), lerp(40, 100, t), 95 * alphaScale);
      vertex(cx + dx * r + px * w, cy + dy * r + py * w);
    }
    endShape();
  }

  void drawCore(float cx, float cy, float u) {
    // Cool cyan when the CPU is cold, through amber, to red near 90 C.
    float h = Float.isNaN(s.tempC) ? 200 : map(constrain(s.tempC, 35, 90), 35, 90, 195, 0);

    noFill();
    strokeCap(ROUND);
    strokeWeight(5 * u);
    stroke(0, 0, 100, 8);
    ellipse(cx, cy, 2 * RAM_R * u, 2 * RAM_R * u);
    stroke(210, 20, 100, 85);
    arc(cx, cy, 2 * RAM_R * u, 2 * RAM_R * u, -HALF_PI, -HALF_PI + TWO_PI * max(ramFrac, 0.001));
    if (s.gpuSeen) {
      stroke(0, 0, 100, 8);
      ellipse(cx, cy, 2 * GPU_R * u, 2 * GPU_R * u);
      stroke(95, 70, 95, 85);
      arc(cx, cy, 2 * GPU_R * u, 2 * GPU_R * u, -HALF_PI, -HALF_PI + TWO_PI * max(gpuFrac, 0.001));
    }

    float pulse = sin(frameCount * 0.05 * (1 + avgLoad * 3)) * 1.5;
    float r = (40 + 18 * avgLoad + pulse) * u;
    noStroke();
    fill(h, 70, 16);
    ellipse(cx, cy, 2 * r, 2 * r);
    blendMode(ADD);
    for (int k = 0; k < 12; k++) {
      float rr = r * (1 - k * 0.07);
      fill(h, 75 - k * 4, 100, 5);
      ellipse(cx, cy, 2 * rr, 2 * rr);
    }
    for (int k = 1; k <= 8; k++) {
      float rr = r * (1 + k * 0.1);
      fill(h, 80, 80, 3);
      ellipse(cx, cy, 2 * rr, 2 * rr);
    }
    blendMode(BLEND);

    fill(0, 0, 100);
    textAlign(CENTER, CENTER);
    float ts = compact ? 1.6 : 1;
    useFont(32 * u * ts);
    text(round(avgLoad * 100) + "%", cx, cy - 6 * u * ts);
    useFont(14 * u * ts);
    fill(0, 0, 100, 75);
    text(Float.isNaN(s.tempC) ? "CPU" : nf(s.tempC, 0, 1) + "°C", cx, cy + 20 * u * ts);
  }

  void drawLabels(float cx, float cy, float u) {
    useFont(14 * u);
    textAlign(CENTER, CENTER);
    rectMode(CENTER);
    noStroke();
    for (int i = 0; i < n; i++) {
      float a = angle(i), r = LABEL_R * u;
      float x = cx + cos(a) * r, y = cy + sin(a) * r;
      String label = "cpu" + s.displayOrder[i] + "  " + round(load[i] * 100) + "%";
      // Dark pill keeps the label readable on top of bright particle trails.
      fill(232, 50, 7, 80);
      rect(x, y, textWidth(label) + 16 * u, 22 * u, 11 * u);
      fill(slotHue[i], 30, 95, 90);
      text(label, x, y - 1 * u);
    }
    rectMode(CORNER);
  }
}
