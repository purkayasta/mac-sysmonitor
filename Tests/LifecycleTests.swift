import AppKit
import Darwin

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(description: message) }
}

@MainActor
private final class ModalProbe: NSObject {
    var ticks = 0

    @objc func tick(_ timer: Timer) {
        ticks += 1
        if ticks == 3 {
            timer.invalidate()
            NSApplication.shared.stopModal(withCode: .alertSecondButtonReturn)
        }
    }
}

@main
struct LifecycleTests {
    @MainActor
    static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // AppKit owns a nested run loop during runModal. Test that loop in a
        // separate invocation from the async quit tests' main dispatch loop.
        if CommandLine.arguments.dropFirst().contains("--modal") {
            try modalResponsivenessTest()
            return
        }
        try await shutdownTests()
        if CommandLine.arguments.dropFirst().contains("--shutdown") {
            try await shutdownFixtureTests()
            return
        }
        try settingsTests()
        try await renderNativeUI()
        try await shutdownFixtureTests()
        try await quitTests()
        print("Passed settings close/quit, native appearance, and asynchronous quit responsiveness checks.")
    }

    @MainActor
    private static func modalResponsivenessTest() throws {
        let probe = ModalProbe()
        let timer = Timer(timeInterval: 0.1, target: probe, selector: #selector(ModalProbe.tick(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .modalPanel)
        defer { timer.invalidate() }
        let alert = NSAlert()
        alert.messageText = "Save settings before closing?"
        alert.addButton(withTitle: "Save and Close")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Close Without Saving")
        let response = alert.runModal()
        try check(response == .alertSecondButtonReturn && probe.ticks == 3,
                  "Native modal dialog blocked its UI event loop")
        print("PASS modal responsiveness: AppKit processed timer events and cancellation")
    }

    @MainActor
    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor
    private static func settingsTests() throws {
        for quitting in [false, true] {
            for response: NSApplication.ModalResponse in [.alertFirstButtonReturn, .alertSecondButtonReturn, .alertThirdButtonReturn] {
                let domain = "dev.local.mac-sysmonitor.tests.\(UUID())"
                let defaults = UserDefaults(suiteName: domain)!
                defer { defaults.removePersistentDomain(forName: domain) }
                let store = SettingsStore(defaults: defaults)
                var saves = 0
                var prompts = 0
                let controller = SettingsWindowController(settings: store, onSave: { changes in
                    saves += 1
                    _ = store.apply(changes)
                }, onUninstall: {}, presentAlert: { alert in
                    prompts += 1
                    precondition(alert.messageText == (quitting ? "Save settings before quitting?" : "Save settings before closing?"))
                    precondition(alert.buttons.map(\.title) == (quitting
                        ? ["Save and Quit", "Cancel", "Quit Without Saving"]
                        : ["Save and Close", "Cancel", "Close Without Saving"]))
                    return response
                })
                let window = controller.window!
                try check(controller.windowShouldClose(window) && controller.confirmQuit(), "Clean settings should close/quit without prompting")
                try check(prompts == 0, "Clean settings prompted")
                let toggle = descendants(window.contentView!).compactMap { $0 as? NSButton }
                    .first { $0.identifier?.rawValue == Metric.cpu.rawValue }!
                toggle.state = .off
                _ = NSApplication.shared.sendAction(toggle.action!, to: toggle.target, from: toggle)
                try check(window.isDocumentEdited, "Settings edit wasn't marked pending")
                let permitted = quitting ? controller.confirmQuit() : controller.windowShouldClose(window)
                try check(prompts == 1, "Expected one confirmation")
                if response == .alertSecondButtonReturn {
                    try check(!permitted && window.isDocumentEdited && store.isEnabled(.cpu) && saves == 0,
                              "Cancel must preserve pending edits and keep the window/app open")
                    controller.refresh()
                    try check(toggle.state == .off, "Cancel lost pending edit")
                } else {
                    try check(permitted, "Save/discard must allow closing")
                    if response == .alertFirstButtonReturn {
                        try check(!store.isEnabled(.cpu) && saves == 1 && !window.isDocumentEdited,
                                  "Save must persist exactly once")
                    } else {
                        try check(store.isEnabled(.cpu) && saves == 0, "Discard unexpectedly saved")
                    }
                    if !quitting {
                        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
                        try check(!window.isDocumentEdited, "Close must clear discarded edits")
                        controller.refresh()
                        try check(toggle.state == (store.isEnabled(.cpu) ? .on : .off), "Reopen didn't match saved state")
                    }
                }
            }
        }
        print("PASS settings: clean, Save, Cancel, and Discard for both close and quit")
    }

    @MainActor
    private static func renderNativeUI() async throws {
        let domain = "dev.local.mac-sysmonitor.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let controller = SettingsWindowController(settings: SettingsStore(defaults: defaults), onSave: { _ in }, onUninstall: {})
        let content = controller.window!.contentView!
        let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let sampler = SystemSampler()
        var readings: [Metric: MetricReading] = [:]
        var histories: [Metric: MetricHistory] = [:]
        for _ in 0..<3 {
            readings = await sampler.sample(enabled: Set(Metric.allCases))
            for (metric, reading) in readings { histories[metric, default: MetricHistory()].append(reading, for: metric) }
            try await Task.sleep(for: .milliseconds(100))
        }
        var lightFrames: [NSRect] = []
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            controller.window!.appearance = NSAppearance(named: appearance)
            content.layoutSubtreeIfNeeded()
            try check(!content.hasAmbiguousLayout, "Ambiguous settings container")
            for control in descendants(content).compactMap({ $0 as? NSControl }) {
                let rect = control.convert(control.bounds, to: content)
                try check(content.bounds.contains(rect), "Settings control extends outside the window: \(control)")
                try check(rect.width > 0 && rect.height > 0, "Settings control has no visible size")
            }
            let frames = descendants(content).compactMap { $0 as? NSPopUpButton }.map { $0.convert($0.bounds, to: content) }
            if name == "light" { lightFrames = frames }
            else { try check(frames == lightFrames, "Popup layout shifted between light and dark appearance") }
            let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("settings-\(name).png"))
            let images = NSImage(size: NSSize(width: 450, height: 240))
            images.lockFocus()
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                NSRect(x: 0, y: 0, width: 450, height: 240).fill()
                for (row, metric) in Metric.allCases.enumerated() {
                    for (column, mode) in DisplayMode.allCases.enumerated() {
                        let image = StatusGraphic.image(metric: metric, mode: mode, reading: readings[metric] ?? .measuring,
                                                        history: histories[metric] ?? MetricHistory())
                        precondition(image.isTemplate && image.accessibilityDescription != nil)
                        // Tint template pixels for the preview as AppKit does in the status bar.
                        let tinted = NSImage(size: image.size)
                        tinted.lockFocus()
                        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
                        NSColor.labelColor.setFill()
                        NSRect(origin: .zero, size: image.size).fill(using: .sourceIn)
                        tinted.unlockFocus()
                        tinted.draw(at: NSPoint(x: 10 + column * 145, y: 205 - row * 38), from: .zero, operation: .sourceOver, fraction: 1)
                    }
                }
            }
            images.unlockFocus()
            let png = NSBitmapImageRep(data: images.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            try png.write(to: directory.appendingPathComponent("indicators-\(name).png"))
        }
        print("PASS native appearance: control bounds and all 18 indicators; light/dark previews saved in .build")
    }

    @MainActor
    private static func shutdownFixtureTests() async throws {
        var processes: [Process] = []
        var readyFiles: [URL] = []
        defer {
            for process in processes where process.isRunning { kill(process.processIdentifier, SIGKILL) }
            for file in readyFiles { try? FileManager.default.removeItem(at: file) }
        }
        for _ in 0..<2 {
            let ready = FileManager.default.temporaryDirectory.appendingPathComponent("SysMon-shutdown-\(UUID())")
            readyFiles.append(ready)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
                .deletingLastPathComponent().appendingPathComponent("quit-fixture")
            process.arguments = ["65", "cancel", ready.path]
            try process.run()
            processes.append(process)
            let deadline = ContinuousClock.now + .seconds(10)
            while !FileManager.default.fileExists(atPath: ready.path) {
                try check(process.isRunning && ContinuousClock.now < deadline, "Shutdown fixture failed to launch")
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        // Address fixture PIDs explicitly so this test cannot stop installed apps.
        let applications = processes.compactMap { NSRunningApplication(processIdentifier: $0.processIdentifier) }
        try check(applications.count == 2, "Fixture applications were not registered")
        let fixtureCopies = applications.map(FixtureUninstallProcess.init)
        try await AppInstanceShutdown.stopAll(gracePeriod: .milliseconds(200), forcePeriod: .seconds(3),
                                              runningApplications: { fixtureCopies })
        try check(applications.allSatisfy(\.isTerminated), "Force shutdown left fixture instances running")
        print("PASS shutdown integration: two real AppKit instances that refuse quit were force-closed")
    }

    @MainActor
    private static func quitTests() async throws {
        // Hold a cancellation longer than the former 60-second update deadline.
        for (delay, decision) in [(65.0, "cancel"), (0.2, "accept")] {
            let ready = FileManager.default.temporaryDirectory.appendingPathComponent("SysMon-ready-\(UUID())")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
                .deletingLastPathComponent().appendingPathComponent("quit-fixture")
            process.arguments = [String(delay), decision, ready.path]
            try process.run()
            defer {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                try? FileManager.default.removeItem(at: ready)
            }
            let deadline = ContinuousClock.now + .seconds(10)
            while !FileManager.default.fileExists(atPath: ready.path) {
                try check(process.isRunning && ContinuousClock.now < deadline, "Quit fixture failed to launch")
                try await Task.sleep(for: .milliseconds(20))
            }
            var heartbeats = 0
            let heartbeat = Task { @MainActor in
                while !Task.isCancelled {
                    heartbeats += 1
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            let start = ContinuousClock.now
            let accepted = await QuitRequest.send(to: process.processIdentifier)
            heartbeat.cancel()
            try check(accepted == (decision == "accept"), "Quit response didn't match \(decision)")
            try check(start.duration(to: .now) >= .milliseconds(Int64(delay * 900)), "Quit request returned before the user decision")
            try check(heartbeats >= Int(delay * 10), "Main actor stalled while awaiting the quit response")
            if decision == "cancel" {
                try check(process.isRunning, "Cancel unexpectedly terminated app")
            }
            print("PASS quit: \(decision) after \(delay)s; main actor delivered \(heartbeats) heartbeats")
        }
    }
}
