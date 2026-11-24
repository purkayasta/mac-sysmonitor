import Foundation

@main
struct AppRemovalTests {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        func fixture(_ name: String, identifier: String = AppRemoval.bundleIdentifier) throws -> URL {
            let app = root.appendingPathComponent(name).appendingPathComponent("mac-sysmonitor.app")
            let contents = app.appendingPathComponent("Contents")
            try manager.createDirectory(at: contents, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL"],
                format: .xml, options: 0
            )
            try data.write(to: contents.appendingPathComponent("Info.plist"))
            return app
        }

        func expect(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "AppRemovalTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }

        var cleared: [String] = []
        let keep = try fixture("keep settings")
        try AppRemoval.perform(bundleURL: keep, removeSettings: false, trash: {
            try expect($0 == keep, "Must target only the selected bundle")
            try manager.removeItem(at: $0)
        }, clearSettings: { cleared.append($0) })
        try expect(!manager.fileExists(atPath: keep.path) && cleared.isEmpty, "Keep-settings flow failed")

        let purge = try fixture("purge settings")
        try AppRemoval.perform(bundleURL: purge, removeSettings: true, trash: {
            try expect(cleared.isEmpty, "Preferences must not be cleared before successful removal")
            try manager.removeItem(at: $0)
        }, clearSettings: { cleared.append($0) })
        try expect(cleared == [AppRemoval.bundleIdentifier], "Wrong preference domain cleared")

        cleared.removeAll()
        let failure = try fixture("permission failure")
        var failed = false
        do {
            try AppRemoval.perform(bundleURL: failure, removeSettings: true, trash: { _ in
                throw CocoaError(.fileWriteNoPermission)
            }, clearSettings: { cleared.append($0) })
        } catch { failed = true }
        try expect(failed && cleared.isEmpty && manager.fileExists(atPath: failure.path), "Removal failure must preserve settings and bundle")

        let other = try fixture("other app", identifier: "example.other")
        var touchedInvalidApp = false
        do {
            try AppRemoval.perform(bundleURL: other, removeSettings: true, trash: { _ in
                touchedInvalidApp = true
            }, clearSettings: { cleared.append($0) })
            throw NSError(domain: "AppRemovalTests", code: 2)
        } catch AppRemoval.RemovalError.invalidBundle { }
        try expect(!touchedInvalidApp && cleared.isEmpty, "Must reject unrelated apps before any mutation")

        let link = root.appendingPathComponent("mac-sysmonitor.app")
        try manager.createSymbolicLink(at: link, withDestinationURL: failure)
        do {
            try AppRemoval.validate(link)
            throw NSError(domain: "AppRemovalTests", code: 3)
        } catch AppRemoval.RemovalError.invalidBundle { }
        print("Passed 5 app-removal safety checks (temporary fixtures only).")
    }
}
