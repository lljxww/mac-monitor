# Changelog

## 0.1.0 — 2026-10-26

Initial open-source release for native Apple Silicon Macs running macOS 14 or later.

- Eight-segment CPU, GPU, and memory meters in the menu bar.
- Top five processes per metric, with full process lists in the same popover.
- Persistent visibility, refresh interval, and optional percentage settings.
- No main window, Dock icon, or automatically focused input control.
- GPU process counters from the Apple driver and basic statistics for protected processes.
- Cached rankings and menu bar images; lightweight history without process snapshots.
- Sampling follows the visible page and enabled metrics; no process scans while closed or in settings.
- MIT license, macOS CI, and tag-triggered DMG/ZIP/checksum releases.

Release binaries are ad-hoc signed and are not Developer ID signed or notarized.
