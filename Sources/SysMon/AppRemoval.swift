import Darwin
import Foundation

enum AppRemoval {
    static let bundleIdentifier = "dev.local.mac-sysmonitor"
    static let bundleName = "SysMon.app"

    struct Identity: Codable, Equatable {
        let device: dev_t
        let inode: ino_t
    }

    enum RemovalError: LocalizedError {
        case invalidBundle
        case changedBundle

        var errorDescription: String? {
            switch self {
            case .invalidBundle:
                "Uninstall is available only from a packaged SysMon.app. Build the app and run that copy first."
            case .changedBundle:
                "The app bundle changed after uninstall was confirmed."
            }
        }
    }

    @discardableResult
    static func validate(_ url: URL) throws -> Identity {
        var info = stat()
        guard url.lastPathComponent == bundleName,
              lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              Bundle(url: url)?.bundleIdentifier == bundleIdentifier else {
            throw RemovalError.invalidBundle
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    /// Delete preferences only after moving the app succeeds.
    static func perform(
        bundleURL: URL,
        removeSettings: Bool,
        expectedIdentity: Identity? = nil,
        trash: (URL) throws -> Void,
        clearSettings: (String) -> Void
    ) throws {
        let identity = try validate(bundleURL)
        if let expectedIdentity, identity != expectedIdentity {
            throw RemovalError.changedBundle
        }
        try trash(bundleURL)
        if removeSettings {
            clearSettings(bundleIdentifier)
        }
    }
}
