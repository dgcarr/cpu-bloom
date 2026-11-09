// Ridge: a 3D landscape with one mountain ridge per CPU thread. The front
// edge is live; every 100 ms it is frozen into a new row that scrolls back
// into the fog, so the terrain behind you is the last ~15 s of history. A
// translucent sea rises with RAM use. Drawn into its own P3D buffer, since
// the host window is P2D.

class RidgeTheme extends Theme {
  final float WORLD_W = 1600, ROW_DZ = 13, MAX_H = 340;
  final float MARGIN = 1.5;          // empty hills either side, in thread widths
  final int COLS_PER_THREAD = 6;
  final int ROW_MS = 100;

  PGraphics g3;
  int n, cols, rows;
  float[] colX, colHue;
  float[][] weight;                  // [col][slot] Gaussian ridge profile
  float[] liveH, liveR, labelX, labelY;
  float[] smooth;                    // smoothed load per slot
  float[][] heights, ridges;         // ring buffers [row][col]
  int head = 0, serial = 0, lastRowMs = 0;
  float ramFrac = 0;

  String id() { return "ridge"; }
  String name() { return "Ridge"; }

  String legend() { return "height = thread load · sea level = RAM"; }

  void start() {
    n = sampler.cpuCount;
    cols = round((n + 2 * MARGIN) * COLS_PER_THREAD) + 1;
    colX = new float[cols];
    colHue = new float[cols];
    weight = new float[cols][n];
    for (int c = 0; c < cols; c++) {
      float u = map(c, 0, cols - 1, -MARGIN, n + MARGIN);   // position in thread widths
      colX[c] = map(c, 0, cols - 1, -WORLD_W / 2, WORLD_W / 2);
      colHue[c] = threadHue(constrain(floor(u), 0, n - 1));
      for (int s = 0; s < n; s++) {
        float d = u - (s + 0.5);
        weight[c][s] = exp(-d * d / (2 * 0.32 * 0.32));
      }
    }
    if (smooth == null || smooth.length != n) smooth = new float[n];
    liveH = new float[cols]; liveR = new float[cols];
    labelX = new float[n]; labelY = new float[n];
    rows = 0;  // buffers are (re)sized on the first draw, when compact is known
  }

  void stop() {
    if (g3 != null) g3.dispose();
    g3 = null;
  }

  void allocRows(int count) {
    rows = count;
    heights = new float[rows][cols];
    ridges = new float[rows][cols];
    head = 0;
  }

  // Heights for one row from the current smoothed loads.
  void fillRow(float[] h, float[] r, int rowSerial) {
    for (int c = 0; c < cols; c++) {
      float v = 0;
      for (int s = 0; s < n; s++) v += smooth[s] * weight[c][s];
      v = min(v, 1.15);
      float base = noise(c * 0.11, rowSerial * 0.03) * 0.14;
      float rough = (noise(c * 0.5 + 40, rowSerial * 0.12) - 0.5) * 0.12 * v;
      r[c] = v;
      h[c] = MAX_H * (v + base + rough);
    }
  }

