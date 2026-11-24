import AppKit
import Carbon

enum QuitRequest {
    /// Wait for the quit event's reply, including any Save/Discard/Cancel dialog.
    /// NSRunningApplication.terminate() only reports whether the request was sent.
    static func send(to processID: pid_t) async -> Bool {
        await withCheckedContinuation { continuation in
            // Apple Event delivery blocks until the user answers. Keep it off
            // both the main actor and Swift's cooperative executor pool.
            DispatchQueue.global(qos: .userInitiated).async {
                let event = NSAppleEventDescriptor(
                    eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEQuitApplication),
                    targetDescriptor: NSAppleEventDescriptor(processIdentifier: processID),
                    returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
                )
                var reply = AppleEvent()
                let status = AESendMessage(event.aeDesc, &reply,
                                           AESendMode(kAEWaitReply | kAECanInteract), kNoTimeOut)
                let response = NSAppleEventDescriptor(aeDescNoCopy: &reply)
                let accepted = status == noErr &&
                    (response.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value ?? 0) == 0
                continuation.resume(returning: accepted)
            }
        }
    }
}
