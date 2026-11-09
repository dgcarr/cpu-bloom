// Reads CPU, memory, temperature and GPU stats on a background thread.
// Linux uses /proc and /sys; Windows uses OSHI for CPU topology/load and RAM.
// GPU numbers come from nvidia-smi when it is installed.

class SystemSampler implements Runnable {
  final int cpuCount;
  final int coreCount;
  final int[] displayOrder;  // slot -> logical cpu, SMT siblings adjacent
  final int[] coreRank;      // logical cpu -> physical core index
  final String cpuModel;

  volatile float[] usage;    // logical cpu -> 0..1
  volatile float memUsedGiB, memTotalGiB;
  volatile String loadAvg = "";
  volatile float tempC = Float.NaN;
  volatile boolean gpuSeen = false;
  volatile float gpuUtil, gpuTempC, gpuMemUsedGiB, gpuMemTotalGiB;

  private final long[] prevIdle, prevTotal;
  private final String tempPath;
  private volatile boolean running = true, gpuActive = true;
  private volatile Process gpuProcess;
  private volatile long gpuOutputAt;
  private volatile int gpuEpoch = 0;
  private final Object gpuWake = new Object();
  private Thread gpuThread;
  private final Object sampleWake = new Object();
  private volatile boolean background = false;
  private long sampleEpoch = 0;
  volatile long sampleCycles = 0;

  void setBackground(boolean value) {
    synchronized (sampleWake) {
      if (background == value) return;
      background = value;
      sampleEpoch++;
      sampleWake.notifyAll();
    }
  }

  // Testing only: CPU_BLOOM_FAKE_LOAD replaces every thread's load with a
  // constant ("0.5") or with seconds:load points from startup, interpolated
  // and held after the last one ("0:0,2:1,8:1,10:0"). CPU_BLOOM_FAKE_TEMP
  // does the same for the CPU temperature in °C ("40" or "0:40,5:90").
  private final float[][] fakeLoad = parseSchedule("load", System.getenv("CPU_BLOOM_FAKE_LOAD"), 0, 1);
  private final float[][] fakeTemp = parseSchedule("temp", System.getenv("CPU_BLOOM_FAKE_TEMP"), -50, 150);
  private final long startMs = System.currentTimeMillis();

  private final oshi.hardware.HardwareAbstractionLayer windowsHardware =
    System.getProperty("os.name").startsWith("Windows") ? new oshi.SystemInfo().getHardware() : null;
  private long[][] windowsTicks;

  SystemSampler() {
    if (windowsHardware != null) {
      oshi.hardware.CentralProcessor cpu = windowsHardware.getProcessor();
      cpuCount = cpu.getLogicalProcessorCount();
      coreCount = cpu.getPhysicalProcessorCount();
      cpuModel = cpu.getProcessorIdentifier().getName();
      usage = new float[cpuCount];
      prevIdle = new long[cpuCount];
      prevTotal = new long[cpuCount];
      displayOrder = new int[cpuCount];
      coreRank = new int[cpuCount];
      java.util.List<oshi.hardware.CentralProcessor.LogicalProcessor> logical = cpu.getLogicalProcessors();
      java.util.Map<String, Integer> ranks = new java.util.LinkedHashMap<String, Integer>();
      Integer[] order = new Integer[cpuCount];
      for (int i = 0; i < cpuCount; i++) {
        oshi.hardware.CentralProcessor.LogicalProcessor lp = logical.get(i);
        String key = lp.getPhysicalPackageNumber() + ":" + lp.getPhysicalProcessorNumber();
        if (!ranks.containsKey(key)) ranks.put(key, ranks.size());
        coreRank[i] = ranks.get(key);
        order[i] = i;
      }
      Arrays.sort(order, (a, b) -> Integer.compare(coreRank[a], coreRank[b]));
      for (int i = 0; i < cpuCount; i++) displayOrder[i] = order[i];
      windowsTicks = cpu.getProcessorCpuLoadTicks();
      tempPath = null;
      loadAvg = "N/A";
      return;
    }
    int count = 0;
    for (String line : lines("/proc/stat")) {
      if (line.matches("cpu\\d+ .*")) count++;
    }
    cpuCount = max(count, 1);
    usage = new float[cpuCount];
    prevIdle = new long[cpuCount];
    prevTotal = new long[cpuCount];

    final int[] pkg = new int[cpuCount];
    final int[] core = new int[cpuCount];
    Integer[] order = new Integer[cpuCount];
    for (int i = 0; i < cpuCount; i++) {
      String topo = "/sys/devices/system/cpu/cpu" + i + "/topology/";
      pkg[i] = readInt(topo + "physical_package_id", 0);
      core[i] = readInt(topo + "core_id", i);
      order[i] = i;
    }
    Arrays.sort(order, (a, b) -> pkg[a] != pkg[b] ? pkg[a] - pkg[b]
                               : core[a] != core[b] ? core[a] - core[b] : a - b);

    displayOrder = new int[cpuCount];
    coreRank = new int[cpuCount];
    int rank = -1;
    for (int slot = 0; slot < cpuCount; slot++) {
      int c = order[slot];
      if (slot == 0 || pkg[c] != pkg[order[slot - 1]] || core[c] != core[order[slot - 1]]) rank++;
      displayOrder[slot] = c;
      coreRank[c] = rank;
    }
    coreCount = rank + 1;

    String model = "Unknown CPU";
    for (String line : lines("/proc/cpuinfo")) {
      if (line.startsWith("model name")) {
        model = line.substring(line.indexOf(':') + 1).trim();
        break;
      }
    }
    cpuModel = model;
    tempPath = findTempSensor();
    sampleCpu();  // prime the deltas so the first real sample is meaningful
  }

