import AppKit

@MainActor
enum AppUninstaller {
    static func confirmAndUninstall() {
        let appURL = Bundle.main.bundleURL
        NSApplication.shared.activate(ignoringOtherApps: true)

        guard !appURL.path.contains("/AppTranslocation/") else {
            showError("Move the app to Applications and launch that copy before uninstalling.")
            return
        }
        let otherCopies = NSRunningApplication.runningApplications(
            withBundleIdentifier: AppRemoval.bundleIdentifier
        ).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard otherCopies.isEmpty else {
            showError("Quit other running copies of mac-sysmonitor, then try again.")
            return
        }

        do {
            try AppRemoval.validate(appURL)
        } catch {
            showError(error.localizedDescription)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall mac-sysmonitor?"
        alert.informativeText = "This copy will move to Trash and the app will quit. Other copies and source files will remain.\n\nLocation: \(appURL.path)"
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Move to Trash")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Also remove saved settings"
        alert.suppressionButton?.state = .off
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        do {
            try AppRemoval.perform(
                bundleURL: appURL,
                removeSettings: alert.suppressionButton?.state == .on,
                trash: { url in
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                },
                clearSettings: { identifier in
                    UserDefaults.standard.removePersistentDomain(forName: identifier)
                }
            )
            // macOS permits moving a running bundle; terminate only after success.
            NSApplication.shared.terminate(nil)
        } catch {
            showError("The app could not be moved to Trash. Your settings were kept.\n\n\(error.localizedDescription)\n\nYou can quit the app and move this copy to Trash in Finder.")
        }
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to uninstall mac-sysmonitor"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
