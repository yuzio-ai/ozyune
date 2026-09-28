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
/// Laid out as a grouped preference pane in the manner of recent macOS System
/// Settings: a page title, then one rounded surface per topic, so the page reads
/// as a small number of deliberate groups instead of a column of loose rows.
/// The groups are filled with the system's own quaternary wash rather than a
/// fixed colour, which is what keeps them visible in both appearances — on
/// current macOS `controlBackgroundColor` and `windowBackgroundColor` resolve to
/// the same value, so a drawn surface of that colour would disappear into the
/// window. The two blocks are separated by a fixed gap rather than by stretching
/// the layout, which is what keeps the vertical rhythm readable when the window
/// has height to spare.
struct NotificationSettingsView: View {
    @ObservedObject private var notifications = NotificationController.shared

    /// Brand blue, sampled from the logo. Used only to tint the one primary
    /// action on the page — the single intentional 5% of Ozyune here.
    private let brandBlue = Color(red: 0.22, green: 0.45, blue: 0.93)

    /// 560 pt window = 496 pt content column + 32 pt a side.
    private let horizontalPadding: CGFloat = 32
    private let contentWidth: CGFloat = 496

    /// 440 pt window minus a standard 28 pt title bar = 412 pt of content view.
    ///
    /// Fixed, so the window keeps its intended size: the height the groups do
    /// not use collects under the last one instead of being distributed between
    /// them as dead space.
    private let contentHeight: CGFloat = 412

    /// Space between the page heading and the first group.
    private let headerSpacing: CGFloat = 22

    /// Space between two groups — clearly more than the 8–12 pt used *inside*
    /// one, so grouping is readable without a separator line.
    private let groupSpacing: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            notifyGroup
                .padding(.top, headerSpacing)

            systemGroup
                .padding(.top, groupSpacing)

            // Any height the two groups leave over stays at the bottom: the
            // page is anchored to its top edge, the way a settings pane is.
            Spacer(minLength: 0)
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

    private var notifyGroup: some View {
        group(title: "Notify me", symbol: "bell") {
            // Deliberately narrower than the group and left-aligned inside it:
            // a full-width segmented control reads as a toolbar, not a setting.
            Picker("Notify me", selection: deliveryModeBinding) {
                ForEach(NotificationController.DeliveryMode.allCases) { mode in
                    Text(mode.shortLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 340, alignment: .leading)

            Text(helpText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .padding(.top, 8)
        }
    }

    /// Writes the mode through an animation so the help text below cross-fades
    /// with the choice instead of snapping to a new sentence.
    private var deliveryModeBinding: Binding<NotificationController.DeliveryMode> {
        Binding(
            get: { notifications.deliveryMode },
            set: { mode in
                withAnimation(.easeOut(duration: 0.18)) {
                    notifications.deliveryMode = mode
                }
            }
        )
    }

    /// One sentence that describes the mode actually selected.
    private var helpText: String {
        switch notifications.deliveryMode {
        case .backgroundOnly:
            return "Only notify when Ozyune isn't the active app."
        case .always:
            return "Notify for every event, even while Ozyune is the active app."
        case .off:
            return "Don't send agent notifications."
        }
    }

    // MARK: - System notifications

    private var systemGroup: some View {
        group(title: "System Notifications", symbol: "gearshape") {
            HStack(spacing: 12) {
                Text("Permission")
                Spacer(minLength: 12)
                PermissionStatusPill(status: notifications.authorizationStatus)
            }

            // Reads as part of the row above: same leading edge, a short gap, no
            // full-width button.
            HStack(spacing: 10) {
                let denied = notifications.authorizationStatus == .denied

                Button(action: notifications.postTestNotification) {
                    Label("Send Test Notification", systemImage: "paperplane")
                }
                .controlSize(.regular)
                .disabled(denied)
                // The page's one strong action — except while permission is
                // denied, where a test run cannot deliver anything: there it
                // steps back so the recovery button below can carry the
                // emphasis instead of two grey buttons facing each other.
                .modifier(ActionEmphasis(isPrimary: !denied, tint: brandBlue))

                if denied {
                    Button("Open System Settings…", action: openNotificationSettings)
                        .buttonStyle(.borderedProminent)
                        .tint(brandBlue)
                        .controlSize(.regular)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
        }
    }

    /// One topic on one rounded surface: a heading row, then its controls.
    ///
    /// The heading sits a step below the page title — 13 pt semibold against the
    /// 17 pt title — with its symbol in the secondary colour so the words, not
    /// the icons, carry the hierarchy. The surface is a system wash, so it
    /// composites over whatever the window paints and stays legible in either
    /// appearance.
    private func group<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
            }
            .font(.headline)

            content()
                .padding(.top, 10)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Opens the Notifications pane of System Settings.
    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/// Applies the pane's primary-action styling to whichever button currently
/// deserves it.
///
/// A modifier rather than a plain `.buttonStyle(_:)` call because the choice is
/// conditional: the two styles are different types, so they cannot be selected
/// at the call site without duplicating the button.
private struct ActionEmphasis: ViewModifier {
    let isPrimary: Bool
    let tint: Color

    func body(content: Content) -> some View {
        if isPrimary {
            content
                .buttonStyle(.borderedProminent)
                .tint(tint)
        } else {
            content
                .buttonStyle(.bordered)
        }
    }
}

/// Single-line echo of the system authorization state, as a small capsule.
///
/// The pill always carries a symbol *and* a word, so the state never depends on
/// colour alone; the tint is a 14% wash of the same system colour behind it,
/// which stays legible in both appearances and, being small and light, does not
/// compete with the primary button underneath it.
private struct PermissionStatusPill: View {
    let status: UNAuthorizationStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            Text(title)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
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
