# Install mac-sysmonitor

[README](README.md) · [App settings](README.md#-make-it-yours) · [Development setup](CONTRIBUTING.md#set-up-the-development-environment) · [Report a bug](CONTRIBUTING.md#report-a-bug) · [Contact](CONTACT.md)

[Install from source](#install-from-source) · [Update](#update) · [Uninstall](#uninstall) · [Troubleshooting](#troubleshooting)

## Install from source

### 1. Get the tools

You need an **Apple Silicon Mac**, **macOS 13 or newer**, and **Swift 6 or newer**.
Install [Xcode](https://developer.apple.com/xcode/resources/) from the Mac App Store,
then open it once to finish setup. A compatible Command Line Tools installation
also works with the build script. No paid Apple Developer membership is needed
for local builds. **Python is not required.**

### 2. Open the project folder in Terminal

Download and extract the source, or use your existing checkout. In Terminal, type
`cd` followed by a space, drag the project folder from Finder into Terminal, and
press Return. You should be in the folder containing `Package.swift` and `scripts/`.

Run the commands below from that folder.

### 3. Build and try it

```sh
bash scripts/build-app.sh
open dist/mac-sysmonitor.app
```

Wait for `Built .../dist/mac-sysmonitor.app`. The settings window opens on launch,
and **SM** and enabled metric indicators appear in the menu bar.

### 4. Keep it in Applications

```sh
open dist
```

Drag **mac-sysmonitor.app** into **Applications** in Finder. Quit the test copy,
then launch the Applications copy. You can also launch it from Launchpad if listed.
Keep the source folder if you want to [update later](#update) or use the
[Terminal uninstaller](#from-terminal).

> [!NOTE]
> Local builds use free ad-hoc signing. They are not Developer ID signed or
> notarized. Signed downloadable releases and Homebrew distribution are planned.

## Update

1. Quit through **SM → Quit mac-sysmonitor**.
2. Get the latest source and run `bash scripts/build-app.sh`.
3. Run `open dist`, then drag the rebuilt app into Applications and choose **Replace**.
4. Launch the Applications copy. Your settings are kept.

## Uninstall

### From the app — easiest

1. Click or right-click **SM** or any metric.
2. Choose **Uninstall mac-sysmonitor…**, also available in the settings window.
3. Optionally check **Also remove saved settings**.
4. Choose **Move to Trash**, or **Cancel** to keep the app.

The running app copy moves to Trash, then quits. Other copies, source files, and
build caches stay in place. Settings are kept unless you select their removal.
If removal fails, the app stays open and settings are preserved. Quit any other
running copies before uninstalling.

### From Terminal

Quit the app first. To move the Applications copy to Trash:

```sh
bash scripts/uninstall.sh --app /Applications/mac-sysmonitor.app
```

Add `--purge` to remove saved settings after the app moves to Trash:

```sh
bash scripts/uninstall.sh --app /Applications/mac-sysmonitor.app --purge
```

For the copy built inside this project, omit `--app`:

```sh
bash scripts/uninstall.sh          # Keep settings
bash scripts/uninstall.sh --purge  # Also remove settings
```

Add **`--dry-run`** to preview changes. Use `--app "/full/path/mac-sysmonitor.app"`
for another location. Each run moves only that copy. The command uses the Swift
toolchain from the build instructions. You can also move the app to Trash in Finder.

### From Finder

Quit the app, then move **mac-sysmonitor.app** from Applications to Trash. Remove
any extra copy in `dist/` too. After quitting, you can clear saved preferences with
this command.

```sh
defaults delete dev.local.mac-sysmonitor
```

A “domain not found” message means there were no saved settings to remove. You can
delete the source project folder afterward if you no longer need it.

## Troubleshooting

- **Build fails.** Check `swift --version`. If you have Xcode installed, select
  its toolchain in **Xcode → Settings → Locations → Command Line Tools**.
- **A downloaded build is blocked.** Use the source build instructions above.
  Signed downloadable releases are planned.
- **An old version keeps appearing.** Quit all copies before replacing the app.
- **The app crashes.** [Find and read the crash report](CONTRIBUTING.md#find-and-read-a-crash-report),
  then [attach it to a GitHub issue](CONTRIBUTING.md#attach-the-report-to-the-issue).
