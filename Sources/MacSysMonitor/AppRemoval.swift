import Foundation

enum AppRemoval {
    static let bundleIdentifier = "dev.local.mac-sysmonitor"

    enum RemovalError: LocalizedError {
        case invalidBundle

        var errorDescription: String? {
            "Uninstall is available only from a packaged mac-sysmonitor.app. Build the app and run that copy first."
        }
    }

    static func validate(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              url.lastPathComponent == "mac-sysmonitor.app",
              Bundle(url: url)?.bundleIdentifier == bundleIdentifier else {
            throw RemovalError.invalidBundle
        }
    }

    /// Delete preferences only after moving the app succeeds.
    static func perform(
        bundleURL: URL,
        removeSettings: Bool,
        trash: (URL) throws -> Void,
        clearSettings: (String) -> Void
    ) throws {
        try validate(bundleURL)
        try trash(bundleURL)
        if removeSettings {
            clearSettings(bundleIdentifier)
        }
    }
}
