import AppKit
import Darwin

private struct InstallError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@main
struct BundleInstaller {
    @MainActor
    static func main() async {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count == 4, ["build", "update"].contains(arguments[1]) else {
                throw InstallError(message: "Expected build or update, a staged bundle, and a destination.")
            }
            let source = URL(fileURLWithPath: arguments[2], isDirectory: true).standardizedFileURL
            let destination = URL(fileURLWithPath: arguments[3], isDirectory: true).standardizedFileURL
            try await install(source, at: destination, updating: arguments[1] == "update")
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    @MainActor
    private static func install(_ source: URL, at destination: URL, updating: Bool) async throws {
        let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
        let lock = open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard lock >= 0 else { throw systemError("Could not open \(parent.path)") }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            throw systemError("Could not lock \(parent.path) for this installation")
        }

        let candidate = try validate(source)
        guard destination.lastPathComponent == AppRemoval.bundleName else {
            throw InstallError(message: "Expected a destination named \(source.lastPathComponent).")
        }
        var info = stat()
        if lstat(destination.path, &info) != 0 {
            guard errno == ENOENT else { throw systemError("Could not inspect \(destination.path)") }
            guard !updating else { throw InstallError(message: "No installed app at \(destination.path).") }
            try rename(source, to: destination, flags: UInt32(RENAME_EXCL))
            return
        }
        let previous = try validate(destination)
        let running = runningCopies(at: destination)
        guard updating || running.isEmpty else {
            throw InstallError(message: "Quit the running build or update it with scripts/update-app.sh --app \"\(destination.path)\".")
        }
        guard running.count <= 1 else {
            throw InstallError(message: "Quit extra instances of the app at \(destination.path) before updating.")
        }
        guard let oldApp = running.first else {
            try replace(source, at: destination, expected: previous)
            guard updating else { return }
            print("Launching updated SysMon…")
            do {
                _ = try await launch(destination)
            } catch {
                let launchFailure = error.localizedDescription
                do {
                    guard try validate(source) == previous else {
                        throw InstallError(message: "The previous bundle changed during the update.")
                    }
                    try replace(source, at: destination, expected: candidate)
                } catch {
                    throw InstallError(message: "Could not launch the updated app: \(launchFailure). Recovery could not finish: \(error.localizedDescription). Previous copy: \(source.path)")
                }
                throw InstallError(message: "Could not launch the updated app: \(launchFailure). The previous version was restored.")
            }
            return
        }

        let stagingDirectory = source.deletingLastPathComponent()
        let keepBackup = stagingDirectory.appendingPathComponent(".keep-for-recovery")
        let readyFile = stagingDirectory.appendingPathComponent(".update-ready")
        try Data().write(to: keepBackup, options: .withoutOverwriting)
        var keepRecoveryFiles = false
        defer { if !keepRecoveryFiles { try? FileManager.default.removeItem(at: keepBackup) } }

        print("Waiting for SysMon to quit…")
        guard await quit(oldApp) else {
            throw InstallError(message: "The app did not quit. The update was cancelled.")
        }
        do {
            try replace(source, at: destination, expected: previous)
        } catch {
            if (try? validate(destination)) == previous {
                _ = try? await launch(destination)
            }
            throw error
        }

        keepRecoveryFiles = true
        var startedApp: NSRunningApplication?
        do {
            let app = try await launch(destination, readyFile: readyFile)
            startedApp = app
            guard await waitUntil(timeout: .seconds(15), condition: {
                app.isTerminated ||
                    (try? String(contentsOf: readyFile, encoding: .utf8)) == String(app.processIdentifier)
            }), !app.isTerminated else {
                throw InstallError(message: "The updated app did not report that it finished launching.")
            }
            keepRecoveryFiles = false
        } catch {
            let launchFailure = error.localizedDescription
            do {
                var running = runningCopies(at: destination)
                if let startedApp, !startedApp.isTerminated,
                   !running.contains(where: { $0.processIdentifier == startedApp.processIdentifier }) {
                    running.append(startedApp)
                }
                for app in running {
                    guard await quit(app) else {
                        throw InstallError(message: "The updated process is still running.")
                    }
                }
                guard try validate(source) == previous else {
                    throw InstallError(message: "The previous bundle changed during the update.")
                }
                try replace(source, at: destination, expected: candidate)
            } catch {
                throw InstallError(message: "\(launchFailure) Recovery could not finish: \(error.localizedDescription) Previous copy: \(source.path)")
            }
            keepRecoveryFiles = false
            do {
                _ = try await launch(destination)
            } catch {
                throw InstallError(message: "\(launchFailure) The previous app was restored. Open it manually at \(destination.path).")
            }
            throw InstallError(message: "\(launchFailure) The previous app was restored and reopened.")
        }
    }

    private static func validate(_ url: URL) throws -> AppRemoval.Identity {
        do {
            let identity = try AppRemoval.validate(url)
            guard let bundle = Bundle(url: url),
                  bundle.infoDictionary?["CFBundlePackageType"] as? String == "APPL",
                  let executable = bundle.executableURL,
                  FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw InstallError(message: "Expected a packaged app with an executable.")
            }
            return identity
        } catch {
            throw InstallError(message: "Refusing to use an unrecognized app bundle at \(url.path).")
        }
    }

    private static func replace(_ source: URL, at destination: URL, expected: AppRemoval.Identity) throws {
        guard try validate(destination) == expected else {
            throw InstallError(message: "The app at \(destination.path) changed during installation.")
        }
        try rename(source, to: destination, flags: UInt32(RENAME_SWAP))
    }

    private static func rename(_ source: URL, to destination: URL, flags: UInt32) throws {
        guard renamex_np(source.path, destination.path, flags) == 0 else {
            throw systemError("Could not install the signed app at \(destination.path)")
        }
    }

    @MainActor
    private static func runningCopies(at url: URL) -> [NSRunningApplication] {
        let path = url.resolvingSymlinksInPath().path
        return NSRunningApplication.runningApplications(withBundleIdentifier: AppRemoval.bundleIdentifier)
            .filter { !$0.isTerminated && $0.bundleURL?.resolvingSymlinksInPath().path == path }
    }

    @MainActor
    private static func quit(_ app: NSRunningApplication) async -> Bool {
        guard !app.isTerminated else { return true }
        let accepted = await QuitRequest.send(to: app.processIdentifier)
        guard accepted || app.isTerminated else { return false }
        // The reply resolves user interaction; allow a short interval for exit.
        return await waitUntil(timeout: .seconds(5)) { app.isTerminated }
    }

    @MainActor
    private static func launch(_ url: URL, readyFile: URL? = nil) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        if let readyFile {
            configuration.environment = ["SYSMON_UPDATE_READY_PATH": readyFile.path]
        }
        return try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    @MainActor
    private static func waitUntil(timeout: Duration, condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }
        return true
    }

    private static func systemError(_ operation: String) -> InstallError {
        let code = errno
        return InstallError(message: "\(operation): \(String(cString: strerror(code)))")
    }
}
