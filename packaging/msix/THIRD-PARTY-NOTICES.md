# Third-party software — Store distribution

Reviewed 9 November 2026 for CPU Bloom 0.3.7. CPU Bloom code and owner-created
animations are MIT licensed. Dependencies retain their own licenses and copyrights.

| Distributed component | Version | License and accompanying material |
|---|---|---|
| Processing core | 4.5.7 | LGPL 2.1; full license, corresponding source, build and replacement instructions |
| Eclipse Temurin/OpenJDK | 17.0.21+9 | GPL 2 with Classpath Exception; complete java/legal, java/NOTICE, corresponding source and Temurin build scripts |
| JOGL and Windows native libraries | 2.6.0 | BSD 2/3 clause, SGI FreeB, Apache 1.1/2.0 and upstream component notices |
| GlueGen runtime and Windows natives | 2.6.0 | BSD 2/3 clause and Apache 2.0 component notices |
| JNA and JNA Platform | 5.19.1 | Apache 2.0 selected from upstream dual-license option; native libffi MIT notice included |
| OSHI | 6.9.3 | MIT copyright and license included |
| SLF4J API and no-op backend | 2.0.17 | MIT; original JAR notices extracted |
| Processing Sans Pro font | Bundled with core | Adobe copyright and SIL Open Font License 1.1 retained; unmodified |
| Processing cursor artwork | Bundled with core | MIT; original embedded cursor license retained |
| Microsoft runtime components | Supplied with Temurin / native C++ builds | Microsoft runtime redistribution terms; runtime files remain with their supplying product |

`ThirdPartyNotices/upstream` contains exact upstream texts; `provenance.json`
records their source archive URL, checksum and member. Extracted JAR notices are
also in `ThirdPartyNotices`; `binary-inventory.json` identifies the shipped JARs.
`Sources/README.md` explains accompanying source and replacement/relinking rights.
No third-party library was modified. No separate fee is charged for source.

The Store package omits unused Kotlin, annotations, ANTLR, Serial/jSSC and empty
aggregator JARs exported by Processing. It does not distribute the Processing IDE
as an executable application. JOGL's optional Oculus native artifacts are absent.
Upstream notices may describe additional components not present in these runtime
JARs; they are preserved intact rather than edited. Runtime legal files include
OpenJDK's component-specific third-party and exception notices.

This review applies to the pinned inputs and runtime allowlist in this release.
Any dependency update requires renewed review of licenses, source and notices.

Microsoft redistribution references (reviewed 9 November 2026):
https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution
https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files
Native launchers use the release C++ runtime linked into the application; no
compiler, SDK, debug runtime or Visual Studio utility is shipped as a runtime tool.
The bundled Temurin runtime and its notices are redistributed unchanged.
