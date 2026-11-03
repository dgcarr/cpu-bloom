import java.util.*;
import java.nio.file.*;
import processing.core.*;

// Run through scripts/test-resources.sh against the exported build.
public class ResourceRegression {
  static void check(boolean pass, String message) {
    if (!pass) throw new AssertionError(message);
  }

  static class CountingSketch extends cpu_bloom {
    int decodes;
    public PImage loadImage(String filename) { decodes++; return super.loadImage(filename); }
  }

  static class BlockingSketch extends cpu_bloom {
    final java.util.concurrent.CountDownLatch entered = new java.util.concurrent.CountDownLatch(1);
    final java.util.concurrent.CountDownLatch release = new java.util.concurrent.CountDownLatch(1);
    public PImage loadPoppyFrame(String path, int size) {
      entered.countDown();
      try { release.await(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
      return new PImage(4, 4, PConstants.RGB);
    }
  }

  static void checkWorkerSuspension() throws Exception {
    BlockingSketch app = new BlockingSketch(); app.g = new PGraphics();
    cpu_bloom.PoppyTheme poppy = app.new PoppyTheme();
    poppy.files = new String[][] {{"unused"}, {"unused"}};
    poppy.n = 1; poppy.wantLight = 0; poppy.running = true; poppy.runToken = 1;
    Thread worker = new Thread(() -> poppy.work(1)); worker.setDaemon(true); worker.start();
    check(app.entered.await(2, java.util.concurrent.TimeUnit.SECONDS), "worker did not decode");
    poppy.setSuspended(true); app.release.countDown();
    long deadline = System.nanoTime() + 2_000_000_000L;
    while ((!poppy.busy.isEmpty() || worker.getState() != Thread.State.WAITING) && System.nanoTime() < deadline) Thread.sleep(10);
    check(worker.getState() == Thread.State.WAITING, "hidden decoder did not sleep");
    check(poppy.decoded.isEmpty(), "hidden job published stale data");
    poppy.setSuspended(false);
    deadline = System.nanoTime() + 2_000_000_000L;
    while (poppy.decoded.isEmpty() && System.nanoTime() < deadline) Thread.sleep(10);
    check(poppy.decoded.size() == 1, "decoder did not resume");
    poppy.stop(); worker.join(2000);
    check(!worker.isAlive(), "decoder survived stop");
  }

  public static void main(String[] args) throws Exception {
    checkWorkerSuspension();
    CountingSketch app = new CountingSketch();
    java.lang.reflect.Field sketchPath = PApplet.class.getDeclaredField("sketchPath");
    sketchPath.setAccessible(true); sketchPath.set(app, System.getProperty("user.dir"));
    app.g = new PGraphics();
    cpu_bloom.PoppyTheme poppy = app.new PoppyTheme();
    poppy.files = new String[][] {new String[121], new String[121]};
    poppy.n = 121;
    poppy.wantPos = 50;
    poppy.wantDir = 1;
    poppy.wantLight = 0.5f;
    for (int level = 0; level < 2; level++) {
      for (int frame = 42; frame <= 58; frame++) {
        poppy.decoded.put(poppy.key(level, frame), new PImage(4, 4, PConstants.RGB));
        poppy.cachedBytes += 64;
      }
    }
    poppy.evict();
    check(poppy.decoded.size() == 24, "cache bound");
    for (int level = 0; level < 2; level++) for (int frame = 48; frame <= 58; frame++)
      check(poppy.decoded.containsKey(poppy.key(level, frame)), "prefetch frame evicted");
    check(poppy.pickNext() == -1, "eviction must not trigger re-decoding of wanted frames");
    poppy.wantDir = -1;
    check(poppy.wanted(poppy.key(0, 42)), "reverse prefetch");
    check(!poppy.wanted(poppy.key(0, 58)), "old direction no longer wanted");
    poppy.wantLight = 0;
    check(!poppy.wanted(poppy.key(1, 50)), "unused light level");
    app.paused = true;
    poppy.decoded.clear(); poppy.busy.clear();
    poppy.wantPos = 50.25f; poppy.wantLight = 0.5f;
    Set<Integer> pausedKeys = new HashSet<>();
    int selected;
    while ((selected = poppy.pickNext()) >= 0) pausedKeys.add(selected);
    check(pausedKeys.equals(new HashSet<>(Arrays.asList(50, 51, 100050, 100051))), "pause should decode only visible layers");
    app.paused = false;
    poppy.stop();
    check(poppy.decoded.isEmpty() && poppy.cachedBytes == 0, "stop releases cache");

    // Cold and warm cache pixels must equal the original Processing resize,
    // at every supported size. A corrupt cache must transparently recover.
    for (int size : new int[] {400, 640, 960}) {
      PImage original = app.loadImage(args[0]);
      original.resize(size, size); original.loadPixels();
      java.io.File cache = app.poppyCacheFile(new java.io.File(args[0]), size);
      Files.deleteIfExists(cache.toPath());
      PImage cold = app.loadPoppyFrame(args[0], size);
      int coldDecodes = app.decodes;
      PImage warm = app.loadPoppyFrame(args[0], size);
      check(app.decodes == coldDecodes, "warm cache decoded original again");
      cold.loadPixels(); warm.loadPixels();
      check(Arrays.equals(original.pixels, cold.pixels), "cold pixels changed at " + size);
      check(Arrays.equals(original.pixels, warm.pixels), "warm pixels changed at " + size);
      Files.write(cache.toPath(), new byte[] {1, 2, 3});
      PImage recovered = app.loadPoppyFrame(args[0], size); recovered.loadPixels();
      check(Arrays.equals(original.pixels, recovered.pixels), "corrupt cache recovery");
    }
    System.out.println("PASS: worker suspension/resume/stop, prefetch eviction, reversal, lighting, cleanup, exact cache pixels, corruption recovery");
  }
}
