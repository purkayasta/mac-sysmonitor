import AppKit

@MainActor
final class QuitFixture: NSObject, NSApplicationDelegate {
    let delay: TimeInterval
    let accept: Bool
    let readyPath: String

    init(delay: TimeInterval, accept: Bool, readyPath: String) {
        self.delay = delay
        self.accept = accept
        self.readyPath = readyPath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FileManager.default.createFile(atPath: readyPath, contents: Data())
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            sender.reply(toApplicationShouldTerminate: self.accept)
        }
        return .terminateLater
    }
}

@main
struct QuitFixtureApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = QuitFixture(delay: Double(CommandLine.arguments[1])!,
                                   accept: CommandLine.arguments[2] == "accept",
                                   readyPath: CommandLine.arguments[3])
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
