import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var processManager: OzyuneProcessManager

    var body: some View {
        Group {
            switch processManager.state {
            case .idle, .starting:
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Starting Ozyune…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .running(let url):
                OzyuneWebView(url: url)
                    .ignoresSafeArea()

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
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            processManager.start()
        }
    }
}
