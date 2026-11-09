import java.util.*;

public class GpuCounterCheck {
    static void check(boolean result,String name) {
        if(!result) throw new AssertionError(name);
        System.out.println("PASS: "+name);
    }
    static String key(int pid,int adapter,int engine) {
        return "pid_"+pid+"_luid_0x00000000_0x0000000"+adapter+"_phys_0_eng_"+engine+"_engtype_3D";
    }
    public static void main(String[] args) throws Exception {
        Map<String,Double> values=new HashMap<>();
        check(Float.isNaN(WindowsGpuCounters.busiest(values)),"missing counters are unavailable");
        values.put(key(1,1,0),0d);
        check(WindowsGpuCounters.busiest(values)==0,"real idle is zero");
        values.put(key(1,1,0),30d); values.put(key(2,1,0),25d);
        values.put(key(1,1,1),40d); values.put(key(1,2,0),50d);
        values.put("invalid",999d); values.put(key(3,1,0),Double.NaN);
        check(WindowsGpuCounters.busiest(values)==55,"sum processes, keep adapters/engines separate");
        values.put(key(2,1,0),90d);
        check(WindowsGpuCounters.busiest(values)==100,"bound utilization");
        for(int cycle=0;cycle<2;cycle++) {
            try(WindowsGpuCounters counters=new WindowsGpuCounters()) {
                Thread.sleep(2100);
                float sample=counters.sample();
                check(Float.isFinite(sample)&&sample>=0&&sample<=100,"live Windows sample after opening/reopening: "+sample);
            }
        }
    }
}
