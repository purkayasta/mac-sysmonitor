# Contributing to SysMon

[README](README.md) · [Installation guide](INSTALL.md) · [Repository guidelines](AGENTS.md) · [Contact](CONTACT.md)

[Report a bug](#report-a-bug) · [Crash reports](#find-and-read-a-crash-report) · [Development setup](#set-up-the-development-environment) · [Build and test](#build-and-test) · [Submit a change](#submit-a-change) · [Publish](#publish-the-private-repository)

## Report a bug

Sign in to GitHub with access to this private repository. Search the
[existing issues](https://github.com/purkayasta/mac-sysmonitor/issues) for the
same problem, then open a [new issue](https://github.com/purkayasta/mac-sysmonitor/issues/new)
if needed. Give it a short title that names the symptom and include:

- Steps to reproduce it, what you expected, and what happened.
- Your macOS version, Mac model or chip, and app version. For a source build,
  include the commit hash if you know it.
- How often it happens and, for a crash, the approximate time and time zone.
- A screenshot, error message, or crash report when available.

### Find and read a crash report

1. Open **Console** from **Applications → Utilities**, then select **Crash Reports**
   in the sidebar.
2. Find the `SysMon` report whose date matches the crash. Select it to
   read the report or double-click it to open a separate window.
3. Choose **File → Reveal in Finder** to locate the `.ips` file on disk.
   [Apple’s guide to Console reports](https://support.apple.com/en-gu/guide/console/cnsl664be99a/mac)

To look for the file directly, press **Shift–Command–G** in Finder and open
`~/Library/Logs/DiagnosticReports`. If you need the system-wide folder, use
`/Library/Logs/DiagnosticReports`. Sort by date and look for a file named
`SysMon` with the matching timestamp. You can also open the file as
plain text in TextEdit.

### Attach the report to the issue

Make a copy of the matching report. Review it and redact personal details such
as your username, home-directory paths, or sensitive file names before
uploading. Keep technical details such as the exception type and backtrace.
Save the redacted copy as a plain-text `.txt` file or compress it as a `.zip`,
then drag it into the issue description or a comment.
[GitHub’s guide to attachments](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files)

If no crash report appears, still file the issue. Include the approximate time
and any related messages from Console around that time.
[Apple’s guide to diagnostic logs](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)

## Set up the development environment

Use an Apple Silicon Mac with macOS 13 or newer and Swift 6 or newer. Follow the
[installation guide](INSTALL.md#install-from-source) to set up Xcode or its
Command Line Tools and build your checkout. All tests use Swift; Python is not required.

## Project layout

| Path | Contents |
| --- | --- |
| [Sources/SysMon/](Sources/SysMon/) | App lifecycle, preferences, indicator rendering, and uninstall flow |
| [Resources/](Resources/) | Bundle metadata, app icon, icon prompt, and README badges |
| [scripts/](scripts/) | Build, update/recovery, icon packaging, uninstall, publishing, and test commands |
| [Tests/](Tests/) | Standalone Swift removal, script integration, settings, appearance, and responsiveness checks |
| `.build/`, `dist/` | Generated caches and app bundles excluded from Git |

## Build and test

The verified build uses `swiftc` directly. You can open [Package.swift](Package.swift) in Xcode
with an Apple Silicon destination, but the initial development machine had
inconsistent Swift Package Manager interfaces/libraries. Use a matching full Xcode
installation for that workflow.

Run these commands from the repository root. Quit any running copy before
launching a rebuild. Use the [update command](INSTALL.md#update) to replace and
restart a running copy.

```sh
bash scripts/build-app.sh
open dist/SysMon.app

# Swift removal, installer, uninstall, publishing, and AppKit lifecycle checks.
bash scripts/test.sh

# Check metadata and a built bundle.
plutil -lint Resources/Info.plist
codesign --verify --strict dist/SysMon.app

# Regenerate .icns using macOS tools and a Swift fallback.
bash scripts/build-icon.sh
```

See the [master icon](Resources/AppIcon.png) and its [generation prompt](Resources/AppIcon-prompt.txt).

The test suite uses temporary app bundles and mocked publishing/removal commands;
it does not contact GitHub, trash installed apps, or change your app preferences.
AppKit lifecycle checks require a logged-in graphical macOS session. They wait
65 seconds on a delayed quit response to guard against premature update cancellation
and check that the main actor stays responsive. Native modal-dialog checks also
verify that AppKit continues processing events. Light/dark settings and indicator
previews are written to `.build/` for visual inspection.

The current suite has six removal safety checks and 22 script integration cases,
plus collector and native lifecycle checks. All test code is Swift; `Package.swift` has no test
target, so use `bash scripts/test.sh` rather than `swift test`. For a focused
removal check, run `bash scripts/test-app-removal.sh`.

Inspect `.build/settings-light.png`, `.build/settings-dark.png`, and the matching
`indicators-*.png` previews for visual changes. The async lifecycle output is
saved in `.build/lifecycle-test-output.log`. A passing responsiveness check covers
the exercised path; report any additional manual checks or untested failure paths.

Use native AppKit controls, semantic colors, system fonts, and accessibility
labels. Keep the settings layout stable in both appearances. Saving applies edits and closes Settings. Pending edits must survive Cancel when
closing or quitting. Keep blocking IPC and process waits off
the UI thread, and avoid blocking Swift's cooperative executor with Apple Event
reply waits. Preserve the updater's wait for an explicit quit decision.

Collector tests live in `Tests/SysMonTests/CollectorTests.swift` and exercise
counter rollover/reset, device changes, actual elapsed time, zero readings,
disabled collectors, unavailable counters, bounded history, and slow sampling
without main-actor stalls. Native smoke checks read all six collectors on the
current Mac; a driver can legitimately omit GPU utilization counters.

Uninstall shutdown tests cover multiple copies, exclusion of the helper and
unrelated apps, graceful and forced exits, newly appearing copies, cancellation,
and failure. Two explicitly spawned AppKit fixtures also refuse normal quit so
the force-close path is verified without touching installed SysMon instances.

The stable bundle identifier and preference domain are `dev.local.mac-sysmonitor`;
the source target, executable, and app bundle are `SysMon`, `SysMon`, and `SysMon.app`.
macOS 13 is the deployment minimum; native controls use the installed OS appearance.
Change deployment requirements together in `Package.swift`, `scripts/build-app.sh`,
and `Resources/Info.plist`.

## Submit a change

1. Create a branch for your change and follow the [repository guidelines](AGENTS.md).
2. Run the relevant checks above. For UI changes, verify all six metrics in all
   three display modes, the **Save** action, recovery of hidden indicators via
   the **SM** fallback when all metrics are hidden, saved preferences after
   relaunch, light and dark appearance, compact icon alignment at zero and unequal
   readings, and network ordering with download above upload. Verify Save closes
   Settings; exercise Save, Cancel, and Discard for pending edits on close and quit.
3. Commit with a concise imperative subject. Keep generated builds and
   credentials out of Git.
4. Open a pull request with the behavior change, validation performed, and
   known limitations. Include screenshots for visual changes.

## Publish the private repository

To publish on GitHub, review and commit your changes on `main`, then run
`bash scripts/publish-private.sh` from a checkout authenticated with `gh`.
The [publishing script](scripts/publish-private.sh) pushes committed changes only
to the verified private repository.

It expects the current branch to be `main`, an authenticated `gh` session, and
the existing repository slug `mac-sysmonitor`. Check `git status` and review the
diff before committing; untracked or uncommitted work is excluded from the push.
The script checks repository visibility and origin push URLs before sending
`main`. It does not publish a downloadable app or notarize a build.
