![mac-sysmonitor app icon](Resources/readme-icon.png)

# mac-sysmonitor

A small, native home for your Mac’s system stats. Right in the menu bar.

![macOS 13+, Apple Silicon, Swift 6+, in development](Resources/readme-badges.svg)

[Install](#-install) · [Settings](#-make-it-yours) · [Uninstall](#-uninstall) · [Development](#-development)

> [!IMPORTANT]
> **Early development preview.** The settings window, menu bar indicators, display
> modes, and uninstall flow are implemented. **Live metric collection is still
> pending.** Dashes and empty graphs mean no data—not zero usage.
>
> There is no published DMG or Homebrew package yet. Installation currently means
> building from source. Intel Macs are not supported.

## ✨ What’s taking shape

| Metric | Planned readings | Display options available now |
| --- | --- | --- |
| CPU | Processor usage | Text · Mini graph · Both |
| GPU | GPU usage, where supported | Text · Mini graph · Both |
| RAM | Memory usage | Text · Mini graph · Both |
| Swap | Swap usage | Text · Mini graph · Both |
| Network | Download above upload | Text · Mini graph · Both |
| Disk I/O | Read and write rates | Text · Mini graph · Both |

Every metric has its own saved visibility and display settings. A shared refresh
interval defaults to **3 seconds**. Native Swift and AppKit keep the app focused;
there are no third-party runtime dependencies.

## 📦 Install

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

Wait for `Built .../dist/mac-sysmonitor.app`. The settings window opens on launch;
**SM** and enabled metric indicators appear in the menu bar. There is no Dock icon.

### 4. Keep it in Applications

```sh
open dist
```

Drag **mac-sysmonitor.app** into **Applications** in Finder. Quit the test copy,
then launch the Applications copy. You can also launch it from Launchpad if listed.
Keep the source folder if you want to rebuild later or use the uninstall script.

> [!NOTE]
> Local builds use free ad-hoc signing. They are not Developer ID signed or
> notarized. Signed downloadable releases and Homebrew distribution are planned.

## 🎛 Make it yours

Open the app from Applications or Launchpad to see all active settings. You can
also click or right-click **SM** or any metric and choose **Settings…**.

| Control | What it does |
| --- | --- |
| Show in menu bar | Show or hide each metric independently |
| Display mode | Choose **Text**, **Mini graph**, or **Text + mini graph** |
| Refresh interval | Choose **1, 2, 3, 5, 10, or 30 seconds**; default **3** |
| SM menu | Restore hidden metrics, open settings, quit, or uninstall |

Changes apply immediately and are saved automatically. Close the settings window
to keep the app running. To stop it, choose **SM → Quit mac-sysmonitor**.
The refresh interval will control sampling once collectors are implemented.

**Network layout:** download is on top, upload below. The current indicators use
empty states until real network measurements are connected.

### Follows your Mac

Menu bar indicators have transparent backgrounds. macOS chooses the foreground
and highlight treatment for its transparent, tinted, or opaque menu bar. The app
uses native light/dark appearance, system accent colors, semantic labels, and a
window material that supports desktop tinting. AppKit handles accessibility
contrast and transparency behavior; no custom theme needs configuring.

## 🔄 Update

1. Quit through **SM → Quit mac-sysmonitor**.
2. Get the latest source and run `bash scripts/build-app.sh`.
3. Run `open dist`, then drag the rebuilt app into Applications and choose **Replace**.
4. Launch the Applications copy. Your settings are kept.

## 🗑 Uninstall

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

Quit the app first. To remove the Applications copy:

```sh
bash scripts/uninstall.sh --app /Applications/mac-sysmonitor.app
```

Add `--purge` to remove saved settings too:

```sh
bash scripts/uninstall.sh --app /Applications/mac-sysmonitor.app --purge
```

For the copy built inside this project, omit `--app`:

```sh
bash scripts/uninstall.sh          # Keep settings
bash scripts/uninstall.sh --purge  # Also remove settings
```

Add **`--dry-run`** to preview changes. Use `--app "/full/path/mac-sysmonitor.app"`
for another location. Each run removes only that copy. If permission is denied,
move the app to Trash in Finder instead.

### From Finder

Quit the app, then move **mac-sysmonitor.app** from Applications to Trash. Remove
any extra copy in `dist/` too. This keeps preferences; to clear them after quitting:

```sh
defaults delete dev.local.mac-sysmonitor
```

A “domain not found” message means there were no saved settings to remove. You can
delete the source project folder afterward if you no longer need it.

## 🛠 Development

See [Repository Guidelines](AGENTS.md) for contributor conventions.

| Path | Contents |
| --- | --- |
| `Sources/MacSysMonitor/` | App lifecycle, settings, indicator rendering, and uninstall flow |
| `Resources/` | Bundle metadata, app icon, icon prompt, and README badges |
| `scripts/` | Build, icon packaging, uninstall, and safety-check commands |
| `Tests/` | Native removal checks and optional shell-script tests |
| `.build/`, `dist/` | Generated caches and app bundles; excluded from Git |

The verified build uses `swiftc` directly. You can open `Package.swift` in Xcode
with an Apple Silicon destination, but the initial development machine had
inconsistent Swift Package Manager interfaces/libraries. Use a matching full Xcode
installation for that workflow.

```sh
# Native uninstall safety checks; temporary fixtures only.
bash scripts/test-app-removal.sh

# Optional shell-uninstaller checks; these alone require Python 3.
python3 -m unittest discover -s Tests -p 'test_*.py'

# Check metadata and a built bundle.
plutil -lint Resources/Info.plist
codesign --verify --strict dist/mac-sysmonitor.app

# Regenerate .icns using macOS tools and a Swift fallback.
bash scripts/build-icon.sh
```

The icon master is `Resources/AppIcon.png`; its prompt is
`Resources/AppIcon-prompt.txt`. Never commit signing certificates, private keys,
or notarization credentials.

## 🔎 Troubleshooting

- **Settings is closed:** choose **SM → Settings…**, or launch the app again.
- **Only dashes or empty graphs:** collectors are not implemented yet.
- **Build fails:** check `swift --version`; with Xcode installed, select it under
  **Xcode → Settings → Locations → Command Line Tools**.
- **A downloaded build is blocked:** current builds are not Developer ID signed
  or notarized. Smooth downloadable installation is planned.
- **An old version keeps appearing:** quit all copies before replacing the app.


## 🚧 Next up

- [ ] CPU and memory collectors
- [ ] Swap, network, disk I/O, and supported GPU counters
- [ ] Live graphs with bounded history and disabled-collector shutdown
- [ ] CPU, memory, and energy profiling on Apple Silicon
- [ ] Signed GitHub releases, DMG packaging, and a Homebrew cask