  void draw(boolean compact) {
    int wantRows = compact ? 80 : 150;
    if (rows != wantRows) allocRows(wantRows);
    if (g3 == null || g3.width != width || g3.height != height) {
      if (g3 != null) g3.dispose();
      g3 = createGraphics(width, height, P3D);
      g3.smooth(4);
    }

    if (!paused) {
      for (int s = 0; s < n; s++) smooth[s] += (sampler.usage[sampler.displayOrder[s]] - smooth[s]) * 0.15;
      float ram = sampler.memTotalGiB > 0 ? sampler.memUsedGiB / sampler.memTotalGiB : 0;
      ramFrac += (ram - ramFrac) * 0.05;
      if (animationMillis() - lastRowMs >= ROW_MS) {
        lastRowMs = animationMillis();
        head = (head + rows - 1) % rows;          // newest row goes to the front
        fillRow(heights[head], ridges[head], serial++);
      }
    }
    // The live front row, recomputed every frame so the edge never lags.
    fillRow(liveH, liveR, serial);
    float scroll = paused ? 0 : constrain((animationMillis() - lastRowMs) / (float) ROW_MS, 0, 1);

    g3.beginDraw();
    g3.colorMode(HSB, 360, 100, 100, 100);
    g3.background(232, 50, 7);
    g3.perspective(PI / 3.3, width / (float) height, 1, 8000);
    // The overlay has fewer rows, so space them out to keep the same depth feel.
    float dz = compact ? ROW_DZ * 1.8 : ROW_DZ;
    float depth = rows * dz;
    // Close enough to fill the window but far enough back that the whole live
    // edge fits across it, looking down at the terrain. A slow sideways drift
    // keeps the 3D shape readable even when nothing changes.
    float aspect = width / (float) height;
    float back = (WORLD_W * 0.5) / tan(PI / 3.3 / 2) / aspect;
    float drift = sin(animationMillis() * 0.00006) * WORLD_W * 0.08;
    if (compact) g3.camera(drift, -MAX_H * 4.5, back, 0, 0, -depth * 0.62, 0, 1, 0);
    else g3.camera(drift, -MAX_H * 3.4, back * 0.92, 0, 0, -depth * 0.55, 0, 1, 0);

    // Terrain: one triangle strip between each pair of rows, front to back.
    g3.noStroke();
    for (int k = -1; k < rows - 1; k++) {
      float[] hA = k < 0 ? liveH : heights[(head + k) % rows];
      float[] rA = k < 0 ? liveR : ridges[(head + k) % rows];
      float[] hB = heights[(head + k + 1) % rows];
      float[] rB = ridges[(head + k + 1) % rows];
      float zA = k < 0 ? 0 : -(k + scroll) * dz;
      float zB = -(k + 1 + scroll) * dz;
      float fogA = fog(k < 0 ? 0 : k + scroll), fogB = fog(k + 1 + scroll);
      g3.beginShape(TRIANGLE_STRIP);
      for (int c = 0; c < cols; c++) {
        vertexColor(hA, rA, c, fogA);
        g3.vertex(colX[c], -hA[c], zA);
        vertexColor(hB, rB, c, fogB);
        g3.vertex(colX[c], -hB[c], zB);
      }
      g3.endShape();
    }

    // Contour-like lines every few rows, and a bright live edge.
    g3.noFill();
    g3.strokeWeight(compact ? 1.2 : 1.5);
    for (int k = -1; k < rows; k += 6) {
      float[] h = k < 0 ? liveH : heights[(head + k) % rows];
      float[] r = k < 0 ? liveR : ridges[(head + k) % rows];
      float z = k < 0 ? 0 : -(k + scroll) * dz;
      float f = fog(max(0, k + scroll));
      g3.beginShape();
      for (int c = 0; c < cols; c++) {
        float a = (k < 0 ? 95 : 45) * (1 - f);
        g3.stroke(colHue[c], 40 - 25 * r[c], 70 + 30 * r[c], a);
        g3.vertex(colX[c], -h[c] - 0.8, z + 0.5);
      }
      g3.endShape();
    }

    // RAM sea: a translucent plane whose level follows memory use.
    float sea = MAX_H * 0.12 * ramFrac;
    g3.noStroke();
    g3.fill(210, 70, 55, 22);
    g3.beginShape(QUADS);
    g3.vertex(-WORLD_W / 2, -sea, 0);
    g3.vertex(WORLD_W / 2, -sea, 0);
    g3.vertex(WORLD_W / 2, -sea, -depth);
    g3.vertex(-WORLD_W / 2, -sea, -depth);
    g3.endShape();

    // Where each thread's front peak lands on screen, for the labels.
    float[] lx = labelX, ly = labelY;
    if (!compact) {
      for (int s = 0; s < n; s++) {
        int c = round(map(s + 0.5, -MARGIN, n + MARGIN, 0, cols - 1));
        lx[s] = g3.screenX(colX[c], -liveH[c] - 26, 0);
        ly[s] = g3.screenY(colX[c], -liveH[c] - 26, 0);
      }
    }
    g3.endDraw();
    image(g3, 0, 0);

    if (!compact) drawLabels(lx, ly);
  }

  // 0 at the front, 1 at the back; eased so the near terrain stays crisp.
  float fog(float rowAge) {
    return pow(constrain(rowAge / rows, 0, 1), 1.3);
  }

  void vertexColor(float[] h, float[] r, int c, float fogAmount) {
    // Cheap relief shading from the left/right slope.
    float slope = (h[min(c + 1, cols - 1)] - h[max(c - 1, 0)]) / MAX_H;
    float shade = constrain(1 - slope * 1.6, 0.55, 1.25);
    float load = r[c];
    float sat = lerp(75, 35, load);
    float bri = constrain((22 + 70 * load) * shade, 0, 100);
    // Fog: fade towards the background colour with distance.
    g3.fill(lerp(colHue[c], 232, fogAmount), lerp(sat, 50, fogAmount), lerp(bri, 7, fogAmount));
  }

  void drawLabels(float[] lx, float[] ly) {
    float u = min(width, height) / 820f;
    colorMode(HSB, 360, 100, 100, 100);
    useFont(13 * u);
    textAlign(CENTER, CENTER);
    rectMode(CENTER);
    noStroke();
    for (int s = 0; s < n; s++) {
      String label = "cpu" + sampler.displayOrder[s] + " " + round(smooth[s] * 100) + "%";
      fill(232, 50, 7, 75);
      rect(lx[s], ly[s], textWidth(label) + 12 * u, 20 * u, 10 * u);
      fill(threadHue(s), 30, 95, 92);
      text(label, lx[s], ly[s] - 1 * u);
    }
    rectMode(CORNER);
  }
}
