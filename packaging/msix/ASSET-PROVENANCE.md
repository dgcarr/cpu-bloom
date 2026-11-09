# CPU Bloom assets

On 9 November 2026 the project owner explicitly confirmed: "we build the frame animations they are ours".

| Assets | Provenance | Packaging decision |
|---|---|---|
| `cpu_bloom/data/poppy`, `cpu_bloom/data/orchid` | Owner-created Blender frame animations, confirmed by owner | Include |
| Bloom and Ridge procedural graphics | Repository implementation under the project's MIT license | Include |
| `icons/cpu-bloom.svg` | Repository artwork; rasterized unchanged into Store assets | Include; retain project license |
| Reference MP4 in repository root | Reference material; no redistribution evidence needed for excluded file | Never package |
| Fonts | Use installed system fonts; no font files shipped | No bundled font license |

The build packages only exported `data`, JARs, the pinned runtime, native binaries, Store icons, and notices. Blender sources, references, development tools, and arbitrary repository files are excluded. Archive this statement with each release and review new assets before adding them.
