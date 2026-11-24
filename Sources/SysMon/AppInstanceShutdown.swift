import AppKit

@MainActor
protocol UninstallProcess: AnyObject {
    var processIdentifier: pid_t { get }
    var bundleIdentifier: String? { get }
    var isTerminated: Bool { get }
    func terminate() -> Bool
    func forceTerminate() -> Bool
}

extension NSRunningApplication: UninstallProcess {}

@MainActor
enum AppInstanceShutdown {
    struct ShutdownError: LocalizedError {
        let processIDs: [pid_t]
        var errorDescription: String? {
            "Could not stop SysMon instances (PIDs: \(processIDs.map(String.init).joined(separator: ", "))). Try again after closing those processes in Activity Monitor."
        }
    }

    /// Used only after uninstall is authorized. Other SysMon copies may have
    /// pending settings; the confirmation warns that these can be discarded.
    static func stopAll(
        excluding processID: pid_t = ProcessInfo.processInfo.processIdentifier,
        gracePeriod: Duration = .seconds(3),
        forcePeriod: Duration = .seconds(2),
        runningApplications: () -> [any UninstallProcess] = { NSWorkspace.shared.runningApplications }
    ) async throws {
        func remaining() -> [any UninstallProcess] {
            runningApplications().filter {
                $0.processIdentifier != processID && !$0.isTerminated &&
                    $0.bundleIdentifier == AppRemoval.bundleIdentifier
            }
        }

        for (force, period) in [(false, gracePeriod), (true, forcePeriod)] {
            let deadline = ContinuousClock.now + period
            var requested = Set<pid_t>()
            repeat {
                let copies = remaining()
                if copies.isEmpty { return }
                for copy in copies where requested.insert(copy.processIdentifier).inserted {
                    if force { _ = copy.forceTerminate() }
                    else { _ = copy.terminate() }
                }
                if remaining().isEmpty { return }
                try await Task.sleep(for: .milliseconds(50))
            } while ContinuousClock.now < deadline
        }
        let copies = remaining()
        if !copies.isEmpty {
            throw ShutdownError(processIDs: copies.map(\.processIdentifier).sorted())
        }
    }
}
