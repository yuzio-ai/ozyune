import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationInProgress = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard OzyuneProcessManager.shared.hasManagedProcess else {
            return .terminateNow
        }

        guard !terminationInProgress else {
            return .terminateLater
        }

        terminationInProgress = true
        Task {
            await OzyuneProcessManager.shared.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
