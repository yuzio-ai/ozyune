import AppKit
import SwiftUI
import UserNotifications

@main
struct OzyuneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var processManager = OzyuneProcessManager.shared

    var body: some Scene {
        WindowGroup("Ozyune") {
            ContentView()
                .environmentObject(processManager)
        }
        .defaultSize(width: 1280, height: 820)

        Settings {
            NotificationSettingsView()
        }
        // The pane is a fixed 560 × 440: sizing the window to the content keeps
        // a restored frame from reopening it at some older, larger size.
        .windowResizability(.contentSize)
    }
}

/// Preferences for system-level agent notifications.
///
/// Built as a quiet, native macOS preference pane: system typography, alignment
/// and controls carry the hierarchy, so there are no cards, custom surfaces,
/// badges or shadows to re-implement light/dark mode, accent colour or
/// accessibility behaviour. The delivery choice explains itself through help
/// text that changes with the selected mode, instead of one paragraph that has
/// to cover all three at once.
struct NotificationSettingsView: View {
    @ObservedObject private var notifications = NotificationController.shared

    /// Brand blue, sampled from the logo. Used only to tint the selected
    /// segment — the single intentional 5% of Ozyune on this page.
    private let brandBlue = Color(red: 0.22, green: 0.45, blue: 0.93)

    /// 560 pt window = 496 pt content column + 32 pt a side.
    private let horizontalPadding: CGFloat = 32
    private let contentWidth: CGFloat = 496

    /// 440 pt window minus a standard 28 pt title bar = 412 pt of content view.
    ///
    /// The page's own blocks only need about 240 pt of that, so the remainder is
    /// shared equally by the flexible gaps below rather than being dumped under
    /// the last control as a block of dead space.
    private let contentHeight: CGFloat = 412

    /// The Permission row stops short of the column so the status stays tied
    /// to the field it describes instead of drifting to the far right.
    private let settingRowWidth: CGFloat = 430

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Spacer(minLength: 20)

            notifySection

            Spacer(minLength: 24)

            systemSection

            Spacer(minLength: 32)
        }
        .padding(.top, 28)
        .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
        .padding(.horizontal, horizontalPadding)
        .task {
            await notifications.refreshAuthorizationStatus()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notifications")
                .font(.title2.weight(.semibold))

            Text("Get notified when an agent finishes a task or needs your attention.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Notify me

    private var notifySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Notify me")

            // Deliberately narrower than the content column: a full-width
            // segmented control reads as a toolbar, not a setting.
            Picker("Notify me", selection: $notifications.deliveryMode) {
                ForEach(NotificationController.DeliveryMode.allCases) { mode in
                    Text(mode.shortLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(brandBlue)
            .frame(width: 340)
            .padding(.top, 12)

            Text(helpText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    /// One sentence that describes the mode actually selected.
    private var helpText: String {
        switch notifications.deliveryMode {
        case .backgroundOnly:
            return "Only notify when Ozyune isn't the active app."
        case .always:
            return "Notify whether Ozyune is active or in the background."
        case .off:
            return "Don't send agent notifications."
        }
    }

    // MARK: - System notifications

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("System Notifications")

            HStack(spacing: 0) {
                Text("Permission")
                Spacer(minLength: 12)
                PermissionStatusLabel(status: notifications.authorizationStatus)
            }
            .frame(maxWidth: settingRowWidth, alignment: .leading)
            .padding(.top, 12)

            // Reads as one group with the row above: same leading edge, a short
            // gap, no full-width button.
            HStack(spacing: 10) {
                Button("Send Test Notification") {
                    notifications.postTestNotification()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(notifications.authorizationStatus == .denied)

                if notifications.authorizationStatus == .denied {
                    Button("Open System Settings…") {
                        openNotificationSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 14)
        }
    }

    /// Section headings sit a step below the page title: same weight, smaller
    /// size, so "Notifications" stays the only display-level line on the page.
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
    }

    /// Opens the Notifications pane of System Settings.
    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/// Single-line echo of the system authorization state.
///
/// Only the symbol carries status colour and the title stays secondary, so the
/// row reads as a standard settings value rather than a coloured badge.
private struct PermissionStatusLabel: View {
    let status: UNAuthorizationStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.secondary)
        }
        .font(.body)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Denied"
        case .notDetermined: return "Not Determined"
        @unknown default: return "Unknown"
        }
    }

    private var symbol: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle"
        @unknown default: return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        case .notDetermined: return .secondary
        @unknown default: return .secondary
        }
    }
}
