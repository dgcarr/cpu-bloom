CPU Bloom - Windows x64 portable build

Extract the entire ZIP to a writable folder, then double-click cpu_bloom.exe.
Keep the data, lib and java folders beside the executable. Java is bundled.
Requires 64-bit Windows and an OpenGL 2-capable graphics driver.

N: next theme; A: always on top; H: HUD; P/Space: pause; S: screenshot.
Run cpu_bloom.exe --overlay for the borderless overlay.
Run cpu_bloom.exe --theme=ridge (or bloom, poppy, orchid) to select a theme.
Settings: %APPDATA%\CPU Bloom\settings.properties.

CPU load, physical core grouping and RAM use are sampled through OSHI.
NVIDIA metrics require nvidia-smi on PATH. CPU temperature and Unix load
average are unavailable. The Linux tray menu and login integration are not
included. This build is unsigned and has not been runtime-tested on Windows.

Third-party software: Processing (LGPL-2.1), JOGL/GlueGen (BSD-style),
JNA/JNA Platform (Apache-2.0 or LGPL-2.1), OSHI and SLF4J (MIT),
Eclipse Temurin (GPL-2.0 with Classpath Exception). Library notices are
included in the JARs; runtime notices are under java/legal.
