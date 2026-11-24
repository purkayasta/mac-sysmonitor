import Darwin
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift move-to-trash.swift APP_PATH\n".utf8))
    exit(EXIT_FAILURE)
}

let appURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
do {
    try FileManager.default.trashItem(at: appURL, resultingItemURL: nil)
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
