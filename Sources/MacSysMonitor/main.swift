import AppKit

#if !arch(arm64)
#error("mac-sysmonitor supports Apple Silicon (arm64) only.")
#endif

enum Metric: String, CaseIterable {
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "RAM"
    case swap = "Swap"
    case network = "Network speed"
    case disk = "Disk I/O"

    var preferenceKey: String { "metric.\(rawValue).enabled" }
    var displayModeKey: String { "metric.\(rawValue).displayMode" }

    var shortName: String {
        switch self {
        case .memory: "RAM"
        case .network: "NET"
        case .disk: "DISK"
        default: rawValue
        }
    }
}

enum DisplayMode: String, CaseIterable {
    case text = "Text"
    case graph = "Mini graph"
    case combined = "Text + mini graph"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var metricItems: [Metric: NSStatusItem] = [:]
    private var settingsController: SettingsWindowController?
    private let refreshIntervalKey = "refreshIntervalSeconds"
    private let refreshIntervals = [1, 2, 3, 5, 10, 30]

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: Dictionary(
            uniqueKeysWithValues: Metric.allCases.map { ($0.preferenceKey, true) }
        ))
        UserDefaults.standard.register(defaults: [refreshIntervalKey: 3])
        for metric in Metric.allCases {
            UserDefaults.standard.register(defaults: [metric.displayModeKey: DisplayMode.text.rawValue])
        }
        if !refreshIntervals.contains(UserDefaults.standard.integer(forKey: refreshIntervalKey)) {
            UserDefaults.standard.set(3, forKey: refreshIntervalKey)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "SM"
        item.button?.toolTip = "mac-sysmonitor"
        // Let the status bar choose its own contrast/highlight colors and backing.
        item.button?.appearance = nil
        item.button?.contentTintColor = nil
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.menu = makeMenu()
        statusItem = item
        updateIndicators()
        showSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(intervalKey: refreshIntervalKey, intervals: refreshIntervals) { [weak self] in
                self?.refreshSettings()
            }
        }
        settingsController?.refresh()
        settingsController?.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    private func refreshSettings() {
        updateIndicators()
        statusItem?.menu = makeMenu()
        settingsController?.refresh()
    }

    private func makeSettingsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        item.target = self
        return item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let heading = NSMenuItem(title: "mac-sysmonitor", action: nil, keyEquivalent: "")
        menu.addItem(heading)
        menu.addItem(makeSettingsItem())
        let notice = NSMenuItem(
            title: "Setup ready · metric collection coming next",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(notice)
        menu.addItem(.separator())

        for metric in Metric.allCases {
            let settings = NSMenuItem(title: metric.rawValue, action: nil, keyEquivalent: "")
            settings.submenu = makeMetricMenu(metric)
            menu.addItem(settings)
        }

        menu.addItem(.separator())
        let intervalItem = NSMenuItem(title: "Refresh interval", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        for seconds in refreshIntervals {
            let option = NSMenuItem(
                title: "\(seconds) \(seconds == 1 ? "second" : "seconds")",
                action: #selector(changeRefreshInterval(_:)),
                keyEquivalent: ""
            )
            option.target = self
            option.tag = seconds
            option.state = UserDefaults.standard.integer(forKey: refreshIntervalKey) == seconds ? .on : .off
            intervalMenu.addItem(option)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)
        menu.addItem(.separator())
        menu.addItem(makeUninstallItem())
        let quit = NSMenuItem(title: "Quit mac-sysmonitor", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func toggleMetric(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let metric = Metric(rawValue: rawValue) else { return }
        let enabled = !UserDefaults.standard.bool(forKey: metric.preferenceKey)
        UserDefaults.standard.set(enabled, forKey: metric.preferenceKey)
        sender.state = enabled ? .on : .off
        refreshSettings()
    }

    private func displayMode(for metric: Metric) -> DisplayMode {
        DisplayMode(rawValue: UserDefaults.standard.string(forKey: metric.displayModeKey) ?? "") ?? .text
    }

    private func makeMetricMenu(_ metric: Metric) -> NSMenu {
        let menu = NSMenu(title: metric.rawValue)
        menu.addItem(NSMenuItem(title: metric.rawValue, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "No data · collector not implemented yet", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Show in menu bar", action: #selector(toggleMetric(_:)), keyEquivalent: "")
        toggle.target = self
        toggle.representedObject = metric.rawValue
        toggle.state = UserDefaults.standard.bool(forKey: metric.preferenceKey) ? .on : .off
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Display", action: nil, keyEquivalent: ""))
        for mode in DisplayMode.allCases {
            let option = NSMenuItem(title: mode.rawValue, action: #selector(changeDisplayMode(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = [metric.rawValue, mode.rawValue]
            option.state = displayMode(for: metric) == mode ? .on : .off
            menu.addItem(option)
        }
        menu.addItem(.separator())
        menu.addItem(makeSettingsItem())
        menu.addItem(makeUninstallItem())
        return menu
    }

    private func makeUninstallItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Uninstall mac-sysmonitor…", action: #selector(uninstallApp), keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func uninstallApp() {
        // Present the confirmation after menu tracking ends.
        DispatchQueue.main.async {
            AppUninstaller.confirmAndUninstall()
        }
    }

    @objc private func changeDisplayMode(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? [String], selection.count == 2,
              let metric = Metric(rawValue: selection[0]),
              let mode = DisplayMode(rawValue: selection[1]) else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: metric.displayModeKey)
        for option in sender.menu?.items ?? [] {
            if let value = option.representedObject as? [String], value.count == 2 {
                option.state = value[1] == mode.rawValue ? .on : .off
            }
        }
        refreshSettings()
    }

    private func updateIndicators() {
        for metric in Metric.allCases {
            guard UserDefaults.standard.bool(forKey: metric.preferenceKey) else {
                if let item = metricItems.removeValue(forKey: metric) {
                    NSStatusBar.system.removeStatusItem(item)
                }
                continue
            }
            let item: NSStatusItem
            if let existing = metricItems[metric] {
                item = existing
            } else {
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                metricItems[metric] = item
            }
            let mode = displayMode(for: metric)
            item.button?.title = ""
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.image = StatusGraphic.image(metric: metric, mode: mode)
            item.button?.appearance = nil
            item.button?.contentTintColor = nil
            item.button?.toolTip = "\(metric.rawValue) · \(mode.rawValue) · No data"
            item.button?.setAccessibilityLabel("\(metric.rawValue), no data, \(mode.rawValue)")
            item.menu = makeMetricMenu(metric)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func changeRefreshInterval(_ sender: NSMenuItem) {
        guard refreshIntervals.contains(sender.tag) else { return }
        UserDefaults.standard.set(sender.tag, forKey: refreshIntervalKey)
        for option in sender.menu?.items ?? [] {
            option.state = option.tag == sender.tag ? .on : .off
        }
        refreshSettings()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
