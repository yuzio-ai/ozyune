import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var processManager: OzyuneProcessManager

    var body: some View {
        Group {
            switch processManager.state {
            case .idle, .starting:
                StartupView()
                    .transition(.opacity)

            case .running(let url):
                OzyuneWebView(url: url)
                    .ignoresSafeArea()
                    .transition(.opacity)

            case .failed(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)

                    Text("Unable to start Ozyune")
                        .font(.title2.weight(.semibold))

                    ScrollView {
                        Text(message)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: 640, alignment: .leading)
                    }
                    .frame(maxHeight: 220)

                    Button("Try Again") {
                        processManager.restart()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .animation(.easeInOut(duration: 0.35), value: processManager.state)
        .task {
            processManager.start()
        }
    }
}
