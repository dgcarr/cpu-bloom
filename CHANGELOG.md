# Changelog

## Unreleased

- The Orchid theme: a photorealistic moth orchid, rendered with Blender after a bud-to-bloom timelapse, that opens with CPU load and glows with CPU temperature.
- Pre-rendered themes share one player, `FrameSequenceTheme`.

## 0.1.0 (2026-11-03)

First public release.

- The Bloom theme: one petal per CPU thread, with load history, RAM, GPU and temperature.
- The Ridge theme: a 3D landscape of per-thread load over time.
- The Poppy theme: a photorealistic poppy, rendered with Blender, that opens with CPU load and is lit by CPU temperature.
- An always-on-top overlay, and an always-on-top toggle for the full window.
- A tray indicator (gjs and Ayatana AppIndicator) showing average load, with Start at Login. Without a tray, the launcher opens the window directly.
- Packages: a strictly confined snap on the Snap Store, plus .deb, .rpm, an Arch package and a tarball with `install.sh`.
