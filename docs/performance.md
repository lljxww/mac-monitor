# Performance validation — v0.1.0

Measured on 2026-10-26 with an Apple M2 Pro (10 logical CPUs), macOS 27.0.1, Swift 6.4.2, Release/arm64 builds, and approximately 800 running processes. The before binary was built from the starting implementation; the after binary includes the optimizations in this release. The application was stopped during the comparison.

Each mode uses three warm-up samples followed by 80 measured samples, with 50 ms sleeps between iterations. This intentionally stresses the sampler; the application's default refresh interval is 2 seconds. Each iteration reads the three rankings six times to measure repeated SwiftUI-style reads of one snapshot. These are sampler microbenchmarks, **not whole-application CPU or energy measurements**.

| Measurement | Before | After |
| --- | ---: | ---: |
| Menu-bar-only sampling, median wall time | 0.436 ms | 0.094 ms |
| All process metrics, median sampling wall time | 20.900 ms | 15.948 ms |
| Eighteen ranking reads, median wall time | 9.491 ms | 0.0012 ms |
| Benchmark process CPU per full iteration | 15.665 ms | 7.504 ms |
| Child `ps` CPU per full iteration | 13.238 ms | 11.586 ms |
| Full sampling, 95th percentile wall time | 22.299 ms | 32.765 ms |

The median full sample improved by about 24%; benchmark-process CPU per iteration decreased by about 52%. Tail latency remained variable and was higher in this run; this is not a claim that every sample is faster. Background scheduling, process churn, and the protected-process `ps` query affect these figures. See the complete [before](performance-before.json) and [after](performance-after.json) data rather than treating one measurement as a universal guarantee.

The new GPU-only mode sampled approximately 20 GPU processes in 3.903 ms median, with **zero child-process CPU**: it skips the CPU/memory libproc and `ps` queries. The menu-bar-only mode also starts no child process.

## Changes

- Cache rankings per immutable snapshot; sort compact keys once on the sampling actor.
- Keep only date and three percentages in chart history, bounded to two minutes. Executable paths and process arrays are no longer retained by historical points.
- Publish SwiftUI snapshots only while the popover is visible. Closed views do not rebuild every tick.
- Query only enabled system metrics and the current page's process metrics. Settings and a closed popover scan no processes.
- Reuse accelerator handles and GPU client ownership; read individual driver properties with a serialization fallback for older drivers.
- Reuse permission-denied process results for up to 30 seconds, keyed by process identity; retry and invalidate on PID reuse.
- Redraw the menu-bar bitmap only when its segment count, displayed text, dimensions, or appearance changes. Display-only settings no longer restart the sampling task.

## Reproduce

```bash
swift run -c release --arch arm64 MonitorProbe --benchmark --samples 80
swift test --arch arm64
./scripts/build-app.sh
```

For UI state and rendering checks, build Debug and use `--ui-self-test` as described in the README. The local run passed 21 checks including no automatic input focus, no main window, persistent visibility settings, sorted full lists, GPU-only query scope, and stopping process enumeration in settings/after closing. It uses app-owned state and view rendering; it does not perform external mouse automation. A missing hardware GPU counter should be investigated on a physical Apple Silicon Mac rather than inferred from a virtual CI runner.

Release validation also checks native arm64 architecture, `LSUIElement`, minimum OS, bundle version, code signature, ZIP contents, DMG integrity, and SHA-256 checksums.
