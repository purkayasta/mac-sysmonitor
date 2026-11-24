# SysMon Repository Guidelines

[README](README.md) · [Installation](INSTALL.md) · [Contributor guide](CONTRIBUTING.md) · [Report a bug](CONTRIBUTING.md#report-a-bug) · [Contact](CONTACT.md)

## Project Structure & Module Organization

`SysMon` is a dependency-free Swift/AppKit menu bar app for Apple Silicon, targeting macOS 13+. `Sources/SysMon/main.swift` owns app lifecycle, menus, and saved preferences; `StatusGraphic.swift` renders compact indicators. `Package.swift` defines the executable package. `Resources/` contains bundle metadata, the master icon, its generation prompt, and the packaged `.icns`. Build scripts live in `scripts/`; generated binaries, caches, and app bundles belong in ignored `.build/` and `dist/` directories. Swift fixture, integration, and AppKit lifecycle checks live in `Tests/`; no SwiftPM test target exists yet.

Use **SysMon — Your Mac, at a glance.** for the product name and tagline. Keep **Made with Codex.** in the README. The executable, package target, and app bundle are `SysMon`, `SysMon`, and `SysMon.app`. Keep the stable bundle identifier `dev.local.mac-sysmonitor` and persisted preference keys unless a migration is explicitly requested. The existing GitHub repository slug is `mac-sysmonitor`; app-name compatibility fallbacks have been removed.

`SettingsStore.swift` manages preferences, including optional macOS login-item registration; `SettingsWindowController.swift` manages pending edits, Save (apply and close), and Save/Cancel/Discard confirmation on close or quit. `AppUninstaller.swift` hands removal to a helper after quit; `AppRemoval.swift` validates bundle identity before removal. `scripts/install-built-app.swift` installs signed bundles and handles update recovery; `scripts/QuitRequest.swift` waits for a quit-event reply off the UI thread.

`SystemSampler.swift` owns actor-isolated sampling baselines; `NativeSystemCounters.swift` reads Mach, sysctl, and IOKit counters. `MetricReading.swift` formats readings and bounds graph history. `AppInstanceShutdown.swift` closes all matching SysMon instances during authorized uninstall, excluding its own helper and unrelated applications; it requests normal quit before a bounded force-quit fallback.

## Build, Test, and Development Commands

- `bash scripts/build-app.sh`: compile an optimized arm64 executable, package `dist/SysMon.app`, and apply a free local ad-hoc signature. Shows staged progress.
- `open dist/SysMon.app`: launch the menu bar app. Quit an existing copy before relaunching a rebuild.
- `bash scripts/update-app.sh`: update an existing `/Applications/SysMon.app`; use `--app dist/SysMon.app` for a development copy. A running app is asked to quit and then reopened; a closed app stays closed.
- `bash scripts/uninstall.sh --app /Applications/SysMon.app --purge`: move that copy to Trash and delete preferences after a successful move. Omit `--purge` to keep preferences; use `--dry-run` to preview. Shows staged progress.
- `bash scripts/build-icon.sh`: regenerate icon sizes and `.icns`; requires macOS image tools and Swift for its fallback.
- `bash scripts/test.sh`: run all Swift checks; requires a graphical macOS session and includes a 65-second delayed-quit responsiveness check.
- `codesign --verify --strict dist/SysMon.app`: verify the built bundle’s signature.
- `plutil -lint Resources/Info.plist`: validate bundle metadata.

Use the direct compiler build script as the baseline workflow. The initial machine has inconsistent Swift Package Manager interfaces/libraries; use a matching full Xcode installation for package-based development.

macOS 13 is the minimum deployment version, not a visual theme. Native AppKit controls follow the installed macOS appearance. Keep the deployment version consistent across `Package.swift`, `scripts/build-app.sh`, and `Resources/Info.plist`.

## Coding Style & Naming Conventions

Use four-space indentation, `UpperCamelCase` type names, and `lowerCamelCase` members. Keep AppKit operations on `@MainActor`; move future sampling work off the UI thread. Preserve existing preference keys or provide a migration. No formatter or linter is configured.

Use native AppKit controls, dialogs, semantic colors, and system fonts. Preserve template status images and accessibility labels. Saving Settings applies edits and closes the window. Closing Settings or quitting with pending edits must offer Save, Cancel, and Discard. Keep the optional Launch at Login setting synchronized with `SMAppService.mainApp`; surface registration failures and provide a route to System Settings Login Items. Keep blocking IPC, process waits, and future collection work off the UI thread. The updater must wait for the user's quit decision without expiring while a confirmation dialog is open; keep Apple Event waits off Swift's cooperative executor pool as well.

## Testing Guidelines

Run `bash scripts/test.sh` for the standalone Swift checks; there is no coverage threshold configured. For UI changes, build and manually verify all six metrics across all three display modes, toggle recovery through SM, preference persistence after relaunch, Launch at Login state, Save closing Settings, and light/dark appearance. Verify icon and direction-marker alignment at zero, unequal, measuring, and unavailable readings. Network download stays above upload. For future collector logic, add focused tests under `Tests/SysMonTests/` and register a package test target before using `swift test`.

All test code must be Swift. The suite runs six removal safety checks, 22 script integration cases, collector logic and native-counter smoke checks, multi-instance shutdown checks, settings close/quit decisions, native modal event handling, light/dark control bounds and alignment, and delayed-quit responsiveness. The delayed cancellation takes 65 seconds; allow more than one minute for the suite. Tests use isolated preferences, temporary bundles, explicitly launched helper apps, and mocked destructive/publishing commands. Keep tests independent of installed copies and real GitHub access. Preview images and lifecycle logs belong in `.build/`.

For UI or IPC changes, verify event-loop responsiveness and delayed cancellation, rather than claiming universal freedom from freezes. Tests must report completion explicitly so early native-process termination cannot silently skip checks.

## Commit & Pull Request Guidelines

Use concise imperative subjects, such as `Add network sampling`. PRs should describe behavior, validation, limitations, and related issues. Include screenshots for visual changes. Exclude generated build outputs. When publishing is requested, commit the intended changes before running `bash scripts/publish-private.sh`; it pushes committed `main` to the verified private repository and excludes uncommitted files.

## Performance & Security

Keep the default refresh interval at three seconds. All six collectors are implemented; never present synthetic readings as real data. Keep native reads off the main actor, limit histories to 60 samples, and stop disabled collectors. CPU and throughput need a baseline; report measuring or unavailable states accurately. Use actual elapsed time, 64-bit I/O counters, and per-device baselines to handle hot-plug and resets. GPU counters are driver-dependent. Never commit signing keys or credentials; local ad-hoc signing is not public-release notarization.

After explicit uninstall confirmation (or a Terminal uninstall command), close every matching SysMon instance before touching app files. Force-close copies that refuse normal quit, with that behavior disclosed to the user. Exclude the helper and unrelated apps; fail without deleting preferences if shutdown fails. Removing the selected bundle must still precede preference removal.

Update, install, and uninstall accept bundles named `SysMon.app` only and must validate their identity before replacement or removal. Preserve recovery files marked `.keep-for-recovery` when an update cannot finish. Keep generated outputs out of commits; if the user requests a clean `dist/`, verify builds in a temporary checkout and remove that temporary output afterward.
