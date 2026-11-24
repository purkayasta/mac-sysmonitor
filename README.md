![SysMon app icon](Resources/readme-icon.png)

# SysMon — Your Mac, at a glance.

Made with Codex.

A small, native home for your Mac’s system stats. Right in the menu bar.

![macOS 13+, Apple Silicon, Swift 6+, in development](Resources/readme-badges.svg)

[Install](INSTALL.md#install-from-source) · [Settings](#-make-it-yours) · [Update](INSTALL.md#update) · [Uninstall](INSTALL.md#uninstall)

[Development setup](CONTRIBUTING.md#set-up-the-development-environment) · [Contributing](CONTRIBUTING.md#submit-a-change) · [Report a bug](CONTRIBUTING.md#report-a-bug) · [Contact](CONTACT.md)

> [!IMPORTANT]
> **Early development preview.** CPU, GPU, memory, swap, network, and disk collectors
> now feed live menu bar readings and graphs. A collector starts with **Measuring…**
> while establishing its baseline. **Unavailable** reports a failed or unsupported
> counter; a dash never represents measured zero usage.
>
> There is no published DMG or Homebrew package yet. Installation currently means
> building from source. Intel Macs are not supported.

## ✨ Live metrics

| Metric | Readings | Display options |
| --- | --- | --- |
| CPU | System-wide usage between samples | Text · Mini graph · Both |
| GPU | Busiest device's reported utilization, where exposed by the driver | Text · Mini graph · Both |
| RAM | Estimated used memory and physical capacity | Text · Mini graph · Both |
| Swap | Used and currently allocated swap | Text · Mini graph · Both |
| Network | Physical Ethernet/Wi-Fi receive and transmit rates | Text · Mini graph · Both |
| Disk I/O | Aggregated block-driver read and write rates | Text · Mini graph · Both |

Every metric has its own saved visibility and display settings. All six metrics
start hidden by default; use the **SM** recovery item to enable the ones you want.
The shared refresh interval defaults to **3 seconds**. Native Swift and AppKit keep the app focused;
there are no third-party runtime dependencies.

Collection runs in a background actor. Hidden metrics stop sampling, and each
graph retains at most 60 samples. Network and disk rates use 64-bit byte counters
and actual elapsed time; new or reset devices establish a fresh baseline.
Readouts use compact B, KB, MB, GB, and TB units (scaled in powers of 1024).

GPU readings depend on the driver's IOKit statistics. RAM estimates exclude
reclaimable file-cache and purgeable pages; they may differ from Activity Monitor.
Network rates aggregate physical `en*` interfaces, including LAN traffic, and
exclude VPN/bridge interfaces to avoid double-counting. Disk rates reflect driver
I/O, so a read served entirely from memory cache can correctly report no disk I/O.

## 🎛 Make it yours

Open the app from Applications or Launchpad to see all active settings. You can
click the combined menu bar indicator and use a metric submenu to open its settings.

| Control | What it does |
| --- | --- |
| Show in menu bar | Show or hide each metric independently |
| Display mode | Choose **Text**, **Mini graph**, or **Text + mini graph** |
| Refresh interval | Choose **1, 2, 3, 5, 10, or 30 seconds**; default **3** |
| Launch at Login | Optionally start SysMon when you sign in; off by default |
| Metric menu | Open settings, quit, or uninstall |

Click **Save** in the settings window to apply your changes and close the window.
Closing with unsaved edits offers **Save and Close**, **Cancel**, or
**Close Without Saving**; the app keeps running. Launch at Login uses the native
macOS login item and can also be managed in **System Settings → General → Login Items**.
Changes made
directly in the menu bar apply immediately. To stop the app, choose
the combined menu bar item → **Quit SysMon**. The refresh interval controls live sampling.

If all metrics are hidden, **SM** appears as the recovery indicator. Use its menu
to restore metrics through Settings. Metrics share one menu bar item, with subtle dividers between them.

**Menu bar icons:** native symbols identify each metric; network readings use
aligned download/upload arrows. Compact values include a space before KB/MB/GB units.
Hover or open a metric for its full name and details. Stacked readings are centered.
**RAM layout:** used memory is on top, physical capacity below, without extra labels.
**Compact labels:** U = used, T = total, D = download, U = upload, R = read,
W = write. Each pair is stacked and aligned. Unavailable samples leave gaps in graphs instead of fabricated readings.

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

- **Settings is closed.** Choose **any metric → Settings…**, or launch the app again.
- **Measuring…** CPU and rate collectors need two samples; wait one refresh interval.
- **Unavailable.** Open the metric menu for the specific counter failure. GPU
  utilization can be unavailable when the driver does not expose it.
- For build or launch issues, see the [installation guide](INSTALL.md#troubleshooting).
- After a crash, [find and read the macOS crash report](CONTRIBUTING.md#find-and-read-a-crash-report).

## 🚧 Next up

- [x] CPU and memory collectors
- [x] Swap, network, disk I/O, and supported GPU counters
- [x] Live graphs with bounded history and disabled-collector shutdown
- [ ] CPU, memory, and energy profiling on Apple Silicon
- [ ] Signed GitHub releases, DMG packaging, and a Homebrew cask
