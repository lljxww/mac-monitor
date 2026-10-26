# Contributing

Use an Apple Silicon Mac with macOS 14 or later and Swift 6 / Xcode 16 or later.

```bash
swift test --arch arm64
./scripts/build-app.sh
```

Changes to sampling should cover missing counters, PID reuse, and client removal. Run `MonitorProbe` on real hardware to verify units and data availability. For UI changes, use the Debug-only `--ui-self-test` command documented in the README and inspect the generated PNGs. GitHub-hosted runners may not expose physical GPU counters.

Do not commit local build products, credentials, signing certificates, or captured process dumps. Keep the checked-in Xcode project in sync with `project.yml` by running `xcodegen generate` when adding source files.

Pull requests run read-only CI on macOS 15 and 26. Maintainers publish releases by pushing a version tag such as `v0.2.0`; the Release workflow tests, packages, uploads checksums, and publishes only after all steps succeed. Pre-release tags such as `v0.2.0-beta.1` become GitHub pre-releases. Re-running the workflow preserves an already published release.
