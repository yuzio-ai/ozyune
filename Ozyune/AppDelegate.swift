import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationInProgress = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before launch completes, so a notification click is never missed.
        NotificationController.shared.prepare()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The permission prompt is only shown reliably once the app has fully
        // launched — asking earlier can be dropped silently by macOS.
        NotificationController.shared.requestAuthorizationIfNeeded()
    }

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
