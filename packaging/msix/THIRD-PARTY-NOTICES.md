# Third-party software

CPU Bloom is MIT licensed. Its dependencies retain their original licenses:

| Component | Version | License / upstream |
|---|---|---|
| Processing core | 4.5.7 | LGPL-2.1; https://github.com/processing/processing4 |
| Eclipse Temurin Java runtime | 17.0.21+9 | GPL-2.0 with Classpath Exception; https://github.com/adoptium/temurin17-binaries |
| JOGL / GlueGen | 2.6.0 | BSD-style and component notices; https://jogamp.org |
| JNA / JNA Platform | 5.19.1 | Apache-2.0 or LGPL-2.1; https://github.com/java-native-access/jna |
| OSHI | 6.9.3 | MIT; https://github.com/oshi/oshi |
| SLF4J API / no-op backend | 2.0.17 | MIT; https://www.slf4j.org |
| Kotlin standard library | 2.3.21 | Apache-2.0; https://github.com/JetBrains/kotlin |
| JetBrains annotations | 13.0 | Apache-2.0; https://github.com/JetBrains/java-annotations |
| ANTLR | 2.7.7 | Public-domain dedication / upstream license; https://www.antlr2.org |
| Processing Serial / jSSC (exported dependencies) | See binary inventory | Preserve included LGPL notices and upstream license text; review whether unused export dependencies can be removed |

The package contains Java runtime notices in `java/legal`, extracted JAR notices in `ThirdPartyNotices`, and a SHA-256 binary inventory. These are an inventory, not a substitute for reviewing each license.

RELEASE GATE: collect the exact corresponding source for distributed LGPL/GPL components (including native components), any modifications and applicable build instructions; provide a license-compliant source distribution/offer and preserve required replacement/relinking rights. Review the entire extracted notice inventory before setting `ThirdPartyNoticesReviewed=true`. No assertion of completed legal review is made by the test build.
