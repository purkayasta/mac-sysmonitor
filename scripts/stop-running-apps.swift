import AppKit

@main
struct StopRunningApps {
    @MainActor
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count <= 1 else {
            FileHandle.standardError.write(Data("Usage: stop-running-apps [APP_PATH]\n".utf8))
            exit(EXIT_FAILURE)
        }
        do {
            let bundleURL = arguments.first.map { URL(fileURLWithPath: $0, isDirectory: true) }
            // Capture identity before waiting, then revalidate before moving.
            let identity = try bundleURL.map { try AppRemoval.validate($0) }
            try await AppInstanceShutdown.stopAll()
            if let bundleURL, let identity {
                try AppRemoval.perform(
                    bundleURL: bundleURL,
                    removeSettings: false,
                    expectedIdentity: identity,
                    trash: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
                    clearSettings: { _ in }
                )
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
