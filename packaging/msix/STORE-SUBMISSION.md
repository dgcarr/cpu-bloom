# Store submission workbook

## Product

- Free Windows 11 x64 desktop utility; English (en-US).
- Suggested description: CPU Bloom visualizes CPU activity as animated flowers and landscapes. Includes CPU and RAM readings, four themes, a resizable window, system-tray controls, and optional startup at Windows login.
- Requirements: Windows 11, x64, compatible OpenGL graphics driver. No external Java installation required.
- Limitations: CPU temperature and Unix load average are unavailable. Windows GPU activity requires compatible performance counters; The Store build does not invoke external NVIDIA tools. GPU temperature/memory are not exposed by the current Windows counter provider. No claim of native ARM64 support.
- Complete IARC questionnaire in Partner Center based on the actual utility; do not predeclare an unissued rating.

## Capability justification / certification notes

`runFullTrust` is required by this packaged Java desktop application for native Processing/JOGL rendering, Windows system metrics through OSHI/JNA, and the Windows system-tray icon. It runs as the interactive standard user, without elevation, drivers or services. There are no runtime software downloads or self-updates.

Launch from Start/Store to show the normal window. Menu selects a theme or opens Preferences. The lower-right grip resizes the window. Minimize hides it in the system tray; double-click its tray icon or launch the app again to restore it. Right-click the tray icon for Show, Theme, Preferences, Minimize and Quit.

Startup is off by default, declared in the manifest, and enabled only through Preferences or Windows Settings. Login starts the normal app minimized only after a tray icon is successfully installed. Windows user/policy startup disablement is respected. Portable settings can be imported explicitly without inheriting startup consent.

## Release blockers

- Assigned identity and privacy/support URLs are recorded in `store-config.json`.
- Confirm the publisher account's verification status in Partner Center before submission.
- License review completed for pinned 0.3.7 inputs; accompanying source and notices are included. Repeat the review when dependencies change.
- Store screenshots captured from the packaged build, final branding review and IARC answers.
- Clean Windows 11 / Smart App Control-on tests, GPU coverage, actual login tests, update/uninstall tests and private Store flight.
- Actual Store 0.3.7.0 MSIX: WACK overall PASS and every required test PASS. Optional archive/process-reference findings are documented below; see `certification-0.3.7.json`.

## Evidence matrix

Record OS build, graphics adapter/driver, scale factor, package SHA-256 and result for each: fresh install, first launch, four themes, metric fallback, resize/DPI/multiple monitors, keyboard use, pause, tray minimize/restore, duplicate activation, overlay independence, startup enable/disable/Windows override/login, portable import, screenshot destination, update settings retention, uninstall and reinstall. Check outbound connections during a representative run and confirm package-directory hashes remain unchanged.

## Optional WACK findings for the certification reviewer

The package includes complete corresponding OpenJDK/Processing source archives
under `Sources` to satisfy redistribution obligations. They are documentation
and developer source material, never extracted or executed by CPU Bloom. The
optional archive check reports these `.tar.gz` files.

The optional blocked-executable check reports process-launch APIs in the bundled
Java runtime and short executable-name strings in compressed JARs, source
archives, upstream metadata and an upstream license PDF. CPU Bloom's packaged
execution paths launch only its bundled Java executable and fixed-operation
startup helper. The portable-only PowerShell startup branch is bypassed in
package context; external `nvidia-smi` fallback is disabled in the Store build.
No command shell, driver installer, self-updater or downloaded executable is used
by the Store application's normal functionality.

Microsoft describes these two Desktop Bridge checks as informational:
https://learn.microsoft.com/en-us/windows/uwp/debug-test-perf/windows-desktop-bridge-app-tests
Do not describe an overall WARNING report as a clean pass. Verify every required
result with `python packaging/msix/summarize-wack.py <report.xml> --require-pass`.
