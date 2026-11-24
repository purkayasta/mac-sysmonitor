# Repository Guidelines

[README](README.md) · [Installation](INSTALL.md) · [Contributor guide](CONTRIBUTING.md) · [Report a bug](CONTRIBUTING.md#report-a-bug) · [Contact](CONTACT.md)

## Project Structure & Module Organization

`mac-sysmonitor` is a dependency-free Swift/AppKit menu bar app for Apple Silicon, targeting macOS 13+. `Sources/MacSysMonitor/main.swift` owns app lifecycle, menus, and saved preferences; `StatusGraphic.swift` renders compact indicators. `Package.swift` defines the executable package. `Resources/` contains bundle metadata, the master icon, its generation prompt, and the packaged `.icns`. Build scripts live in `scripts/`; generated binaries, caches, and app bundles belong in ignored `.build/` and `dist/` directories. No test target exists yet.

## Build, Test, and Development Commands

- `bash scripts/build-app.sh`: compile an optimized arm64 executable, package `dist/mac-sysmonitor.app`, and apply a free local ad-hoc signature.
- `open dist/mac-sysmonitor.app`: launch the menu bar app. Quit an existing copy before relaunching a rebuild.
- `bash scripts/build-icon.sh`: regenerate icon sizes and `.icns`; requires macOS image tools and Python 3 for its fallback.
- `codesign --verify --strict dist/mac-sysmonitor.app`: verify the built bundle’s signature.
- `plutil -lint Resources/Info.plist`: validate bundle metadata.

Use the direct compiler build script as the baseline workflow. The initial machine has inconsistent Swift Package Manager interfaces/libraries; use a matching full Xcode installation for package-based development.

## Coding Style & Naming Conventions

Use four-space indentation, `UpperCamelCase` type names, and `lowerCamelCase` members. Keep AppKit operations on `@MainActor`; move future sampling work off the UI thread. Preserve existing preference keys or provide a migration. No formatter or linter is configured.

## Testing Guidelines

There is no automated framework or coverage threshold configured. For UI changes, build and manually verify all six metrics across all three display modes, toggle recovery through SM, preference persistence after relaunch, and light/dark appearance. Network download stays above upload. For future collector logic, add focused tests under `Tests/MacSysMonitorTests/` and register a package test target before using `swift test`.

## Commit & Pull Request Guidelines

No Git history is available to establish existing conventions. Use concise imperative subjects, such as `Add network sampling`. PRs should describe behavior, validation, limitations, and related issues. Include screenshots for visual changes. Exclude generated build outputs.

## Performance & Security

Keep the default refresh interval at three seconds. Collectors are not implemented yet; never present synthetic readings as real data. Bound future history buffers and stop disabled collectors. Never commit signing keys or credentials; local ad-hoc signing is not public-release notarization.
