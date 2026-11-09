import processing.core.PApplet;
import java.util.function.BooleanSupplier;
import com.sun.jna.Pointer;
import com.sun.jna.platform.win32.User32;
import com.sun.jna.platform.win32.WinDef.HWND;

/** Exercise real rendering, native minimize without a tray, and wake-up. */
public class EfficiencyCheck {
    static void await(BooleanSupplier condition) throws Exception {
        for (int i=0;i<200;i++) { if(condition.getAsBoolean()) return; Thread.sleep(100); }
        throw new AssertionError("Timed out");
    }
    static void idle(cpu_bloom app, String label) throws Exception {
        Thread.sleep(1200); // allow in-flight draw/sample to finish
        long frames=app.renderActivity.frames, samples=app.sampler.sampleCycles;
        long cpu=ProcessHandle.current().info().totalCpuDuration().orElseThrow().toNanos();
        Thread.sleep(4200);
        long draws=app.renderActivity.frames-frames, polls=app.sampler.sampleCycles-samples;
        double cpuMs=(ProcessHandle.current().info().totalCpuDuration().orElseThrow().toNanos()-cpu)/1e6;
        if(draws!=0 || polls<1 || polls>3) throw new AssertionError(label+": frames="+draws+", samples="+polls);
        System.out.println("PASS: "+label+", zero frames; samples="+polls+"; process CPU ms over 4.2s="+cpuMs);
    }
    public static void main(String[] args) throws Exception {
        cpu_bloom app=new cpu_bloom();
        try {
            PApplet.runSketch(new String[]{"cpu_bloom"},app);
            await(()->app.renderActivity!=null && app.renderActivity.frames>5 && app.desktopTray!=null);
            app.minimizeDesktopToTray();
            await(()->!app.newtWindow().isVisible());
            idle(app,"tray hidden");
            app.restoreDesktopWindow();
            await(()->app.newtWindow().isVisible() && !app.hiddenInTray);
            final long frames=app.renderActivity.frames;
            await(()->app.renderActivity.frames>frames+5);
            // Leave the native tray resource intact; bypass the app's tray handling.
            java.awt.TrayIcon tray=app.desktopTray;
            app.desktopTray=null;
            HWND hwnd=new HWND(new Pointer(app.newtWindow().getWindowHandle()));
            User32.INSTANCE.ShowWindow(hwnd,6); // SW_MINIMIZE
            await(()->app.desktopWindowMinimized());
            idle(app,"native minimized without tray");
            long samples=app.sampler.sampleCycles;
            final long before=app.renderActivity.frames;
            User32.INSTANCE.ShowWindow(hwnd,9);
            await(()->app.renderActivity.frames>before+5 && app.sampler.sampleCycles>samples);
            app.desktopTray=tray;
            System.out.println("PASS: restore resumes rendering and sampling");
            app.exit();
        } catch(Throwable e) { e.printStackTrace(); app.removeDesktopTray(); System.exit(1); }
    }
}
