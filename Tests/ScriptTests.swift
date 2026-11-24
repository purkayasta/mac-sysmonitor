import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw CheckFailure(description: message) }
}

struct CommandResult {
    let status: Int32
    let output: String
    let error: String
}

/// File-backed output avoids pipe-buffer deadlocks when a command fails noisily.
func run(_ executable: String, _ arguments: [String], at directory: URL,
         environment: [String: String] = ProcessInfo.processInfo.environment) throws -> CommandResult {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let error = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    FileManager.default.createFile(atPath: output.path, contents: nil)
    FileManager.default.createFile(atPath: error.path, contents: nil)
    defer {
        try? FileManager.default.removeItem(at: output)
        try? FileManager.default.removeItem(at: error)
    }
    let outHandle = try FileHandle(forWritingTo: output)
    let errHandle = try FileHandle(forWritingTo: error)
    defer { try? outHandle.close(); try? errHandle.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = environment
    process.standardOutput = outHandle
    process.standardError = errHandle
    try process.run()
    process.waitUntilExit()
    return try CommandResult(status: process.terminationStatus,
                             output: String(contentsOf: output, encoding: .utf8),
                             error: String(contentsOf: error, encoding: .utf8))
}

final class Fixture {
    let root: URL
    let repository: URL
    var environment = ProcessInfo.processInfo.environment
    let manager = FileManager.default

    init(repository: URL) throws {
        self.repository = repository
        root = manager.temporaryDirectory.appendingPathComponent("SysMon-tests-\(UUID())")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try manager.createDirectory(at: path("bin"), withIntermediateDirectories: true)
        environment["PATH"] = path("bin").path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
    }

    deinit { try? manager.removeItem(at: root) }
    func path(_ name: String) -> URL { root.appendingPathComponent(name) }
    func exists(_ name: String) -> Bool { manager.fileExists(atPath: path(name).path) }
    func read(_ name: String) throws -> String { try String(contentsOf: path(name), encoding: .utf8) }
    func write(_ name: String, _ text: String) throws {
        let url = path(name)
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    func mock(_ name: String, _ body: String) throws {
        try write("bin/" + name, "#!/bin/bash\n" + body + "\n")
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path("bin/" + name).path)
    }
    func bundle(_ name: String, version: String = "old", identifier: String = "dev.local.mac-sysmonitor") throws {
        try write(name + "/Contents/MacOS/SysMon", "#!/bin/sh\n")
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path(name + "/Contents/MacOS/SysMon").path)
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleExecutable": "SysMon", "CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL",
        ], format: .xml, options: 0)
        try plist.write(to: path(name + "/Contents/Info.plist"))
        try write(name + "/version", version)
    }
    func script(_ name: String, _ arguments: [String]) throws -> CommandResult {
        try run("/bin/bash", [repository.appendingPathComponent("scripts/" + name).path] + arguments,
                at: root, environment: environment)
    }
}

