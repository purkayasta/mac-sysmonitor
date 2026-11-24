import AppKit
import Darwin

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "SM"
        item.button?.toolTip = "SysMon — Your Mac, at a glance."
        // Let the status bar choose its own contrast/highlight colors and backing.
        item.button?.appearance = nil
        item.button?.contentTintColor = nil
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.menu = makeMenu()
        statusItem = item
        for metric in Metric.allCases {
            updateIndicator(for: metric)
        }
        showSettings()
        DispatchQueue.main.async { [weak self] in self?.reportUpdateReady() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if uninstallChannel != nil { return .terminateNow }
        return settingsController?.confirmQuit() == false ? .terminateCancel : .terminateNow
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
        let applied = settings.apply(changes)
        for metric in Metric.allCases where applied.visibility[metric] != nil || applied.modes[metric] != nil {
            metricMenuItems[metric]?.submenu = makeMetricMenu(metric)
            updateIndicator(for: metric)
        }
        if let seconds = applied.interval {
            for option in intervalMenu.items {
                option.state = option.tag == seconds ? .on : .off
            }
        }
        settingsController?.refresh()
    }

    private func makeSettingsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        item.target = self
        return item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let heading = NSMenuItem(title: "SysMon", action: nil, keyEquivalent: "")
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
        let quit = NSMenuItem(title: "Quit SysMon", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func toggleMetric(_ sender: NSMenuItem) {
        guard let metric = sender.representedObject as? Metric else { return }
        applySettings(SettingsChanges(visibility: [metric: !settings.isEnabled(metric)]))
    }

    private func makeMetricMenu(_ metric: Metric) -> NSMenu {
        let menu = NSMenu(title: metric.title)
        menu.addItem(NSMenuItem(title: metric.title, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "No data · collector not implemented yet", action: nil, keyEquivalent: ""))
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
        return menu
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
        let mode = settings.displayMode(for: metric)
        item.button?.image = StatusGraphic.image(metric: metric, mode: mode)
        item.button?.toolTip = "\(metric.title) · \(mode.title) · No data"
        item.button?.setAccessibilityLabel("\(metric.title), no data, \(mode.title)")
        item.menu = makeMetricMenu(metric)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func changeRefreshInterval(_ sender: NSMenuItem) {
        applySettings(SettingsChanges(interval: sender.tag))
    }
}

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == AppUninstaller.finishArgument {
    exit(AppUninstaller.finishAfterQuit())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
