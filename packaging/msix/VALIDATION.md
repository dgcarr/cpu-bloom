# Store candidate 0.3.7.0 — 9 November 2026

The actual unsigned Store MSIX, with identity `David-Carr.CPUBloom`, completed
Windows App Certification Kit 10.0.26100.7705 using `-appxpackagepath`.
**Overall: PASS. All required tests: PASS, including DPIAwarenessValidation.**
This is a local certification result, not Microsoft Store acceptance.

- SHA-256: `0F4D3F2AFCC1F894B8B7130E63196D381B372213CC50D9CE21BE6406DF6AC782`.
- Package: `dist/msix/store-0.3.7.0-7a60cb7b/cpu-bloom-0.3.7.0-x64.msix`.
- Full report: `dist/msix/certification-store-0.3.7/wack.xml`.
- Versioned evidence file: `certification-0.3.7.json` records report/package
  hashes and each test result. `summarize-wack.py --require-pass` rejects required
  warnings/failures instead of trusting the tool's process exit code.
- Optional Archive files usage and Blocked executables tests remain FAIL. The
  first flags accompanying source archives; the second flags bundled runtime
  process APIs and executable-name strings in libraries/source/license materials.
  See the explicit triage in `STORE-SUBMISSION.md`. These do not turn this report's
  overall PASS into a failure; they have not been hidden or removed from the report.

## Changes and verification

The three native executables embed asInvoker/PerMonitorV2 manifests. Windows
handles their native dialogs; the Java renderer establishes its own awareness.
A live installed Java rendering process returned per-monitor awareness (2) from
GetProcessDpiAwareness. Mixed-DPI/multi-monitor behavior still needs hardware testing.
The earlier installed-unsigned-package workflow produced COM manifest-reader
errors; using the actual Store archive exposed the PerMonitorV2 requirement and
then verified the correction without altering Windows security settings.

The pinned dependency review is complete: exact notices and provenance, embedded
font/cursor licenses, full Processing/OpenJDK sources, Temurin build scripts and
replacement/relinking instructions accompany the package. Unused exported
libraries are excluded. The Store GPU path does not invoke external NVIDIA tools.

Package-content, source-checksum, embedded-manifest, helper and configuration-gate
checks passed. The final Store and test native executables are byte-identical and
all JAR member contents match. Installed tests of the same Java payload verified
package storage, four themes, tray restoration, duplicate activation and explicit
import preserving the existing Enabled startup state. All four themes rendered
and their screenshots were inspected on AMD Radeon 840M / OpenGL 4.6.

The installed 0.3.7 efficiency check also passed: zero frames and GPU collections
while tray-hidden or natively minimized, two CPU/RAM sampling cycles per 4.2 seconds,
and rendering/sampling resumed on restore. These short checks measured 93.75 ms
and 187.5 ms process CPU time respectively, not a controlled performance benchmark.

## Still required before public release

Publisher verification, final listing/screenshots and IARC questionnaire, clean
Windows 11 with Smart App Control enabled, Intel/NVIDIA and multiple-monitor
coverage, actual sign-out/sign-in, uninstall/reinstall and a private Store flight.
No security setting was changed. The 0.3.4 portable bundle remains separate;
this candidate and license review target the MSIX distribution.

---

# Validation history

## 0.3.4 Windows GPU activity update

Installed and tested on 9 November 2026 on the same AMD Radeon 840M host.
Package SHA-256: `8F0362215CFC5E4CE6EA335E13312C0ECF991AEAE4438175DAEA87A9B29C6CE3`.
Package-content and native-helper checks passed. The installed-package
`EfficiencyCheck` exited 0 and verified live Windows GPU activity, zero GPU
collections and zero rendered frames while hidden in the tray or natively
minimized with tray handling disabled, and resumed activity on restoration.
Both hidden intervals recorded two metric samples over 4.2 seconds.

The portable application JAR and exported source were refreshed from this build.
Intel/NVIDIA hardware, localized Windows and multiple adapters remain untested.
WACK was not rerun; the 0.3.2 certification findings below remain unresolved.

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
