# Store submission workbook

## Product

- Free Windows 11 x64 desktop utility; English (en-US).
- Suggested description: CPU Bloom visualizes CPU activity as animated flowers and landscapes. Includes CPU and RAM readings, four themes, a resizable window, system-tray controls, and optional startup at Windows login.
- Requirements: Windows 11, x64, compatible OpenGL graphics driver. No external Java installation required.
- Limitations: CPU temperature and Unix load average are unavailable. GPU readings require compatible NVIDIA tooling and are optional. No claim of native ARM64 support.
- Complete IARC questionnaire in Partner Center based on the actual utility; do not predeclare an unissued rating.

## Capability justification / certification notes

`runFullTrust` is required by this packaged Java desktop application for native Processing/JOGL rendering, Windows system metrics through OSHI/JNA, and the Windows system-tray icon. It runs as the interactive standard user, without elevation, drivers or services. There are no runtime software downloads or self-updates.

Launch from Start/Store to show the normal window. Menu selects a theme or opens Preferences. The lower-right grip resizes the window. Minimize hides it in the system tray; double-click its tray icon or launch the app again to restore it. Right-click the tray icon for Show, Theme, Preferences, Minimize and Quit.

Startup is off by default, declared in the manifest, and enabled only through Preferences or Windows Settings. Login starts the normal app minimized only after a tray icon is successfully installed. Windows user/policy startup disablement is respected. Portable settings can be imported explicitly without inheriting startup consent.

## Release blockers

- Partner Center account, reserved name and assigned Name/Publisher identity.
- Publisher display name and public privacy/support URLs; publish the privacy draft after review.
- Corresponding source/license obligations for redistributed runtime and libraries; review exact bundled notices.
- Store screenshots captured from the packaged build, final branding review and IARC answers.
- Clean Windows 11 / Smart App Control-on tests, GPU coverage, actual login tests, update/uninstall tests and private Store flight.
- Certification-kit findings triaged against the actual Store package. A local unsigned test package is not submission-ready.

## Evidence matrix

Record OS build, graphics adapter/driver, scale factor, package SHA-256 and result for each: fresh install, first launch, four themes, metric fallback, resize/DPI/multiple monitors, keyboard use, pause, tray minimize/restore, duplicate activation, overlay independence, startup enable/disable/Windows override/login, portable import, screenshot destination, update settings retention, uninstall and reinstall. Check outbound connections during a representative run and confirm package-directory hashes remain unchanged.
