# Install SysMon

[README](README.md) · [App settings](README.md#-make-it-yours) · [Development setup](CONTRIBUTING.md#set-up-the-development-environment) · [Report a bug](CONTRIBUTING.md#report-a-bug) · [Contact](CONTACT.md)

[Install from source](#install-from-source) · [Update](#update) · [Uninstall](#uninstall) · [Troubleshooting](#troubleshooting)

## Install from source

### 1. Get the tools

You need an **Apple Silicon Mac**, **macOS 13 or newer**, and **Swift 6 or newer**.
Install [Xcode](https://developer.apple.com/xcode/resources/) from the Mac App Store,
then open it once to finish setup. A compatible Command Line Tools installation
also works with the build script. No paid Apple Developer membership is needed
for local builds. **Python is not required.**

macOS 13 is the minimum deployment version. SysMon uses native AppKit controls
that follow your installed macOS appearance. The Xcode or Command Line Tools
version you use must support Swift 6 and your development machine's macOS version.

### 2. Open the project folder in Terminal

Download and extract the source, or use your existing checkout. In Terminal, type
`cd` followed by a space, drag the project folder from Finder into Terminal, and
press Return. You should be in the folder containing `Package.swift` and `scripts/`.

Run the commands below from that folder.

### 3. Build and try it

```sh
bash scripts/build-app.sh
open dist/SysMon.app
```

Wait for `Built .../dist/SysMon.app`. The settings window opens on launch,
and all metric checkboxes start unchecked. The **SM** recovery item appears
until you enable metrics in Settings.

### 4. Keep it in Applications

```sh
open dist
```

Quit the test copy using the combined menu bar indicator → **Quit SysMon**, then drag **SysMon.app** into
**Applications** in Finder and launch that copy. You can also launch it from Launchpad if listed.
Keep the source folder if you want to [update later](#update) or use the
[Terminal uninstaller](#from-terminal).

> [!NOTE]
> Local builds use free ad-hoc signing. They are not Developer ID signed or
> notarized. Signed downloadable releases and Homebrew distribution are planned.

## Update

Get the latest source, then run the `scripts/update-app.sh` shell script from
the project folder. The script wraps the build and safe replacement steps in
`scripts/build-app.sh --update`.

```sh
bash scripts/update-app.sh
```

With no options, it updates `/Applications/SysMon.app` and keeps saved settings.
Use `--app APP_PATH` to update a copy in another location. The script also accepts
`--help` to print its usage.

The destination must already exist and be named `SysMon.app`. For a fresh
installation, follow [Build and try it](#3-build-and-try-it) instead.

```sh
bash scripts/update-app.sh --app dist/SysMon.app
```

The command It verifies the new bundle before asking a running copy to
quit. Builds with the save-on-quit prompt let you save or discard pending edits,
or cancel the update. If the app was open, the command reopens it from the same
location. If startup fails, it tries to restore the previous copy and reports its location
if recovery needs your help. The updater also opens SysMon after replacing a copy
that was closed, so the updated indicators become visible immediately.

The command waits for your answer to the quit dialog without a time limit.
Choosing Cancel leaves the running app and installed bundle in place.
Keep any staging folder whose error message identifies it as the previous-copy
recovery location until you have restored or verified the app.

## Uninstall

### From the app — easiest

1. Click or right-click any metric (or **SM** if all metrics are hidden).
2. Choose **Uninstall SysMon…**, also available in the settings window.
3. Optionally check **Also remove saved settings**.
4. Choose **Move to Trash**, or **Cancel** to keep the app.

After confirmation, the app quits and its helper closes every running SysMon
instance. Copies that refuse a normal quit are force-closed after a short wait;
their unsaved settings may be discarded. The helper moves only the selected
bundle to Trash. Other app copies, source files, and build caches stay on disk.
Settings are kept unless you select their removal. If any instance cannot be
stopped or the move fails, an error is shown and your settings are kept.

### From Terminal

To close all running SysMon instances and move the Applications copy to Trash:

```sh
bash scripts/uninstall.sh --app /Applications/SysMon.app
```

Add `--purge` to remove saved settings after the app moves to Trash:

```sh
bash scripts/uninstall.sh --app /Applications/SysMon.app --purge
```

For the copy built inside this project, omit `--app`:

```sh
bash scripts/uninstall.sh          # Keep settings
bash scripts/uninstall.sh --purge  # Also remove settings
```

Add **`--dry-run`** to preview changes. Use `--app "/full/path/SysMon.app"`
for another location. Each run moves only that copy. The command uses the Swift
toolchain from the build instructions. You can also move the app to Trash in Finder.

The Terminal command It also force-closes instances that refuse to quit. Running it
authorizes discarding their pending settings; `--dry-run` describes the actions
without stopping processes or removing files.

The app path must be an actual `SysMon.app` directory; symlinks and unrelated
bundles are rejected. If that copy is already absent, the command exits without
deleting preferences, including when `--purge` is supplied. Use the preferences
command below to clear settings after manually removing the app.

### From Finder

Quit the app, then move **SysMon.app** from Applications to Trash. Remove
any extra copy in `dist/` too. After quitting, you can clear saved preferences with
this command.

```sh
defaults delete dev.local.mac-sysmonitor
```

`dev.local.mac-sysmonitor` is SysMon's stable bundle identifier and preferences
domain. It is independent of the visible app name.

A “domain not found” message means there were no saved settings to remove. You can
delete the source project folder afterward if you no longer need it.

### Clean generated files

After quitting SysMon, you can delete `dist/` in Finder to remove generated app
bundles. This leaves source files, `.build/` caches, and saved preferences in place.
The next `bash scripts/build-app.sh` recreates `dist/SysMon.app`. Moving an app to
Trash is reversible until you empty Trash or permanently delete that item.

## Troubleshooting

- **Build fails.** Check `swift --version`. If you have Xcode installed, select
  its toolchain in **Xcode → Settings → Locations → Command Line Tools**.
- **A downloaded build is blocked.** Use the source build instructions above.
  Signed downloadable releases are planned.
- **An old version keeps appearing.** Quit all copies before replacing the app.
- **The update waits for quit.** Answer the app's Save/Cancel/Discard dialog.
  The updater keeps waiting while that decision is pending.
- **The app crashes.** [Find and read the crash report](CONTRIBUTING.md#find-and-read-a-crash-report),
  then [attach it to a GitHub issue](CONTRIBUTING.md#attach-the-report-to-the-issue).
