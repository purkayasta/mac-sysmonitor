![SysMon app icon](Resources/readme-icon.png)

# SysMon — Your Mac, at a glance.

Made with Codex.

A small, native home for your Mac’s system stats. Right in the menu bar.

![macOS 13+, Apple Silicon, Swift 6+, in development](Resources/readme-badges.svg)

[Install](INSTALL.md#install-from-source) · [Settings](#-make-it-yours) · [Update](INSTALL.md#update) · [Uninstall](INSTALL.md#uninstall)

[Development setup](CONTRIBUTING.md#set-up-the-development-environment) · [Contributing](CONTRIBUTING.md#submit-a-change) · [Report a bug](CONTRIBUTING.md#report-a-bug) · [Contact](CONTACT.md)

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

## 🎛 Make it yours

Open the app from Applications or Launchpad to see all active settings. You can
also click or right-click **SM** or any metric and choose **Settings…**.

| Control | What it does |
| --- | --- |
| Show in menu bar | Show or hide each metric independently |
| Display mode | Choose **Text**, **Mini graph**, or **Text + mini graph** |
| Refresh interval | Choose **1, 2, 3, 5, 10, or 30 seconds**; default **3** |
| SM menu | Restore hidden metrics, open settings, quit, or uninstall |

Click **Save** in the settings window to apply your changes together. Closing
the window with unsaved edits offers **Save and Close**, **Cancel**, or
**Close Without Saving**; the app keeps running. Changes made
directly in the menu bar apply immediately. To stop the app, choose
**SM → Quit SysMon**. The refresh interval will control sampling once
collectors are implemented.

**Network layout:** download is on top, upload below. The current indicators use
empty states until real network measurements are connected.

### Follows your Mac

Menu bar indicators have transparent backgrounds. macOS chooses the foreground
and highlight treatment for its transparent, tinted, or opaque menu bar. The app
uses native light/dark appearance, system accent colors, semantic labels, and a
window material that supports desktop tinting. AppKit handles accessibility
contrast and transparency behavior; no custom theme needs configuring.

**macOS 13+ is the minimum supported version.** Native controls follow the
appearance of the macOS version you run.

### Build and verify

From the repository root:

```sh
bash scripts/build-app.sh
open dist/SysMon.app
```

Run `bash scripts/test.sh` for the Swift safety, integration, and native UI
checks. Allow more than one minute for its delayed-quit responsiveness test.
See the [contributor guide](CONTRIBUTING.md#build-and-test) for requirements,
coverage, and preview images.

## 🔎 Troubleshooting

- **Settings is closed.** Choose **SM → Settings…**, or launch the app again.
- **Only dashes or empty graphs.** Collectors are still in development.
- For build or launch issues, see the [installation guide](INSTALL.md#troubleshooting).
- After a crash, [find and read the macOS crash report](CONTRIBUTING.md#find-and-read-a-crash-report).

## 🚧 Next up

- [ ] CPU and memory collectors
- [ ] Swap, network, disk I/O, and supported GPU counters
- [ ] Live graphs with bounded history and disabled-collector shutdown
- [ ] CPU, memory, and energy profiling on Apple Silicon
- [ ] Signed GitHub releases, DMG packaging, and a Homebrew cask
