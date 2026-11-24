import AppKit

/// Give only the explicitly launched fixtures SysMon's identity for testing.
/// Production discovery always reads the application's actual bundle identifier.
@MainActor
final class FixtureUninstallProcess: UninstallProcess {
    let application: NSRunningApplication
    init(_ application: NSRunningApplication) { self.application = application }
    var processIdentifier: pid_t { application.processIdentifier }
    var bundleIdentifier: String? { AppRemoval.bundleIdentifier }
    var isTerminated: Bool { application.isTerminated }
    func terminate() -> Bool { application.terminate() }
    func forceTerminate() -> Bool { application.forceTerminate() }
}

@MainActor
private final class FakeUninstallProcess: UninstallProcess {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    var isTerminated = false
    var exitsNormally = true
    var exitsWhenForced = true
    var quitRequests = 0
    var forceRequests = 0
    var onQuit: (() -> Void)?

    init(_ id: pid_t, identifier: String = AppRemoval.bundleIdentifier) {
        processIdentifier = id
        bundleIdentifier = identifier
    }

    func terminate() -> Bool {
        quitRequests += 1
        onQuit?()
        if exitsNormally { isTerminated = true }
        return exitsNormally
    }

    func forceTerminate() -> Bool {
        forceRequests += 1
        if exitsWhenForced { isTerminated = true }
        return exitsWhenForced
    }
}

@MainActor
func shutdownTests() async throws {
    func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "ShutdownTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    let first = FakeUninstallProcess(10)
    let second = FakeUninstallProcess(11)
    let helper = FakeUninstallProcess(99)
    let unrelated = FakeUninstallProcess(12, identifier: "example.other")
    let exited = FakeUninstallProcess(13)
    exited.isTerminated = true
    try await AppInstanceShutdown.stopAll(excluding: 99, runningApplications: { [first, second, helper, unrelated, exited] })
    try check(first.isTerminated && second.isTerminated && first.quitRequests == 1 && second.quitRequests == 1,
              "Every running SysMon instance must receive quit")
    try check(helper.quitRequests == 0 && unrelated.quitRequests == 0 && exited.quitRequests == 0,
              "Helper, unrelated apps, and exited processes must be excluded")

    let stubborn = FakeUninstallProcess(20)
    stubborn.exitsNormally = false
    var heartbeats = 0
    let heartbeat = Task { @MainActor in
        while !Task.isCancelled {
            heartbeats += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    try await AppInstanceShutdown.stopAll(excluding: 99, gracePeriod: .milliseconds(200),
                                          forcePeriod: .milliseconds(100), runningApplications: { [stubborn] })
    heartbeat.cancel()
    try check(stubborn.isTerminated && stubborn.quitRequests == 1 && stubborn.forceRequests == 1,
              "Refusing to quit must escalate to force termination")
    try check(heartbeats >= 5, "Waiting for shutdown blocked the main actor")

    let respawned = FakeUninstallProcess(30)
    let original = FakeUninstallProcess(31)
    var copies: [any UninstallProcess] = [original]
    original.onQuit = { copies.append(respawned) }
    try await AppInstanceShutdown.stopAll(excluding: 99, gracePeriod: .milliseconds(100),
                                          forcePeriod: .milliseconds(100), runningApplications: { copies })
    try check(respawned.isTerminated && respawned.quitRequests == 1, "A copy appearing during shutdown was missed")

    let denied = FakeUninstallProcess(40)
    denied.exitsNormally = false
    denied.exitsWhenForced = false
    var failed = false
    do {
        try await AppInstanceShutdown.stopAll(excluding: 99, gracePeriod: .zero,
                                              forcePeriod: .zero, runningApplications: { [denied] })
    } catch let error as AppInstanceShutdown.ShutdownError {
        failed = error.processIDs == [40]
    }
    try check(failed && !denied.isTerminated, "Failed force termination must abort uninstall")

    let cancelled = FakeUninstallProcess(50)
    cancelled.exitsNormally = false
    let operation = Task { @MainActor in
        try await AppInstanceShutdown.stopAll(excluding: 99, runningApplications: { [cancelled] })
    }
    await Task.yield()
    operation.cancel()
    do {
        try await operation.value
        try check(false, "Cancelled shutdown unexpectedly succeeded")
    } catch is CancellationError {}
    try check(cancelled.forceRequests == 0, "Cancelled shutdown continued into force termination")
    print("PASS shutdown: multiple instances, helper exclusion, unrelated apps, forced exit, new arrivals, failure, cancellation, and main-actor responsiveness")
}