@main
struct ScriptTests {
    static func main() throws {
        let repository = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let installer = repository.appendingPathComponent(".build/install-built-app-tests").path
        var count = 0
        func test(_ name: String, _ body: (Fixture) throws -> Void) throws {
            let fixture = try Fixture(repository: repository)
            try body(fixture)
            count += 1
            print("PASS \(name)")
        }

        // Installer safety checks using temporary app bundles.
        for name in ["first build", "replace installed bundle", "unrecognized directory", "other identifier", "symlink with trailing slashes", "missing installed bundle"] {
            try test("installer: " + name) { f in
                let source = "stage/SysMon.app"
                let destination = "SysMon.app"
                try f.bundle(source, version: "new")
                var mode = "update"
                var target = f.path(destination).path
                switch name {
                case "first build": mode = "build"
                case "replace installed bundle": try f.bundle(destination)
                case "unrecognized directory":
                    mode = "build"
                    try f.write(destination + "/keep.txt", "keep")
                case "other identifier": try f.bundle(destination, version: "other", identifier: "example.other")
                case "symlink with trailing slashes":
                    try f.bundle("original/SysMon.app")
                    try f.manager.createSymbolicLink(at: f.path(destination), withDestinationURL: f.path("original/SysMon.app"))
                    target += "//"
                default: break
                }
                let result = try run(installer, [mode, f.path(source).path, target], at: f.root)
                switch name {
                case "first build":
                    try expect(result.status == 0, result.error)
                    try expect(f.read(destination + "/version") == "new", "New bundle missing")
                    try expect(!f.exists(source), "Source should have moved")
                case "replace installed bundle":
                    try expect(result.status == 0, result.error)
                    try expect(f.read(destination + "/version") == "new", "Replacement missing")
                    try expect(f.read(source + "/version") == "old", "Previous copy was not preserved")
                case "unrecognized directory":
                    try expect(result.status != 0 && result.error.contains("unrecognized app bundle"), result.error)
                    try expect(f.read(destination + "/keep.txt") == "keep", "Unrelated directory changed")
                    try expect(f.read(source + "/version") == "new", "Candidate changed")
                case "other identifier":
                    try expect(result.status != 0, "Unrelated bundle accepted")
                    try expect(f.read(destination + "/version") == "other", "Unrelated bundle changed")
                case "symlink with trailing slashes":
                    try expect(result.status != 0, "Symlink accepted")
                    try expect((try? f.manager.destinationOfSymbolicLink(atPath: f.path(destination).path)) != nil, "Symlink changed")
                    try expect(f.read("original/SysMon.app/version") == "old", "Symlink target changed")
                default:
                    try expect(result.status != 0 && result.error.contains("No installed app"), result.error)
                    try expect(!f.exists(destination), "Missing destination was created")
                }
            }
        }

        // Destructive commands target fixtures or mocks only.
        for name in ["dry run", "scoped repeatable removal", "purge after move", "failed move", "failed shutdown", "helper compile failure", "absent bundle", "other identifier", "symlink", "invalid arguments"] {
            try test("uninstall: " + name) { f in
                let app = "folder with spaces/SysMon.app"
                try f.bundle(app)
                try f.write("keep.txt", "keep")
                try f.manager.createDirectory(at: f.path("Trash"), withIntermediateDirectories: true)
                f.environment["TEST_TRASH"] = f.path("Trash").path
                f.environment["TEST_LOG"] = f.path("operations.log").path
                f.environment["TEST_TRASH_FAIL"] = "0"
                f.environment["TEST_STOP_FAIL"] = "0"
                f.environment["TEST_COMPILE_FAIL"] = "0"
                try f.mock("swiftc", #"""
                if [ "$TEST_COMPILE_FAIL" = 1 ]; then
                    echo 'Could not compile shutdown helper' >&2
                    exit 1
                fi
                destination="${!#}"
                cat > "$destination" <<'HELPER'
                #!/bin/bash
                echo stop >> "$TEST_LOG"
                [ "$TEST_STOP_FAIL" = 0 ] || exit 1
                if [ "$#" = 1 ]; then
                    echo trash >> "$TEST_LOG"
                    [ "$TEST_TRASH_FAIL" = 0 ] || exit 1
                    /bin/mv "$1" "$TEST_TRASH/"
                fi
                HELPER
                chmod +x "$destination"
                """#)
                try f.mock("swift", "echo 'Unexpected second Swift compilation' >&2; exit 1")
                try f.mock("defaults", #"echo "$1 $2" >> "$TEST_LOG""#)
                var args = ["--app", f.path(app).path]
                switch name {
                case "dry run": args += ["--dry-run", "--purge"]
                case "purge after move": args += ["--purge"]
                case "failed move":
                    args += ["--purge"]
                    f.environment["TEST_TRASH_FAIL"] = "1"
                case "failed shutdown":
                    args += ["--purge"]
                    f.environment["TEST_STOP_FAIL"] = "1"
                case "helper compile failure":
                    args += ["--purge"]
                    f.environment["TEST_COMPILE_FAIL"] = "1"
                case "absent bundle": args = ["--app", f.path("missing/SysMon.app").path, "--purge"]
                case "other identifier":
                    let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "example.other.app"], format: .xml, options: 0)
                    try data.write(to: f.path(app + "/Contents/Info.plist"))
                case "symlink":
                    try f.manager.createSymbolicLink(at: f.path("SysMon.app"), withDestinationURL: f.path(app))
                    args = ["--app", f.path("SysMon.app").path]
                case "invalid arguments": args = ["--app", f.root.path]
                default: break
                }
                let result = try f.script("uninstall.sh", args)
                switch name {
                case "dry run":
                    try expect(result.status == 0, result.error)
                    try expect(f.exists(app) && !f.exists("operations.log"), "Dry run mutated files")
                    try expect(result.output.contains("Would move to Trash:") && result.output.contains("Would delete preferences:"), result.output)
                case "scoped repeatable removal":
                    try expect(result.status == 0, result.error)
                    let moved = "Trash/" + f.path(app).lastPathComponent + "/Contents/Info.plist"
                    try expect(!f.exists(app) && f.exists(moved) && f.exists("keep.txt"), "Removal scope incorrect")
                    let repeated = try f.script("uninstall.sh", args)
                    try expect(repeated.status == 0 && repeated.output.contains("already absent"), repeated.error)
                    try expect(f.read("operations.log") == "stop\ntrash\n", "Unexpected operations")
                case "purge after move":
                    try expect(result.status == 0, result.error)
                    try expect(f.read("operations.log") == "stop\ntrash\nstop\nread dev.local.mac-sysmonitor\ndelete dev.local.mac-sysmonitor\n", "Purge ordering incorrect")
                case "failed move":
                    try expect(result.status != 0 && result.error.contains("Saved settings were kept"), result.error)
                    try expect(f.exists(app) && f.read("operations.log") == "stop\ntrash\n", "Failure changed preferences or bundle")
                case "failed shutdown":
                    try expect(result.status != 0 && f.exists(app), "Shutdown failure removed the app")
                    try expect(f.read("operations.log") == "stop\n", "Shutdown failure touched bundle or settings")
                case "helper compile failure":
                    try expect(result.status != 0 && f.exists(app) && !f.exists("operations.log"), "Compiler failure changed app or settings")
                case "absent bundle":
                    try expect(result.status == 0 && result.output.contains("already absent"), result.error)
                    try expect(!f.exists("operations.log"), "Absent bundle triggered purge")
                default:
                    try expect(result.status != 0 && f.exists(app), "Invalid input removed bundle")
                    if name == "invalid arguments" {
                        let unknown = try f.script("uninstall.sh", ["--app", f.path(app).path, "--unknown"])
                        try expect(unknown.status != 0 && f.exists(app), "Unknown option accepted")
                    }
                }
            }
        }

        // Six publishing cases. GitHub and git push are mocked; no network is used.
        for name in ["missing commit", "committed main only", "unexpected push URL", "multiple push URLs", "rewritten push URL", "public repository"] {
            try test("publish: " + name) { f in
                let privateRemote = "https://github.com/test-owner/mac-sysmonitor.git"
                let otherRemote = "https://github.com/test-owner/other.git"
                let repo = f.path("repo")
                try f.manager.createDirectory(at: repo.appendingPathComponent("scripts"), withIntermediateDirectories: true)
                let script = repo.appendingPathComponent("scripts/publish-private.sh")
                try f.manager.copyItem(at: repository.appendingPathComponent("scripts/publish-private.sh"), to: script)
                f.environment["GIT_CONFIG_NOSYSTEM"] = "1"
                f.environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
                f.environment["TEST_GIT"] = "/usr/bin/git"
                f.environment["TEST_PUSH_LOG"] = f.path("push.log").path
                f.environment["TEST_VISIBILITY"] = "PRIVATE"
                try f.mock("gh", #"""
                case "$1 $2" in
                    "auth status") exit 0 ;;
                    "api user") echo test-owner ;;
                    "repo view") echo "$TEST_VISIBILITY" ;;
                    *) exit 1 ;;
                esac
                """#)
                try f.mock("git", #"""
                for arg in "$@"; do
                    if [ "$arg" = push ]; then
                        printf '%s\n' "$@" > "$TEST_PUSH_LOG"
                        exit 0
                    fi
                done
                exec "$TEST_GIT" "$@"
                """#)
                func git(_ arguments: [String]) throws -> String {
                    let result = try run("/usr/bin/git", arguments, at: repo, environment: f.environment)
                    try expect(result.status == 0, result.error)
                    return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                _ = try git(["init", "-b", "main"])
                _ = try git(["remote", "add", "origin", privateRemote])
                var head = ""
                var before = ""
                if name != "missing commit" {
                    _ = try git(["add", "scripts"])
                    _ = try git(["-c", "user.name=Test", "-c", "user.email=test@example.test", "commit", "-m", "Initial commit"])
                    head = try git(["rev-parse", "HEAD"])
                }
                switch name {
                case "committed main only":
                    try f.write("repo/scripts/staged.txt", "staged")
                    _ = try git(["add", "scripts/staged.txt"])
                    try f.write("repo/scripts/local.txt", "untracked")
                    before = try git(["status", "--porcelain"])
                case "unexpected push URL": _ = try git(["config", "remote.origin.pushurl", otherRemote])
                case "multiple push URLs":
                    _ = try git(["config", "--add", "remote.origin.pushurl", privateRemote])
                    _ = try git(["config", "--add", "remote.origin.pushurl", otherRemote])
                case "rewritten push URL": _ = try git(["config", "url.\(otherRemote).pushInsteadOf", privateRemote])
                case "public repository": f.environment["TEST_VISIBILITY"] = "PUBLIC"
                default: break
                }
                let result = try run("/bin/bash", [script.path], at: repo, environment: f.environment)
                if name == "committed main only" {
                    try expect(result.status == 0 && result.error.contains("Publishing committed changes only"), result.error)
                    try expect(git(["rev-parse", "HEAD"]) == head, "HEAD changed")
                    try expect(git(["status", "--porcelain"]) == before, "Working tree changed")
                    let args = try f.read("push.log").split(separator: "\n").map(String.init)
                    try expect(Array(args.suffix(6)) == ["push", "--no-follow-tags", "--recurse-submodules=no", "-u", "origin", "refs/heads/main:refs/heads/main"], "Unexpected push arguments")
                } else {
                    let expected = name == "missing commit" ? "on main first" : name == "public repository" ? "Repository is not private" : "exactly one origin push URL"
                    try expect(result.status != 0 && result.error.contains(expected), result.error)
                    try expect(!f.exists("push.log"), "Unsafe push attempted")
                }
            }
        }
        print("Passed \(count) Swift script integration tests.")
    }
}
