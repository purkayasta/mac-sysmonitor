import AppKit

@main
struct StopRunningApps {
    @MainActor
    static func main() async {
        do {
            try await AppInstanceShutdown.stopAll()
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
