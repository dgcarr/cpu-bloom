CPU Bloom - Windows x64 portable build

Extract the entire ZIP to a writable folder, then double-click cpu_bloom.exe.
Keep the data, lib and java folders beside the executable. Java is bundled.
Requires 64-bit Windows and an OpenGL 2-capable graphics driver.

N: next theme; A: always on top; H: HUD; P/Space: pause; S: screenshot.
Use Menu (top right) to select a theme, open Preferences, minimize to tray,
or quit. Drag the bottom-right grip to resize. The title-bar minimize button
also hides the normal window in the tray. Double-click the tray icon to restore,
or right-click it for themes, Preferences, Show and Quit.
Preferences includes Start with Windows (off by default) and Always on top.
Preferences also exports a settings ZIP for explicit import into the Store
edition. Startup consent is never exported. Launching the normal app again
restores its existing window; overlay instances remain independent.
Start with Windows creates a shortcut for this portable folder in your personal
Startup folder; untick and retick it if you move the application folder.
Login startup opens minimized to the system tray. Manual launches stay visible;
use cpu_bloom.exe --start-minimized to start in the tray explicitly.
Run cpu_bloom.exe --overlay for the borderless overlay.
Run cpu_bloom.exe --theme=ridge (or bloom, poppy, orchid) to select a theme.
Settings: %APPDATA%\CPU Bloom\settings.properties.
Normal windows fit the desktop on first launch and remember resized dimensions
in %APPDATA%\CPU Bloom\window.properties. Saved sizes are capped to fit the
current desktop when reopening. Overlay geometry is stored separately.

CPU load, physical core grouping and RAM use are sampled through OSHI.
NVIDIA metrics require nvidia-smi on PATH. CPU temperature and Unix load
average are unavailable. This build is unsigned.

Third-party software: Processing (LGPL-2.1), JOGL/GlueGen (BSD-style),
JNA/JNA Platform (Apache-2.0 or LGPL-2.1), OSHI and SLF4J (MIT),
Eclipse Temurin (GPL-2.0 with Classpath Exception). Library notices are
included in the JARs; runtime notices are under java/legal.
