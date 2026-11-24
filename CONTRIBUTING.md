# Contributing to mac-sysmonitor

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
2. Find the `mac-sysmonitor` report whose date matches the crash. Select it to
   read the report or double-click it to open a separate window.
3. Choose **File → Reveal in Finder** to locate the `.ips` file on disk.
   [Apple’s guide to Console reports](https://support.apple.com/en-gu/guide/console/cnsl664be99a/mac)

To look for the file directly, press **Shift–Command–G** in Finder and open
`~/Library/Logs/DiagnosticReports`. If you need the system-wide folder, use
`/Library/Logs/DiagnosticReports`. Sort by date and look for a file named
`mac-sysmonitor` with the matching timestamp. You can also open the file as
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
Command Line Tools and build your checkout. Python 3 is needed only for the
optional shell-script tests below.

## Project layout

| Path | Contents |
| --- | --- |
| [Sources/MacSysMonitor/](Sources/MacSysMonitor/) | App lifecycle, preferences, indicator rendering, and uninstall flow |
| [Resources/](Resources/) | Bundle metadata, app icon, icon prompt, and README badges |
| [scripts/](scripts/) | Build, icon packaging, uninstall, and safety-check commands |
| [Tests/](Tests/) | Native removal checks and optional shell-script tests |
| `.build/`, `dist/` | Generated caches and app bundles excluded from Git |

## Build and test

The verified build uses `swiftc` directly. You can open [Package.swift](Package.swift) in Xcode
with an Apple Silicon destination, but the initial development machine had
inconsistent Swift Package Manager interfaces/libraries. Use a matching full Xcode
installation for that workflow.

Run these commands from the repository root. Quit any running copy before
launching a rebuild.

```sh
bash scripts/build-app.sh
open dist/mac-sysmonitor.app

# Native uninstall safety checks using temporary fixtures.
bash scripts/test-app-removal.sh

# Optional shell-script checks (Python 3).
python3 -m unittest discover -s Tests -p 'test_*.py'

# Check metadata and a built bundle.
plutil -lint Resources/Info.plist
codesign --verify --strict dist/mac-sysmonitor.app

# Regenerate .icns using macOS tools and a Swift fallback.
bash scripts/build-icon.sh
```

See the [master icon](Resources/AppIcon.png) and its [generation prompt](Resources/AppIcon-prompt.txt).

## Submit a change

1. Create a branch for your change and follow the [repository guidelines](AGENTS.md).
2. Run the relevant checks above. For UI changes, verify all six metrics in all
   three display modes, the **Save** action, recovery of hidden indicators via
   **SM**, saved preferences after relaunch, light and dark appearance, and
   network ordering with download above upload.
3. Commit with a concise imperative subject. Keep generated builds and
   credentials out of Git.
4. Open a pull request with the behavior change, validation performed, and
   known limitations. Include screenshots for visual changes.

## Publish the private repository

To publish on GitHub, review and commit your changes on `main`, then run
`bash scripts/publish-private.sh` from a checkout authenticated with `gh`.
The [publishing script](scripts/publish-private.sh) pushes committed changes only
to the verified private repository.
