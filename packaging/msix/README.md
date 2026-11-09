# Windows Store / MSIX build

This build retains the bundled Java renderer and builds three native x64 binaries:
`cpu_bloom.exe` (manual activation), `cpu_bloom_startup.exe` (tray startup), and
`store-bridge.exe` (fixed startup query/enable/disable operations and diagnostic context).
The manifest declares `runFullTrust`, Windows 11 minimum build 22000, and a disabled
`CpuBloomStartup` startup task. No administrator privileges are requested by the app.

## Build inputs

Use the pinned Processing 4.5.7 Windows portable distribution, MSVC 14.44.35207,
Windows SDK 10.0.26100.0, Python 3, and the Temurin 17.0.21+9 Windows JRE archive.
`inputs.lock.json` verifies the complete Processing distribution tree, source JARs,
and runtime archive. The Processing download is the official
https://github.com/processing/processing4/releases/tag/processing-1435-4.5.7 .
The JRE URL and checksum are in the lock. Dependency upgrades require a deliberate
lock review, rebuild, license review, and regression run.

```powershell
./packaging/msix/build-msix.ps1 -Mode Test -ProcessingRoot 'C:\tools\Processing' -JreArchive 'C:\downloads\windows-jre.zip'
```

The default tool locations match this development machine. Every run creates a
fresh directory under `dist/msix`, with the MSIX, unpackaged layout, compiler and
Processing logs, MakeAppx validation log, and `build-result.json` with SHA-256.
No existing portable app, startup shortcut, installed package or security setting
is modified by the build. `dist/msix/latest-test.json` points to the latest result.
Inputs and native compiler output are pinned; ZIP/MSIX metadata and generated
Processing timestamps mean byte-for-byte identical output is not promised.

## Local package testing

Test builds use **CpuBloom.LocalTest**, clearly labeled "CPU Bloom (Local Test)",
with Microsoft's unsigned-package OID. This is a development identity, not a
Partner Center identity. Do not submit or broadly distribute it.

Windows 11 requires an elevated PowerShell to install an unsigned executable
package. Run the following only after approving the specific installation:

```powershell
./packaging/msix/install-test.ps1 -BuildResult 'C:\path\to\build-result.json'
```

This uses `Add-AppxPackage -AllowUnsigned`, validates the expected SHA-256 and
test identity, and records `install-test.log`. It neither imports certificates nor
changes Developer Mode or Smart App Control. Installation may still be blocked
by device policy. Do not bypass that policy; use an authorized test machine.
See https://learn.microsoft.com/windows/msix/package/unsigned-package .

Launch "CPU Bloom (Local Test)" from Start. It has isolated package data and leaves
the existing portable application's startup setting unchanged. To inspect native
context, use `Invoke-CommandInDesktopPackage` to run `store-bridge.exe context`
inside the package. Its stdout is UTF-8; startup commands return one of Disabled,
Enabled, DisabledByUser, DisabledByPolicy, EnabledByPolicy. Failures return nonzero.

The normal app acquires a per-user file lock and observes a fixed activation signal
under its settings directory. Secondary manual launches restore it; secondary login
launches do not bring it forward. Overlay instances bypass that lock. No socket or
remote command channel is opened. OS file locking releases ownership after a crash.

## Release configuration

`store-config.json` contains CPU Bloom's assigned Partner Center identity and
public GitHub Pages privacy/support URLs. It contains no credentials. The dependency review is recorded in `THIRD-PARTY-NOTICES.md`. Builds verify
`Sources` archive checksums and notice provenance, and include corresponding source
for Processing and the Java runtime. For another publisher, copy `store-config.example.json` and populate
the exact assigned values. Do not fabricate a publisher identity.
Review `ASSET-PROVENANCE.md`, `THIRD-PARTY-NOTICES.md`, the extracted notices, and
`STORE-SUBMISSION.md`, then set the explicit review flags.

```powershell
./packaging/msix/build-msix.ps1 -Mode Store -ConfigFile packaging/msix/store-config.json
```

Store mode refuses missing identity/URLs, test publisher markers, malformed package
versions and unreviewed rights/notices. The Store signs the submitted package;
the unsigned test OID is never used for Store mode. No automated publishing is done.
Before submission, run WACK against the actual release package and perform a private
Store flight. The Store signer, certification, account verification, actual login,
clean-system and multi-GPU matrix cannot be substituted by an unpackaged smoke test.

## Data migration and privacy

The launcher obtains LocalFolder, LocalCacheFolder, TemporaryFolder and Pictures
through Windows APIs. Install contents are read-only; screenshots are explicit
exports. Preferences offers a one-time portable import, copying only the theme,
always-on-top preference and normal geometry; startup consent is never copied.
The portable installation and exported screenshots survive Store uninstall.

Windows may isolate the portable Roaming AppData folder from the package. In that
case use the updated portable app's Preferences > Export preferences, then the
Store app's Preferences > Import portable settings. The ZIP is read without
extracting paths, accepts only the two fixed property entries, limits their size,
and imports only the allowed preference/geometry keys after confirmation.

The maintained public pages are `docs/privacy.html` and `docs/support.html`.
GitHub Pages publishes `main:/docs`; future commits to that directory update the
pages. The package includes local copies and their stylesheet. The earlier
`privacy-policy.draft.md` is superseded. Review the public policy whenever data
handling changes.
