import Darwin
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: swift install-built-app.swift STAGED_APP DESTINATION\n".utf8))
    exit(EXIT_FAILURE)
}

let source = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]

// Publish a new bundle, or atomically swap it with the current one. The build
// script cleans up the staging directory, including the old bundle after a swap.
let firstAttempt = renamex_np(source, destination, UInt32(RENAME_EXCL))
if firstAttempt != 0 {
    let result = errno == EEXIST ? renamex_np(source, destination, UInt32(RENAME_SWAP)) : firstAttempt
    if result != 0 {
        perror("Could not install the signed app")
        exit(EXIT_FAILURE)
    }
}
