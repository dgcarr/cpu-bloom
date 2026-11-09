# Source code and replacement libraries

CPU Bloom is MIT licensed. You may modify it, replace its libraries and reverse
engineer it to debug modifications to the LGPL-covered Processing library.
No CPU Bloom license term restricts those rights. Third-party licenses remain
applicable to their respective components.

This directory accompanies the binaries, without an additional charge:

- `processing-4.5.7.tar.gz`: complete upstream Processing source at release
  commit ca3999abed94d84764370f120daaaaf9f0a77ae8, including core and build files.
  Core is LGPL 2.1-or-later; the editor's separate GPL license does not change
  the license of the core library used by CPU Bloom. See `core/LICENSE.md` and
  `BUILD.md`. With JDK 17, run `gradlew.bat :core:jar` from the extracted root.
- `OpenJDK17U-jdk-sources_17.0.21_9.tar.gz`: corresponding OpenJDK source supplied
  by Temurin for 17.0.21+9, including native code, licenses and `doc/building.md`.
- `temurin-build.tar.gz`: Temurin build scripts at the commit identified by the
  bundled runtime's `java/release` BUILD_SOURCE. Runtime metadata and the upstream
  SBOM accompany it, including build configuration and toolchain information.
- `cpu-bloom-source.zip`: application source and packaging scripts for this build.
  Animation data and dependency JARs are present in the application's `data` and
  `lib` directories. No third-party library has been modified by CPU Bloom.

The checksums and original download locations are in `sources.lock.json`.
The runtime's complete notices are retained in `java/legal` and `java/NOTICE`.

## Run with a replacement library

Windows protects installed MSIX contents. Copy the application's contents to a
directory you own before replacing anything; never modify WindowsApps permissions.
Replace `lib/core-4.5.7.jar` with your compatible rebuilt Processing core JAR,
keeping that filename or removing the old JAR so only one core is on the classpath.
From that writable directory run:

```powershell
.\java\bin\java.exe -cp 'lib/*' cpu_bloom
```

This launches outside the Store package identity and uses portable settings.
You can also replace the `java` directory with a compatible Java 17 runtime.
No signature or library checksum check prevents running this modified copy.
For application changes, extract the app source, copy `data` and the dependency
JARs into its sketch's `data` and `code` directories, and export with Processing
4.5.7. Build instructions and pinned inputs are in `packaging/msix/README.md`.
Network access may be needed to obtain build tools and build-time dependencies;
the corresponding source itself accompanies this distribution.
