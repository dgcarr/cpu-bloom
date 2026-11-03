// Run with a deliberately stalled nvidia-smi stub at the front of PATH.
public class SamplerTimeout {
  public static void main(String[] args) throws Exception {
    cpu_bloom app = new cpu_bloom();
    cpu_bloom.SystemSampler sampler = app.new SystemSampler();
    Thread thread = new Thread(sampler); thread.setDaemon(true); thread.start();
    try {
      Thread.sleep(1500);
      if (sampler.memTotalGiB <= 0) throw new AssertionError("GPU query blocked memory sampling");
      java.lang.reflect.Field field = sampler.getClass().getDeclaredField("gpuProcess");
      field.setAccessible(true);
      Process process = (Process) field.get(sampler);
      if (process == null || !process.isAlive()) throw new AssertionError("stalled GPU test did not start");
      Thread.sleep(6000);
      if (process.isAlive()) throw new AssertionError("GPU query timeout did not kill the process");
      System.out.println("PASS: stalled GPU query does not block other samples and is terminated");
    } finally {
      sampler.close(); thread.join(1500);
      if (thread.isAlive()) throw new AssertionError("sampler did not stop");
    }
  }
}
