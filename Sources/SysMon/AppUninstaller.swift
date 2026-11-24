import AppKit
import Darwin

@MainActor
enum AppUninstaller {
    static let finishArgument = "--finish-uninstall"

    private struct Request: Codable {
        let processID: pid_t
        let bundle: AppRemoval.Identity
        let removeSettings: Bool
    }

    static func confirmAndPrepare() -> FileHandle? {
        let appURL = Bundle.main.bundleURL
        NSApplication.shared.activate(ignoringOtherApps: true)

        guard !appURL.path.contains("/AppTranslocation/") else {
            showError("Move the app to Applications and launch that copy before uninstalling.")
            return nil
        }

        let bundle: AppRemoval.Identity
        let executable: URL
        do {
            bundle = try AppRemoval.validate(appURL)
            guard let appExecutable = Bundle.main.executableURL else { throw AppRemoval.RemovalError.invalidBundle }
            executable = appExecutable
        } catch {
            showError(error.localizedDescription)
            return nil
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall SysMon?"
        alert.informativeText = "All running SysMon instances will close, and this copy will move to Trash. Instances that do not quit will be force-closed; their unsaved settings may be discarded. Other app copies and source files will remain on disk.\n\nLocation: \(appURL.path)"
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Move to Trash")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Also remove saved settings"
        alert.suppressionButton?.state = .off
        guard alert.runModal() == .alertSecondButtonReturn else { return nil }

        let request = Request(
            processID: ProcessInfo.processInfo.processIdentifier,
            bundle: bundle,
            removeSettings: alert.suppressionButton?.state == .on
        )
        do {
            return try startHelper(request, executable: executable)
        } catch {
            showError("The uninstall helper could not start.\n\n\(error.localizedDescription)")
            return nil
        }
    }

    private static func startHelper(_ request: Request, executable: URL) throws -> FileHandle {
        let channel = Pipe()
        let helper = Process()
        helper.executableURL = executable
        helper.arguments = [finishArgument]
        helper.standardInput = channel
        try channel.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(request))
        try helper.run()
        // The app delegate retains the writer until the process quits.
        return channel.fileHandleForWriting
    }

    static func finishAfterQuit() async -> Int32 {
        var input = stat()
        guard fstat(STDIN_FILENO, &input) == 0, input.st_mode & S_IFMT == S_IFIFO else { return EXIT_FAILURE }
        let data: Data? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: try? FileHandle.standardInput.readToEnd())
            }
        }
        guard let data,
              let request = try? JSONDecoder().decode(Request.self, from: data),
              request.processID > 1 else { return EXIT_FAILURE }

        // EOF releases the handoff. Confirm the original PID has exited before
        // touching the bundle, even if its writer closed during shutdown.
        let deadline = ContinuousClock.now + .seconds(5)
        while kill(request.processID, 0) == 0 || errno == EPERM {
            guard ContinuousClock.now < deadline else {
                return reportFailure("The running app did not exit.")
            }
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return reportFailure("Uninstall was interrupted.") }
        }
        do {
            try await AppInstanceShutdown.stopAll()
            try AppRemoval.perform(
                bundleURL: Bundle.main.bundleURL,
                removeSettings: request.removeSettings,
                expectedIdentity: request.bundle,
                trash: { url in
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                },
                clearSettings: { identifier in
                    UserDefaults.standard.removePersistentDomain(forName: identifier)
                }
            )
            return EXIT_SUCCESS
        } catch {
            return reportFailure(error.localizedDescription)
        }
    }

    private static func reportFailure(_ reason: String) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)
        showError("The app could not be moved to Trash. Your settings were kept.\n\n\(reason)\n\nYou can move this copy to Trash in Finder.")
        return EXIT_FAILURE
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to uninstall SysMon"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
