# Troubleshooting SysMon

[README](README.md) · [Installation](INSTALL.md) · [Contributing and bug reports](CONTRIBUTING.md) · [Contact](CONTACT.md)

## Settings or metrics are missing

Open **Settings…** from the menu bar, or launch SysMon again from Applications.
All metrics start hidden; the **SM** recovery menu lets you enable them.
Click **Save** to apply changes and close Settings. Closing with pending edits
offers Save, Cancel, or Discard.

## A reading says Measuring… or Unavailable

- **Measuring…** CPU and throughput collectors need a baseline. Wait one refresh
  interval; the default is three seconds.
- **Unavailable** means a counter failed or is unsupported. Open the metric menu
  for details. GPU utilization depends on statistics exposed by the driver.

Missing readings leave gaps in graphs; they do not represent measured zero usage.

## Understanding the readings

| Metric | What it measures |
| --- | --- |
| CPU | System-wide usage between samples |
| GPU | Busiest device’s reported utilization, where supported |
| RAM | Estimated used memory and physical capacity |
| Swap | Used and currently allocated swap |
| Network | Physical Ethernet/Wi-Fi download and upload rates |
| Disk I/O | Aggregated block-driver read and write rates |

Stacked labels use **U/T** for used/total, **D/U** for download/upload, and
**R/W** for read/write. Download appears above upload. Units scale in powers of 1024.

RAM estimates exclude reclaimable file-cache and purgeable pages, so they may
differ from Activity Monitor. Network rates include LAN traffic on physical
`en*` interfaces and exclude VPN/bridge interfaces to avoid double-counting.
Disk reads served entirely from memory cache can correctly show no disk I/O.
New or reset devices need a fresh baseline.

Hidden metrics stop sampling. Graphs retain up to 60 samples.

## Launch at Login does not work

Check **System Settings → General → Login Items** and confirm SysMon is allowed.
If saving the setting reports a registration error, follow the error’s route to
Login Items, check its state, and try again.

## Build or launch problems

- **Build fails:** check `swift --version`; Swift 6 or newer is required. If you
  have Xcode, select its toolchain in **Xcode → Settings → Locations → Command
  Line Tools**. See [installation requirements](INSTALL.md#install-from-source).
- **Package-based build fails:** use the direct [build script](scripts/build-app.sh).
  Package development requires a matching full Xcode installation.
- **A downloaded build is blocked:** use the [source installation](INSTALL.md#install-from-source).
  Local builds use ad-hoc signing; signed downloadable releases are planned.
- **An old version keeps appearing:** quit all copies before replacing the app,
  then launch the intended copy. See [updating SysMon](INSTALL.md#update).

## An update is waiting or needs recovery

Answer SysMon’s Save/Cancel/Discard quit dialog. The updater waits while your
decision is pending; Cancel leaves the app and installed bundle in place.

If replacement or startup fails, follow the reported recovery path. Keep staging
folders marked `.keep-for-recovery` until the previous copy has been restored or
the updated app has been verified. See the [update guide](INSTALL.md#update).

## The app crashes

[Find the matching macOS crash report](CONTRIBUTING.md#find-and-read-a-crash-report),
then [attach a reviewed copy](CONTRIBUTING.md#attach-the-report-to-the-issue) when
[reporting the bug](CONTRIBUTING.md#report-a-bug). Include your macOS version,
Mac model, app version, and steps to reproduce it.
