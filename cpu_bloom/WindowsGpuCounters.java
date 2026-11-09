import com.sun.jna.*;
import com.sun.jna.ptr.IntByReference;
import com.sun.jna.platform.win32.Pdh;
import com.sun.jna.platform.win32.WinNT.HANDLE;
import com.sun.jna.platform.win32.WinNT.HANDLEByReference;
import java.util.*;
import java.util.regex.*;

/** Windows x64 PDH GPU Engine accounting; no vendor tools or child processes. */
public final class WindowsGpuCounters implements AutoCloseable {
    public interface ArraysApi extends com.sun.jna.win32.StdCallLibrary {
        int PdhGetFormattedCounterArrayW(HANDLE counter, int format,
            IntByReference bytes, IntByReference count, Pointer buffer);
    }
    private final Pdh pdh = Pdh.INSTANCE;
    private final ArraysApi arrays = Native.load("pdh", ArraysApi.class);
    private HANDLE query, counter;
    private static final Pattern INSTANCE = Pattern.compile(
        "pid_\\d+_(luid_0x[0-9a-f]+_0x[0-9a-f]+_phys_\\d+)_eng_(\\d+)_engtype_.+", Pattern.CASE_INSENSITIVE);

    public WindowsGpuCounters() {
        if(Native.POINTER_SIZE!=8) throw new UnsupportedOperationException("GPU counters require Windows x64");
        HANDLEByReference handle=new HANDLEByReference();
        check(pdh.PdhOpenQuery(null,null,handle)); query=handle.getValue();
        try {
            check(pdh.PdhAddEnglishCounter(query,"\\GPU Engine(*)\\Utilization Percentage",null,handle));
            counter=handle.getValue();
            check(pdh.PdhCollectQueryData(query)); // prime rate counters
        } catch(RuntimeException e) { close(); throw e; }
    }
    private static void check(int status) {
        if(status!=0) throw new IllegalStateException("PDH status 0x"+Integer.toHexString(status));
    }

    /** Sum processes on each physical engine, then take the busiest engine. */
    public static float busiest(Map<String,Double> instances) {
        Map<String,Double> engines=new HashMap<>();
        for(Map.Entry<String,Double> entry:instances.entrySet()) {
            Matcher match=INSTANCE.matcher(entry.getKey());
            double value=entry.getValue();
            if(!match.matches() || !Double.isFinite(value) || value<0) continue;
            String engine=match.group(1).toLowerCase(Locale.ROOT)+"/"+match.group(2);
            engines.merge(engine,value,Double::sum);
        }
        if(engines.isEmpty()) return Float.NaN; // missing is not idle
        double maximum=0;
        for(double value:engines.values()) maximum=Math.max(maximum,value);
        return (float)Math.min(100,maximum);
    }

    public float sample() {
        if(query==null) return Float.NaN;
        if(pdh.PdhCollectQueryData(query)!=0) return Float.NaN;
        // Process instances can appear between sizing and reading; retry boundedly.
        for(int attempt=0;attempt<3;attempt++) {
            IntByReference bytes=new IntByReference(), count=new IntByReference();
            int format=Pdh.PDH_FMT_DOUBLE|Pdh.PDH_FMT_NOCAP100;
            int status=arrays.PdhGetFormattedCounterArrayW(counter,format,bytes,count,null);
            if(status!=Pdh.PDH_MORE_DATA || bytes.getValue()<=0 || bytes.getValue()>16*1024*1024) return Float.NaN;
            try(Memory buffer=new Memory(bytes.getValue())) {
                status=arrays.PdhGetFormattedCounterArrayW(counter,format,bytes,count,buffer);
                if(status==Pdh.PDH_MORE_DATA) continue;
                if(status!=0 || count.getValue()<0 || count.getValue()>buffer.size()/24) return Float.NaN;
                Map<String,Double> values=new HashMap<>();
                // Windows x64 PDH_FMT_COUNTERVALUE_ITEM_W: name pointer at 0,
                // CStatus at 8, double union at 16; sizeof(item) = 24.
                for(int i=0;i<count.getValue();i++) {
                    long offset=24L*i;
                    int valid=buffer.getInt(offset+8);
                    Pointer name=buffer.getPointer(offset);
                    if((valid==0 || valid==1) && name!=null)
                        values.put(name.getWideString(0),buffer.getDouble(offset+16));
                }
                return busiest(values);
            }
        }
        return Float.NaN;
    }
    public void close() {
        if(query!=null) { pdh.PdhCloseQuery(query); query=null; counter=null; }
    }
}
