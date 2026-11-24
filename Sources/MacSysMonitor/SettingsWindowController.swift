import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let intervalKey: String
    private let intervals: [Int]
    private let onChange: () -> Void
    private var toggles: [Metric: NSButton] = [:]
    private var modes: [Metric: NSPopUpButton] = [:]
    private let intervalControl = NSPopUpButton(frame: .zero, pullsDown: false)

    init(intervalKey: String, intervals: [Int], onChange: @escaping () -> Void) {
        self.intervalKey = intervalKey
        self.intervals = intervals
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 590, height: 560),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
        )
        window.title = "mac-sysmonitor"
        // Inherit light/dark appearance and the system's control accent color.
        window.appearance = nil
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = settingsPage()
        window.center()
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    func refresh() {
        for metric in Metric.allCases {
            toggles[metric]?.state = UserDefaults.standard.bool(forKey: metric.preferenceKey) ? .on : .off
            let mode = DisplayMode(rawValue: UserDefaults.standard.string(forKey: metric.displayModeKey) ?? "") ?? .text
            modes[metric]?.selectItem(withTitle: mode.rawValue)
        }
        let seconds = UserDefaults.standard.integer(forKey: intervalKey)
        intervalControl.selectItem(withTag: seconds)
    }

    private func settingsPage() -> NSView {
        let header = NSTextField(labelWithString: "Menu bar settings")
        header.textColor = .labelColor
        header.font = .systemFont(ofSize: 20, weight: .semibold)
        var rows: [[NSView]] = []
        for metric in Metric.allCases {
            let label = NSTextField(labelWithString: metric.rawValue)
            let toggle = NSButton(checkboxWithTitle: "Show in menu bar", target: self, action: #selector(toggleMetric(_:)))
            toggle.identifier = NSUserInterfaceItemIdentifier(metric.rawValue)
            toggles[metric] = toggle
            let mode = NSPopUpButton(frame: .zero, pullsDown: false)
            mode.addItems(withTitles: DisplayMode.allCases.map(\.rawValue))
            mode.identifier = NSUserInterfaceItemIdentifier(metric.rawValue)
            mode.target = self
            mode.action = #selector(changeMode(_:))
            mode.setAccessibilityLabel("\(metric.rawValue) display mode")
            toggle.setAccessibilityLabel("Show \(metric.rawValue) in menu bar")
            modes[metric] = mode
            rows.append([label, toggle, mode])
        }
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 16
        grid.rowSpacing = 12
        grid.rowAlignment = .firstBaseline

        for seconds in intervals {
            intervalControl.addItem(withTitle: "\(seconds) \(seconds == 1 ? "second" : "seconds")")
            intervalControl.lastItem?.tag = seconds
        }
        intervalControl.target = self
        intervalControl.action = #selector(changeInterval)
        intervalControl.setAccessibilityLabel("Refresh interval")
        let intervalRow = NSStackView(views: [NSTextField(labelWithString: "Refresh interval"), intervalControl])
        intervalRow.spacing = 16
        let note = NSTextField(wrappingLabelWithString: "Live metric collection is coming next. Indicators currently show no data. Download appears above upload.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        let uninstall = NSButton(title: "Uninstall mac-sysmonitor…", target: self, action: #selector(uninstallApp))
        return page(views: [header, grid, intervalRow, note, uninstall])
    }

    private func page(views: [NSView]) -> NSView {
        // Use the semantic material so macOS handles desktop tinting, contrast,
        // and accessibility changes. Never sample wallpaper or cache resolved RGB.
        let container = NSVisualEffectView()
        container.material = .windowBackground
        container.blendingMode = .behindWindow
        container.state = .followsWindowActiveState
        container.appearance = nil
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
        ])
        return container
    }

    @objc private func toggleMetric(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let metric = Metric(rawValue: raw) else { return }
        UserDefaults.standard.set(sender.state == .on, forKey: metric.preferenceKey)
        onChange()
    }

    @objc private func changeMode(_ sender: NSPopUpButton) {
        guard let raw = sender.identifier?.rawValue, let metric = Metric(rawValue: raw),
              let title = sender.titleOfSelectedItem, let mode = DisplayMode(rawValue: title) else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: metric.displayModeKey)
        onChange()
    }

    @objc private func changeInterval() {
        guard let seconds = intervalControl.selectedItem?.tag, intervals.contains(seconds) else { return }
        UserDefaults.standard.set(seconds, forKey: intervalKey)
        onChange()
    }

    @objc private func uninstallApp() { AppUninstaller.confirmAndUninstall() }
}
