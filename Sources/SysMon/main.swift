import AppKit
import Darwin
import ServiceManagement

#if !arch(arm64)
#error("SysMon supports Apple Silicon (arm64) only.")
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private var statusItem: NSStatusItem?
    private var metricItems: [Metric: NSStatusItem] = [:]
    private var metricMenuItems: [Metric: NSMenuItem] = [:]
    private let intervalMenu = NSMenu()
    private var settingsController: SettingsWindowController?
    private var uninstallChannel: FileHandle?
    private let sampler = SystemSampler()
    private var samplingTask: Task<Void, Never>?
    private var readings: [Metric: MetricReading] = [:]
    private var histories: [Metric: MetricHistory] = [:]
    private var lastSampleTime: Date?
    private var samplingConfiguration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        for metric in Metric.allCases {
            updateIndicator(for: metric)
        }
        updateRecoveryItem()
        startSampling()
        showSettings()
        DispatchQueue.main.async { [weak self] in self?.reportUpdateReady() }
    }

    private func updateRecoveryItem() {
        guard metricItems.isEmpty else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        // Keep a route back to Settings when the last metric is hidden.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "SM"
        item.button?.toolTip = "SysMon — Your Mac, at a glance."
        item.button?.setAccessibilityLabel("SysMon, all metrics hidden")
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.menu = makeMenu()
        statusItem = item
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if uninstallChannel != nil { return .terminateNow }
        return settingsController?.confirmQuit() == false ? .terminateCancel : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        samplingTask?.cancel()
    }

    private func startSampling() {
        samplingTask?.cancel()
        samplingConfiguration += 1
        let configuration = samplingConfiguration
        let enabled = Set(Metric.allCases.filter { settings.isEnabled($0) })
        readings = readings.filter { enabled.contains($0.key) }
        histories = histories.filter { enabled.contains($0.key) }
        guard !enabled.isEmpty else {
            // Reset baselines when everything is disabled, without reading counters.
            let sampler = sampler
            samplingTask = Task { _ = await sampler.sample(enabled: [], configuration: configuration) }
            return
        }
        let seconds = settings.interval
        let sampler = sampler
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                let samples = await sampler.sample(enabled: enabled, configuration: configuration)
                guard !Task.isCancelled else { return }
                self?.receive(samples)
                do { try await Task.sleep(for: .seconds(seconds)) }
                catch { return }
            }
        }
    }

    private func receive(_ samples: [Metric: MetricReading]) {
        lastSampleTime = Date()
        for (metric, reading) in samples {
            readings[metric] = reading
            histories[metric, default: MetricHistory()].append(reading, for: metric)
            refreshMetricDisplay(metric)
        }
    }

    private func reportUpdateReady() {
        guard let path = ProcessInfo.processInfo.environment["SYSMON_UPDATE_READY_PATH"] else { return }
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        guard url.lastPathComponent == ".update-ready",
              directory.lastPathComponent.hasPrefix(".SysMon."),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent(".keep-for-recovery").path) else { return }
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try? file.write(contentsOf: Data(String(ProcessInfo.processInfo.processIdentifier).utf8))
    }

    @objc private func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(settings: settings) { [weak self] changes in
                self?.applySettings(changes)
            } onUninstall: { [weak self] in
                self?.uninstall()
            }
        }
        settingsController?.refresh()
        settingsController?.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    private func applySettings(_ changes: SettingsChanges) {
        var changes = changes
        if let launchAtLogin = changes.launchAtLogin {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                settings.setLaunchAtLogin(launchAtLogin)
            } catch {
                changes.launchAtLogin = nil
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Could not change Login Item"
                alert.informativeText = "\(error.localizedDescription)\n\nYou can manage SysMon in System Settings → General → Login Items."
                alert.addButton(withTitle: "Open Login Items")
                alert.addButton(withTitle: "OK")
                if alert.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        let applied = settings.apply(changes)
        for metric in Metric.allCases where applied.visibility[metric] != nil || applied.modes[metric] != nil {
            metricMenuItems[metric]?.submenu = makeMetricMenu(metric)
            updateIndicator(for: metric)
        }
        updateRecoveryItem()
        if let seconds = applied.interval {
            for option in intervalMenu.items {
                option.state = option.tag == seconds ? .on : .off
            }
        }
        if !applied.visibility.isEmpty || applied.interval != nil { startSampling() }
        settingsController?.refresh()
    }

    private func makeSettingsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        item.target = self
        return item
    }

    private func makeMenu() -> NSMenu {
        intervalMenu.removeAllItems()
        let menu = NSMenu()
        let heading = NSMenuItem(title: "SysMon", action: nil, keyEquivalent: "")
        menu.addItem(heading)
        menu.addItem(makeSettingsItem())
        let notice = NSMenuItem(
            title: "Live system metrics",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(notice)
        menu.addItem(.separator())

        for metric in Metric.allCases {
            let item = NSMenuItem(title: metric.title, action: nil, keyEquivalent: "")
            item.submenu = makeMetricMenu(metric)
            menu.addItem(item)
            metricMenuItems[metric] = item
        }

        menu.addItem(.separator())
        let intervalItem = NSMenuItem(title: "Refresh interval", action: nil, keyEquivalent: "")
        let selectedInterval = settings.interval
        for seconds in SettingsStore.intervals {
            let option = NSMenuItem(
                title: "\(seconds) \(seconds == 1 ? "second" : "seconds")",
                action: #selector(changeRefreshInterval(_:)),
                keyEquivalent: ""
            )
            option.target = self
            option.tag = seconds
            option.state = selectedInterval == seconds ? .on : .off
            intervalMenu.addItem(option)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)
        menu.addItem(.separator())
        menu.addItem(makeUninstallItem())
        menu.addItem(makeQuitItem())
        return menu
    }

    @objc private func toggleMetric(_ sender: NSMenuItem) {
        guard let metric = sender.representedObject as? Metric else { return }
        applySettings(SettingsChanges(visibility: [metric: !settings.isEnabled(metric)]))
    }

    private func makeMetricMenu(_ metric: Metric) -> NSMenu {
        let menu = NSMenu(title: metric.title)
        menu.addItem(NSMenuItem(title: metric.title, action: nil, keyEquivalent: ""))
        for index in 0..<3 {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.tag = 1000 + index
            menu.addItem(item)
        }
        updateReadout(in: menu, metric: metric)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Show in menu bar", action: #selector(toggleMetric(_:)), keyEquivalent: "")
        toggle.target = self
        toggle.representedObject = metric
        toggle.state = settings.isEnabled(metric) ? .on : .off
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Display", action: nil, keyEquivalent: ""))
        let selectedMode = settings.displayMode(for: metric)
        for mode in DisplayMode.allCases {
            let option = NSMenuItem(title: mode.title, action: #selector(changeDisplayMode(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = (metric, mode)
            option.state = selectedMode == mode ? .on : .off
            menu.addItem(option)
        }
        menu.addItem(.separator())
        menu.addItem(makeSettingsItem())
        menu.addItem(makeUninstallItem())
        menu.addItem(makeQuitItem())
        return menu
    }

    private func makeQuitItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Quit SysMon", action: #selector(quitApp), keyEquivalent: "q")
        item.target = self
        return item
    }

    private func makeUninstallItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Uninstall SysMon…", action: #selector(uninstallApp), keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func uninstallApp() {
        // Present the confirmation after menu tracking ends.
        DispatchQueue.main.async { [weak self] in
            self?.uninstall()
        }
    }

    private func uninstall() {
        guard uninstallChannel == nil, let channel = AppUninstaller.confirmAndPrepare() else { return }
        uninstallChannel = channel
        NSApplication.shared.terminate(nil)
    }

    @objc private func changeDisplayMode(_ sender: NSMenuItem) {
        guard let (metric, mode) = sender.representedObject as? (Metric, DisplayMode) else { return }
        applySettings(SettingsChanges(modes: [metric: mode]))
    }

    private func updateIndicator(for metric: Metric) {
        guard settings.isEnabled(metric) else {
            if let item = metricItems.removeValue(forKey: metric) {
                NSStatusBar.system.removeStatusItem(item)
            }
            return
        }
        let item: NSStatusItem
        if let existing = metricItems[metric] {
            item = existing
        } else {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            metricItems[metric] = item
            item.button?.title = ""
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.appearance = nil
            item.button?.contentTintColor = nil
        }
        item.menu = makeMetricMenu(metric)
        refreshMetricDisplay(metric)
    }

    private func refreshMetricDisplay(_ metric: Metric) {
        let mode = settings.displayMode(for: metric)
        let reading = readings[metric] ?? .measuring
        let detail = reading.lines(for: metric).joined(separator: ", ")
        let item = metricItems[metric]
        let image = StatusGraphic.image(metric: metric, mode: mode, reading: reading,
                                        history: histories[metric] ?? MetricHistory())
        item?.button?.image = image
        item?.button?.imagePosition = .imageOnly
        item?.button?.imageScaling = .scaleNone
        // Keep just one point of button padding per side; retain the full click height.
        item?.length = max(18, ceil(image.size.width) + 2)
        item?.button?.toolTip = "\(metric.title) · \(detail)"
        item?.button?.setAccessibilityLabel("\(metric.title), \(detail), \(mode.title)")
        if let menu = item?.menu { updateReadout(in: menu, metric: metric) }
        if let menu = metricMenuItems[metric]?.submenu { updateReadout(in: menu, metric: metric) }
    }

    private func updateReadout(in menu: NSMenu, metric: Metric) {
        let enabled = settings.isEnabled(metric)
        var lines = enabled ? (readings[metric] ?? .measuring).lines(for: metric) : ["Collection paused · hidden from menu bar"]
        if enabled, readings[metric]?.state == .available, let lastSampleTime {
            lines.append("Updated \(lastSampleTime.formatted(date: .omitted, time: .standard))")
        }
        for index in 0..<3 {
            let item = menu.item(withTag: 1000 + index)
            item?.isHidden = index >= lines.count
            if index < lines.count { item?.title = lines[index] }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func changeRefreshInterval(_ sender: NSMenuItem) {
        applySettings(SettingsChanges(interval: sender.tag))
    }
}

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == AppUninstaller.finishArgument {
    // Keep AppKit's event loop alive while the helper waits asynchronously for
    // other copies to exit. This also refreshes NSRunningApplication state.
    let helperApp = NSApplication.shared
    helperApp.setActivationPolicy(.prohibited)
    Task { @MainActor in exit(await AppUninstaller.finishAfterQuit()) }
    helperApp.run()
    exit(EXIT_FAILURE)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