  public void run() {
    gpuThread = new Thread(this::readGpu, "gpu-sampler");
    gpuThread.setDaemon(true);
    gpuThread.start();
    long nextMem = 0, nextSlow = 0;
    long observedEpoch = -1;
    while (running) {
      long epoch;
      synchronized (sampleWake) { epoch = sampleEpoch; }
      if (epoch != observedEpoch) {
        nextMem = nextSlow = 0;
        observedEpoch = epoch;
      }
      long now = System.currentTimeMillis();
      try {
        sampleCpu();
        sampleCycles++;
        if (now >= nextMem) { sampleMem(); nextMem = now + 500; }
        if (now >= nextSlow) { sampleLoadAndTemp(); nextSlow = now + 1000; }
        Process p = gpuProcess;
        if (p != null && (!gpuActive || now - gpuOutputAt > 6000)) p.destroyForcibly();
      } catch (Exception e) {
        println("sampler: " + e);
      }
      try {
        synchronized (sampleWake) {
          // Restoration wakes this immediately; don't lose a change during sampling.
          if (running && sampleEpoch == epoch) sampleWake.wait(background ? 2000 : 200);
        }
      } catch (InterruptedException e) {
        return;
      }
    }
  }

  void sampleCpu() {
    float[] next = new float[cpuCount];
    if (windowsHardware != null) {
      oshi.hardware.CentralProcessor cpu = windowsHardware.getProcessor();
      long[][] ticks = cpu.getProcessorCpuLoadTicks();
      int idleIndex = oshi.hardware.CentralProcessor.TickType.IDLE.getIndex();
      for (int i = 0; i < cpuCount; i++) {
        long total = 0;
        for (int j = 0; j < ticks[i].length; j++) total += ticks[i][j] - windowsTicks[i][j];
        long idle = ticks[i][idleIndex] - windowsTicks[i][idleIndex];
        next[i] = total > 0 ? constrain(1f - idle / (float) total, 0, 1) : usage[i];
      }
      windowsTicks = ticks;
      if (fakeLoad != null) Arrays.fill(next, scheduleValue(fakeLoad));
      usage = next;
      return;
    }
    for (String line : lines("/proc/stat")) {
      if (!line.startsWith("cpu") || line.charAt(3) == ' ') continue;
      String[] f = line.trim().split("\\s+");
      int id = Integer.parseInt(f[0].substring(3));
      if (id >= cpuCount) continue;
      long idle = Long.parseLong(f[4]) + Long.parseLong(f[5]);
      long total = 0;
      for (int k = 1; k <= 8 && k < f.length; k++) total += Long.parseLong(f[k]);
      long dTotal = total - prevTotal[id];
      long dIdle = idle - prevIdle[id];
      next[id] = dTotal > 0 ? constrain(1f - dIdle / (float) dTotal, 0, 1) : usage[id];
      prevTotal[id] = total;
      prevIdle[id] = idle;
    }
    if (fakeLoad != null) Arrays.fill(next, scheduleValue(fakeLoad));
    usage = next;
  }

  float[][] parseSchedule(String what, String spec, float lo, float hi) {
    if (spec == null || spec.trim().isEmpty()) return null;
    String[] parts = spec.trim().split(",");
    float[][] points = new float[parts.length][2];
    for (int i = 0; i < parts.length; i++) {
      String[] p = parts[i].trim().split(":");
      points[i][0] = p.length > 1 ? Float.parseFloat(p[0]) : 0;
      points[i][1] = constrain(Float.parseFloat(p[p.length - 1]), lo, hi);
    }
    println("sampler: fake " + what + " " + spec);
    return points;
  }

