# Local validation: 0.3.2

## 0.3.3 efficiency update

Rebuilt and installed locally on 9 November 2026. Package-content and native-helper
checks passed. `EfficiencyCheck.java` ran against the installed package and passed:

- Tray hidden: zero frames and two sampling cycles over 4.2 seconds.
- Native Windows minimize with app tray handling disabled: zero frames and two
  sampling cycles over 4.2 seconds.
- Restoring resumed both rendering and metric sampling.

Measured process CPU time during those short hidden intervals was approximately
109 ms and 281 ms respectively. These are smoke-test observations, not a controlled
before/after benchmark or a claim of zero CPU usage. The visibility watcher still
runs five times per second; retained graphics caches are not released on minimize.
Installed rendering reported AMD Radeon 840M / OpenGL 4.6.
WACK was not rerun for 0.3.3; the unresolved findings below remain release work.

## 0.3.2 package and certification baseline

Validated on Windows 11 Home build 26300, x64, with AMD Radeon 840M graphics.
This does not establish compatibility on clean systems or Store acceptance.

- The local unsigned MSIX installed as `CpuBloom.LocalTest_0.3.2.0_x64__zn2wp2gj642tw`.
- Package SHA-256: `B596642B547004C3CFA3B112D669C125529B79D818075449109901BB26913DD3`.
- Package-content/helper checks, release-configuration gates, and Java logic checks passed.
- Installed runtime checks on 0.3.1 verified rendering, tray restoration, duplicate
  manual activation, package storage, preference import and disabled startup.
  The 0.3.2 change snapshots cache timestamps before sorting; its cache regression
  check passed. The complete installed runtime check has not been repeated on 0.3.2.
- Startup API testing verified Disabled → Enabled → Disabled. Actual sign-out and
  sign-in remains untested. Portable startup consent was preserved.

## Windows App Certification Kit

WACK 10.0.26100.7705 completed the 0.3.2 test on 9 November 2026.
The process exited successfully, but the report's overall result is **WARNING**,
not a clean certification pass.

- **Blocked executables (optional): FAIL.** The scanner reported process-launch
  APIs in Java runtime DLLs and executable-name strings in runtime DLLs and bundled
  JARs. These findings require review; they have not been dismissed as false positives.
- **DPIAwarenessValidation: WARNING.** The kit could not process the native launcher
  and reported that the application was not DPI aware. Launcher manifest and actual
  high-DPI behavior need follow-up before submission.
- All other reported test results were PASS.

The full local report is `dist/msix/certification-0.3.2/wack.xml` (build output,
not committed). Store packaging remains blocked on assigned publisher identity,
public privacy/support URLs, third-party license/source review and the release
matrix in `STORE-SUBMISSION.md`. Owner-confirmed animation provenance is recorded
in `ASSET-PROVENANCE.md`.
