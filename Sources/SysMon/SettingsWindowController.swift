import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    private let onSave: (SettingsChanges) -> Void
    private let onUninstall: () -> Void
    private let presentAlert: (NSAlert) -> NSApplication.ModalResponse
    private var toggles: [Metric: NSButton] = [:]
    private var modes: [Metric: NSPopUpButton] = [:]
    private let intervalControl = NSPopUpButton(frame: .zero, pullsDown: false)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private var pending = SettingsChanges()

    init(settings: SettingsStore, onSave: @escaping (SettingsChanges) -> Void, onUninstall: @escaping () -> Void,
         presentAlert: @escaping (NSAlert) -> NSApplication.ModalResponse = { $0.runModal() }) {
        self.settings = settings
        self.onSave = onSave
        self.onUninstall = onUninstall
        self.presentAlert = presentAlert
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 590, height: 420),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
        )
        window.title = "SysMon"
        // Inherit light/dark appearance and the system's control accent color.
        window.appearance = nil
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = settingsPage()
        window.center()
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    func refresh() {
        for metric in Metric.allCases {
            let enabled = settings.isEnabled(metric)
            let savedMode = settings.displayMode(for: metric)
            if pending.visibility[metric] == enabled { pending.visibility[metric] = nil }
            if pending.modes[metric] == savedMode { pending.modes[metric] = nil }
            toggles[metric]?.state = (pending.visibility[metric] ?? enabled) ? .on : .off
            let mode = pending.modes[metric] ?? savedMode
            modes[metric]?.selectItem(withTitle: mode.title)
        }
        let seconds = settings.interval
        if pending.interval == seconds { pending.interval = nil }
        intervalControl.selectItem(withTag: pending.interval ?? seconds)
        updateSaveButton()
    }

    func windowWillClose(_ notification: Notification) {
        pending = SettingsChanges()
        refresh()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmPendingChanges(quitting: false)
    }

    func confirmQuit() -> Bool {
        confirmPendingChanges(quitting: true)
    }

    private func confirmPendingChanges(quitting: Bool) -> Bool {
        guard !pending.isEmpty else { return true }
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = quitting ? "Save settings before quitting?" : "Save settings before closing?"
        alert.addButton(withTitle: quitting ? "Save and Quit" : "Save and Close")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: quitting ? "Quit Without Saving" : "Close Without Saving")
        switch presentAlert(alert) {
        case .alertFirstButtonReturn:
            saveSettings()
            return true
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    private func settingsPage() -> NSView {
        let header = NSTextField(labelWithString: "SysMon")
        header.textColor = .labelColor
        header.font = .systemFont(ofSize: 20, weight: .semibold)
        let tagline = NSTextField(labelWithString: "Your Mac, at a glance.")
        tagline.textColor = .secondaryLabelColor
        let identity = NSStackView(views: [header, tagline])
        identity.orientation = .horizontal
        identity.alignment = .firstBaseline
        identity.spacing = 10
        var rows: [[NSView]] = []
        for metric in Metric.allCases {
            let label = NSTextField(labelWithString: metric.title)
            let toggle = NSButton(checkboxWithTitle: "Show in menu bar", target: self, action: #selector(toggleMetric(_:)))
            toggle.identifier = NSUserInterfaceItemIdentifier(metric.rawValue)
            toggles[metric] = toggle
            let mode = NSPopUpButton(frame: .zero, pullsDown: false)
            for option in DisplayMode.allCases {
                mode.addItem(withTitle: option.title)
                mode.lastItem?.representedObject = option
            }
            mode.identifier = NSUserInterfaceItemIdentifier(metric.rawValue)
            mode.target = self
            mode.action = #selector(changeMode(_:))
            mode.setAccessibilityLabel("\(metric.title) display mode")
            toggle.setAccessibilityLabel("Show \(metric.title) in menu bar")
            modes[metric] = mode
            rows.append([label, toggle, mode])
        }
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 16
        grid.rowSpacing = 12
        grid.xPlacement = .leading
        grid.yPlacement = .center
        grid.rowAlignment = .firstBaseline
        // Use native fitting widths so the grid cannot redistribute spare
        // space differently when AppKit resolves light/dark appearance.
        for column in 0..<3 {
            grid.column(at: column).width = rows.map { $0[column].fittingSize.width }.max() ?? 0
        }

        for seconds in SettingsStore.intervals {
            intervalControl.addItem(withTitle: "\(seconds) \(seconds == 1 ? "second" : "seconds")")
            intervalControl.lastItem?.tag = seconds
        }
        intervalControl.target = self
        intervalControl.action = #selector(changeInterval)
        intervalControl.setAccessibilityLabel("Refresh interval")
        let intervalRow = NSStackView(views: [NSTextField(labelWithString: "Refresh interval"), intervalControl])
        intervalRow.orientation = .horizontal
        intervalRow.alignment = .firstBaseline
        intervalRow.distribution = .fill
        intervalRow.spacing = 16
        let note = NSTextField(wrappingLabelWithString: "Live metric collection is coming next. Indicators currently show no data. Download appears above upload.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        let uninstall = NSButton(title: "Uninstall SysMon…", target: self, action: #selector(uninstallApp))
        saveButton.target = self
        saveButton.action = #selector(saveSettings)
        saveButton.keyEquivalent = "\r"
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.addView(uninstall, in: .leading)
        actions.addView(saveButton, in: .trailing)
        return page(views: [identity, grid, intervalRow, note], actions: actions)
    }

    private func page(views: [NSView], actions: NSStackView) -> NSView {
        // Use the semantic material so macOS handles desktop tinting, contrast,
        // and accessibility changes. Never sample wallpaper or cache resolved RGB.
        let container = NSVisualEffectView()
        container.material = .windowBackground
        container.blendingMode = .behindWindow
        container.state = .followsWindowActiveState
        container.appearance = nil
        let stack = NSStackView(views: views + [actions])
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
            actions.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
        return container
    }

    @objc private func toggleMetric(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let metric = Metric(rawValue: raw) else { return }
        let enabled = sender.state == .on
        pending.visibility[metric] = enabled == settings.isEnabled(metric) ? nil : enabled
        updateSaveButton()
    }

    @objc private func changeMode(_ sender: NSPopUpButton) {
        guard let raw = sender.identifier?.rawValue, let metric = Metric(rawValue: raw),
              let mode = sender.selectedItem?.representedObject as? DisplayMode else { return }
        pending.modes[metric] = mode == settings.displayMode(for: metric) ? nil : mode
        updateSaveButton()
    }

    @objc private func changeInterval() {
        guard let seconds = intervalControl.selectedItem?.tag else { return }
        pending.interval = seconds == settings.interval ? nil : seconds
        updateSaveButton()
    }

    private func updateSaveButton() {
        saveButton.isEnabled = !pending.isEmpty
        window?.isDocumentEdited = saveButton.isEnabled
    }

    @objc private func saveSettings() {
        guard !pending.isEmpty else { return }
        let changes = pending
        pending = SettingsChanges()
        updateSaveButton()
        onSave(changes)
    }

    @objc private func uninstallApp() { onUninstall() }
}