  float scheduleValue(float[][] points) {
    float seconds = (System.currentTimeMillis() - startMs) / 1000f;
    if (seconds <= points[0][0]) return points[0][1];
    for (int i = 1; i < points.length; i++) {
      if (seconds <= points[i][0]) {
        float span = points[i][0] - points[i - 1][0];
        float k = span > 0 ? (seconds - points[i - 1][0]) / span : 1;
        return lerp(points[i - 1][1], points[i][1], k);
      }
    }
    return points[points.length - 1][1];
  }

  void sampleMem() {
    if (windowsHardware != null) {
      oshi.hardware.GlobalMemory mem = windowsHardware.getMemory();
      memTotalGiB = mem.getTotal() / 1073741824f;
      memUsedGiB = (mem.getTotal() - mem.getAvailable()) / 1073741824f;
      return;
    }
    long total = 0, available = 0;
    for (String line : lines("/proc/meminfo")) {
      if (line.startsWith("MemTotal:")) total = kib(line);
      else if (line.startsWith("MemAvailable:")) available = kib(line);
    }
    memTotalGiB = total / 1048576f;
    memUsedGiB = (total - available) / 1048576f;
  }

  void sampleLoadAndTemp() {
    String[] f = readText("/proc/loadavg", "").split("\\s+");
    if (f.length >= 3) loadAvg = f[0] + " " + f[1] + " " + f[2];
    if (tempPath != null) tempC = readInt(tempPath, 0) / 1000f;
    if (fakeTemp != null) tempC = scheduleValue(fakeTemp);
  }

  void setGpuActive(boolean active) {
    Process obsolete;
    synchronized (gpuWake) {
      if (gpuActive == active) return;
      gpuActive = active;
      gpuEpoch++;
      obsolete = active ? null : gpuProcess;
      gpuWake.notifyAll();
    }
    if (obsolete != null) obsolete.destroyForcibly();
  }

  void close() {
    running = false;
    synchronized (sampleWake) { sampleWake.notifyAll(); }
    setGpuActive(false);
    if (gpuThread != null) gpuThread.interrupt();
  }

  // One long-lived query while visible. Blocking reads happen on their own
  // thread; the 200 ms sampler enforces a six-second output timeout.
  void readGpu() {
    while (running) {
      Process p = null;
      int epoch = gpuEpoch;
      try {
        synchronized (gpuWake) {
          while (running && !gpuActive) gpuWake.wait();
          epoch = gpuEpoch;
        }
        if (!running) return;
        p = new ProcessBuilder("nvidia-smi",
          "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total",
          "--format=csv,noheader,nounits", "--id=0", "--loop=2")
          .redirectErrorStream(true).start();
        gpuOutputAt = System.currentTimeMillis();
        gpuProcess = p;
        if (!gpuActive || !running || epoch != gpuEpoch) p.destroyForcibly();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
          String line;
          while (running && gpuActive && epoch == gpuEpoch && (line = reader.readLine()) != null) {
            String[] f = line.split(",\\s*");
            if (f.length != 4) continue;
            try {
              gpuUtil = Float.parseFloat(f[0]);
              gpuTempC = Float.parseFloat(f[1]);
              gpuMemUsedGiB = Float.parseFloat(f[2]) / 1024f;
              gpuMemTotalGiB = Float.parseFloat(f[3]) / 1024f;
              gpuSeen = true;
              gpuOutputAt = System.currentTimeMillis();
            } catch (NumberFormatException invalid) { /* unsupported metrics */ }
          }
        }
        if (running && gpuActive && epoch == gpuEpoch) { gpuSeen = false; return; }
      } catch (InterruptedException e) {
        return;
      } catch (IOException e) {
        if (gpuActive && epoch == gpuEpoch) { gpuSeen = false; return; }
      } finally {
        if (p != null) p.destroyForcibly();
        gpuProcess = null;
      }
    }
  }

  String findTempSensor() {
    File[] mons = new File("/sys/class/hwmon").listFiles();
    if (mons == null) return null;
    Arrays.sort(mons);
    for (File m : mons) {
      String name = readText(m + "/name", "");
      if (name.equals("k10temp") || name.equals("zenpower") || name.equals("coretemp")) {
        File t = new File(m, "temp1_input");
        if (t.exists()) return t.getPath();
      }
    }
    return null;
  }

  long kib(String meminfoLine) {
    return Long.parseLong(meminfoLine.replaceAll("\\D+", ""));
  }

  List<String> lines(String path) {
    try {
      return Files.readAllLines(Paths.get(path));
    } catch (IOException e) {
      return Collections.emptyList();
    }
  }

  String readText(String path, String fallback) {
    List<String> l = lines(path);
    return l.isEmpty() ? fallback : l.get(0).trim();
  }

  int readInt(String path, int fallback) {
    try {
      return Integer.parseInt(readText(path, ""));
    } catch (NumberFormatException e) {
      return fallback;
    }
  }
}
