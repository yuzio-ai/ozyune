import Darwin
import Foundation

@MainActor
final class OzyuneProcessManager: ObservableObject {
    static let shared = OzyuneProcessManager()

    enum State: Equatable {
        case idle
        case starting
        case running(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    // Keep this command intentionally simple for the first version.
    // It uses the same npm package the CLI command uses, prevents browser launch,
    // and asks macOS to choose an available loopback port.
    private let launchCommand = "exec npx --yes @deepseek-ai/dsh web --no-open --port 0"
    private let startupTimeoutNanoseconds: UInt64 = 90 * 1_000_000_000

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var startupTimeoutTask: Task<Void, Never>?
    private var outputBuffer = ""
    private var diagnostics = ""
    private var isStopping = false

    var hasManagedProcess: Bool {
        process != nil
    }

    func start() {
        guard process == nil else { return }

        state = .starting
        isStopping = false
        outputBuffer = ""
        diagnostics = ""

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // -l: load login-shell environment (Homebrew PATH is commonly configured there)
        // -i: also load interactive shell setup, which covers nvm/asdf-style Node installs
        // -c: execute the command and exit
        process.arguments = ["-lic", launchCommand]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.consume(data: data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.consume(data: data)
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor in
                self?.processDidTerminate(terminatedProcess)
            }
        }

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        do {
            try process.run()
            armStartupTimeout()
        } catch {
            clearManagedProcess()
            state = .failed("Failed to launch the Ozyune host process.\n\n\(error.localizedDescription)")
        }
    }

    func restart() {
        Task {
            await stop()
            start()
        }
    }

    func stop() async {
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil

        guard let process else {
            state = .idle
            return
        }

        isStopping = true
        detachPipeHandlers()

        if process.isRunning {
            process.terminate()
            let exitedGracefully = await waitUntilExited(process, timeoutNanoseconds: 3 * 1_000_000_000)

            if !exitedGracefully, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = await waitUntilExited(process, timeoutNanoseconds: 1 * 1_000_000_000)
            }
        }

        clearManagedProcess()
        state = .idle
        isStopping = false
    }

    private func armStartupTimeout() {
        startupTimeoutTask?.cancel()
        startupTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: startupTimeoutNanoseconds)
            } catch {
                return
            }

            guard let self, case .starting = self.state else { return }
            let detail = self.diagnostics.trimmingCharacters(in: .whitespacesAndNewlines)
            await self.stop()
            self.state = .failed(
                detail.isEmpty
                ? "Ozyune did not become ready within 90 seconds."
                : "Ozyune did not become ready within 90 seconds.\n\n\(detail)"
            )
        }
    }

    private func consume(data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let cleaned = stripANSI(text)

        outputBuffer = String((outputBuffer + cleaned).suffix(64 * 1024))
        diagnostics = String((diagnostics + cleaned).suffix(64 * 1024))

        guard case .starting = state, let url = extractReadyURL(from: outputBuffer) else {
            return
        }

        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        state = .running(url)
    }

    private func extractReadyURL(from text: String) -> URL? {
        for line in text.split(whereSeparator: \.isNewline) {
            guard let markerRange = line.range(of: "dsh web:") else { continue }
            let candidate = line[markerRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard candidate.hasPrefix("http://") || candidate.hasPrefix("https://") else {
                continue
            }

            // The ready line contains only the URL after the marker. Keeping the first
            // whitespace-delimited token avoids accidentally including later diagnostics.
            let urlString = candidate.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? candidate
            if let url = URL(string: urlString) {
                return url
            }
        }
        return nil
    }

    private func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\x{001B}\[[0-?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
    }

    private func processDidTerminate(_ terminatedProcess: Process) {
        guard process === terminatedProcess else { return }

        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        detachPipeHandlers()

        let wasStopping = isStopping
        let exitStatus = terminatedProcess.terminationStatus
        let detail = diagnostics.trimmingCharacters(in: .whitespacesAndNewlines)

        clearManagedProcess()

        guard !wasStopping else { return }

        var message = "Ozyune host exited unexpectedly with status \(exitStatus)."
        if !detail.isEmpty {
            message += "\n\n\(detail)"
        }
        state = .failed(message)
    }

    private func detachPipeHandlers() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
    }

    private func clearManagedProcess() {
        detachPipeHandlers()
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    private func waitUntilExited(_ process: Process, timeoutNanoseconds: UInt64) async -> Bool {
        let interval: UInt64 = 50_000_000
        var elapsed: UInt64 = 0

        while process.isRunning && elapsed < timeoutNanoseconds {
            do {
                try await Task.sleep(nanoseconds: interval)
            } catch {
                break
            }
            elapsed += interval
        }

        return !process.isRunning
    }
}
