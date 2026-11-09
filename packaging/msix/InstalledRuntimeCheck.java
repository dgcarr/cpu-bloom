import processing.core.PApplet;
import java.io.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Run using the installed JRE in package context; not shipped in the MSIX. */
public class InstalledRuntimeCheck {
    static void waitFor(BooleanSupplier condition) throws Exception {
        for (int i=0; i<200; i++) { if (condition.getAsBoolean()) return; Thread.sleep(100); }
        throw new AssertionError("Timed out waiting for installed runtime");
    }
    static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
        System.out.println("PASS: " + message);
    }
    public static void main(String[] args) throws Exception {
        cpu_bloom app = new cpu_bloom();
        try {
            PApplet.runSketch(new String[]{"cpu_bloom","--start-minimized"},app);
            waitFor(() -> app.desktopTray != null && app.hiddenInTray && !app.newtWindow().isVisible());
            check(app.isStorePackage(), "installed JVM receives package context");
            check(app.configDir().toString().contains("LocalState"), "settings use package LocalState");
            check(app.frameCacheFile(new File("example.jpg"),400).toString().contains("LocalCache"), "frame cache uses package LocalCache");
            check(app.themes.size()==4, "all four themes available");
            check(app.packagedStartupState("startup-query").equals("Disabled"), "Store startup remains off by default");
            Process launcher = new ProcessBuilder(new File(app.applicationDirectory(),"cpu_bloom.exe").toString()).start();
            launcher.waitFor();
            waitFor(() -> app.newtWindow().isVisible() && !app.hiddenInTray);
            check(true, "second packaged launch restores tray instance");
            Properties p = new Properties(); p.setProperty("theme","poppy"); p.setProperty("alwaysOnTop","false"); p.setProperty("startup","true");
            Properties geometry = new Properties(); geometry.setProperty("width","880"); geometry.setProperty("height","570");
            app.queueDesktopAction(() -> {
                try { app.applyImportedPortableSettings(p,geometry); } catch(IOException e) { throw new RuntimeException(e); }
            });
            waitFor(() -> app.theme.id().equals("poppy") && app.newtWindow().getWidth()==880);
            check(!app.loadSettings().containsKey("startup"), "import whitelists preferences");
            check(app.packagedStartupState("startup-query").equals("Disabled"), "import does not enable login startup");
            check("imported".equals(app.loadSettings().getProperty("portableImport")), "one-time migration recorded");
            app.minimizeDesktopToTray(); waitFor(() -> !app.newtWindow().isVisible());
            app.restoreDesktopWindow(); waitFor(() -> app.newtWindow().isVisible() && !app.hiddenInTray);
            check(true, "installed tray hide/restore cycle");
            app.exit();
        } catch(Throwable error) { error.printStackTrace(); app.removeDesktopTray(); System.exit(1); }
    }
}
