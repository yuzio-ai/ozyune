import AppKit
import Combine
import Foundation
import UserNotifications

/// Posts macOS system notifications for ``AgentSignal``s and owns their delivery policy.
///
/// This is the only type that talks to `UserNotifications`: the WebView bridge
/// classifies frames, the classifier knows nothing about notifications, and the
/// policy that decides *whether* a classified signal becomes a banner lives
/// here rather than at the call site. Authorization failure degrades silently —
/// a denied permission must never disturb the main product flow.
@MainActor
final class NotificationController: NSObject, ObservableObject {

    // MARK: - Policy

    /// When a classified signal becomes a visible notification.
    enum DeliveryMode: String, CaseIterable, Identifiable {
        /// Only when Ozyune is not the active application (the default).
        case backgroundOnly
        /// Even while Ozyune is frontmost.
        case always
        /// Never.
        case off

        var id: String { rawValue }

        /// Compact label for the segmented control in Settings, where the
        /// sentence-length form would be truncated in a settings-width window.
        var shortLabel: String {
            switch self {
            case .backgroundOnly: return "In Background"
            case .always: return "Always"
            case .off: return "Never"
            }
        }
    }

    /// UserDefaults keys, in one place so Settings and the controller cannot drift.
    enum SettingsKey {
        static let deliveryMode = "ozyune.notifications.deliveryMode"
    }

    static let shared = NotificationController()

    /// Persisted through `UserDefaults` on change.
    @Published var deliveryMode: DeliveryMode {
        didSet {
            UserDefaults.standard.set(deliveryMode.rawValue, forKey: SettingsKey.deliveryMode)
        }
    }

    /// Minimum gap between two notifications of the same kind, so one live
    /// moment (an approval echoed by `tool/call` and `tool/result`, a burst of
    /// reconnect frames) can never produce a pile of banners.
    private static let cooldown: TimeInterval = 10

    private var lastPosted: [AgentSignal: Date] = [:]

    /// Latest known system authorization state, surfaced in Settings.
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private override init() {
        let stored = UserDefaults.standard.string(forKey: SettingsKey.deliveryMode)
        deliveryMode = stored.flatMap(DeliveryMode.init(rawValue:)) ?? .backgroundOnly
        super.init()
    }

    // MARK: - Lifecycle

    /// Installs the notification delegate.
    ///
    /// Called before the app finishes launching so a notification click is
    /// always routed here. The authorization *request* deliberately does not
    /// happen here: macOS has been observed to drop the prompt silently when it
    /// is made before the app is fully launched, so `requestAuthorizationIfNeeded()`
    /// runs once launch completes instead.
    func prepare() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks for permission once the prompt is reliable to show — and never
    /// re-asks after the user or System Settings has already decided.
    func requestAuthorizationIfNeeded() {
        Task {
            await ensureAuthorization()
        }
    }

    /// Requests authorization while the question is still open, then refreshes
    /// the published status.
    ///
    /// Suspends until the prompt is answered, so a caller that needs a known
    /// state — or that is about to post — never races the decision. A denial
    /// degrades silently.
    @discardableResult
    private func ensureAuthorization() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        await refreshAuthorizationStatus()
        return authorizationStatus
    }

    /// Re-reads the system's authorization state into `authorizationStatus`.
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus

        if AgentSignalDebug.isEnabled {
            NSLog(
                "[OzyuneSignals] notification authorizationStatus=%d",
                settings.authorizationStatus.rawValue
            )
        }
    }

    // MARK: - Delivery

    /// Delivers `signal`, subject to the delivery mode, the system permission
    /// and a per-kind cooldown.
    func handle(_ signal: AgentSignal) {
        switch deliveryMode {
        case .off:
            return
        case .backgroundOnly:
            if NSApp.isActive { return }
        case .always:
            break
        }

        // Cheap synchronous gate first, so a burst of frames cannot queue
        // several posts behind the authorization read below.
        guard !isCoolingDown(signal) else { return }

        Task {
            // Re-read the system state instead of trusting the launch-time
            // value: the user may have changed it in System Settings since.
            await refreshAuthorizationStatus()
            guard authorizationStatus.allowsDelivery else { return }

            // The cooldown is only consumed when a banner is actually
            // requested, so a signal skipped for lack of permission cannot
            // silence the next one after the user grants it.
            let banner = bannerCopy(for: signal)
            lastPosted[signal] = Date()
            addNotification(
                identifier: "ozyune.\(signal.rawValue)",
                title: banner.title,
                body: banner.body
            )
        }
    }

    /// Posts a banner immediately, bypassing delivery mode and cooldown, so
    /// Settings can verify the whole notification path on demand.
    ///
    /// Waits for the permission decision first: posting while the prompt is
    /// still open would have the banner dropped by the system, and the button
    /// should do nothing rather than lie once permission is refused.
    func postTestNotification() {
        Task {
            let status = await ensureAuthorization()
            guard status.allowsDelivery else { return }

            addNotification(
                identifier: "ozyune.test",
                title: "Ozyune test notification",
                body: "If you can read this, system notifications are working."
            )
        }
    }

    /// Whether the per-kind cooldown window is still open for `signal`.
    private func isCoolingDown(_ signal: AgentSignal) -> Bool {
        guard let last = lastPosted[signal] else { return false }
        return Date().timeIntervalSince(last) < Self.cooldown
    }

    /// Banner copy per signal, so the wording for each outcome lives in one
    /// place instead of being assembled at the call site.
    private func bannerCopy(for signal: AgentSignal) -> (title: String, body: String) {
        switch signal {
        case .needsJudgment:
            return (
                "Ozyune needs your judgment",
                "The agent is waiting for your confirmation or answer."
            )
        case .taskComplete:
            return (
                "Ozyune task complete",
                "The agent finished the current run."
            )
        case .runFailed:
            return (
                "Ozyune run failed",
                "The agent stopped because of an error."
            )
        case .runStopped:
            return (
                "Ozyune stopped early",
                "The agent ended the run before finishing the task."
            )
        }
    }

    private func addNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // A stable identifier replaces any older notification with the same
        // identifier, keeping at most one banner per kind visible.
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationController: UNUserNotificationCenterDelegate {

    /// A notification was clicked: bring Ozyune's window to the front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            NSApp.activate()
            NSApp.windows.first(where: \.canBecomeMain)?.makeKeyAndOrderFront(nil)
            completionHandler()
        }
    }

    /// A notification arrived while the app could present it: show the banner.
    /// `handle(_:)` already suppresses signals outside the delivery mode, so at
    /// this point the banner is always wanted.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Authorization

private extension UNAuthorizationStatus {
    /// Whether the system would actually deliver a banner for this app.
    var allowsDelivery: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: return true
        case .denied, .notDetermined: return false
        @unknown default: return false
        }
    }
}
