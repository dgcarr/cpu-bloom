import java.io.*;
import java.nio.file.*;
import java.util.*;

// Separate JVM contenders exercise real OS file locks, not a mock of the implementation.
public class PackageLogicCheck {
    static File fixture;
    static class App extends cpu_bloom {
        public File configDir() { return fixture; }
    }
    static void check(boolean condition, String description) {
        if (!condition) throw new AssertionError(description);
        System.out.println("PASS: " + description);
    }
    static void child(String mode) throws Exception {
        Process process = new ProcessBuilder(
            new File(System.getProperty("java.home"), "bin/java.exe").toString(),
            "-cp", System.getProperty("java.class.path"), "PackageLogicCheck", mode, fixture.toString())
            .inheritIO().start();
        if (!process.waitFor(15, java.util.concurrent.TimeUnit.SECONDS)) {
            process.destroyForcibly(); throw new AssertionError("Child hung");
        }
        check(process.exitValue() == 0, "contender " + mode);
    }
    public static void main(String[] args) throws Exception {
        fixture = args.length > 1 ? new File(args[1]) : Files.createTempDirectory("cpu-bloom-logic-").toFile();
        App app = new App();
        if (args.length > 0) {
            if (args[0].equals("overlay")) app.overlay = true;
            boolean owner = app.acquireNormalInstance(args[0].equals("startup"));
            check(owner == (args[0].equals("owner") || args[0].equals("overlay")), "instance ownership");
            app.releaseNormalInstance(); return;
        }
        check(app.acquireNormalInstance(false), "first normal instance owns lock");
        child("manual");
        check(!app.readActivationSignal().isEmpty(), "manual launch requests activation");
        String signal = app.readActivationSignal();
        child("startup");
        check(signal.equals(app.readActivationSignal()), "duplicate login launch does not restore window");
        child("overlay");
        app.releaseNormalInstance(); child("owner");
        app.updatePackagedStartupState("Enabled"); check(app.startupEnabled, "enabled state");
        app.updatePackagedStartupState("DisabledByUser");
        check(!app.startupEnabled && app.desktopStatus.contains("Windows Settings"), "user disablement explained");
        app.updatePackagedStartupState("EnabledByPolicy");
        check(app.startupEnabled && app.desktopStatus.contains("organization"), "policy enablement explained");
        app.updatePackagedStartupState("DisabledByPolicy"); check(!app.startupEnabled, "policy disablement respected");
        for (String size : new String[]{"", "bad", "-1", "999999", "800"}) {
            Files.writeString(app.normalGeometryFile().toPath(), "width=" + size + "\nheight=" + size);
            app.loadNormalGeometry();
            check(app.normalWidth > 0 && app.normalHeight > 0 && app.normalWidth < app.normalWorkArea.width
                && app.normalHeight < app.normalWorkArea.height, "geometry clamps " + size);
        }
        check(app.screenshotsDirectory().isAbsolute(), "Pictures known-folder resolution");
        Files.writeString(new File(fixture, "settings.properties").toPath(), "theme=poppy\nalwaysOnTop=true\nstartup=true\nprivate=do-not-copy\n");
        File backup = new File(fixture, "backup.zip");
        app.exportPortableSettings(backup);
        Properties exported = app.readPreferenceArchive(backup, "settings.properties");
        check(exported.size() == 2 && "poppy".equals(exported.getProperty("theme"))
            && !exported.containsKey("startup") && !exported.containsKey("private"), "export excludes startup and unrelated preferences");
        try (java.util.zip.ZipOutputStream out = new java.util.zip.ZipOutputStream(new FileOutputStream(new File(fixture,"oversized.zip")))) {
            out.putNextEntry(new java.util.zip.ZipEntry("settings.properties")); out.write(new byte[70000]); out.closeEntry();
        }
        boolean rejected = false;
        try { app.readPreferenceArchive(new File(fixture,"oversized.zip"), "settings.properties"); } catch(IOException e) { rejected = true; }
        check(rejected, "oversized import rejected");
        File cache = new File(fixture,"cache"); cache.mkdir();
        File[] cacheFiles = new File[100];
        for (int i=0;i<cacheFiles.length;i++) {
            cacheFiles[i]=new File(cache,i+".pixels");
            try (RandomAccessFile f=new RandomAccessFile(cacheFiles[i],"rw")) { f.setLength(3L*1024*1024); }
        }
        java.util.concurrent.atomic.AtomicBoolean touching = new java.util.concurrent.atomic.AtomicBoolean(true);
        Thread touch = new Thread(() -> { while(touching.get()) { for(File f:cacheFiles) if(f.exists())f.setLastModified(System.currentTimeMillis()); } });
        touch.start();
        try { app.trimFrameDiskCache(cache); } finally { touching.set(false); touch.join(); }
        long remaining=0; for(File f:cacheFiles) { remaining+=f.length(); f.delete(); }
        check(remaining<=256L*1024*1024, "cache trimming remains bounded while readers update timestamps");
        app.windowOps.shutdownNow();
    }
}
