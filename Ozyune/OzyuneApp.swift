import SwiftUI

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
    }
}
