import Combine
import Darwin
import Foundation

/// Owns the lifecycle of the single `dsh web` host process that Ozyune is responsible for.
///
/// This is the only type permitted to create, signal or reap that process, and it upholds the
/// invariant stated in `docs/architecture.md`: Ozyune must never leave the process it started
/// running. Output parsing is delegated to ``DshOutputInterpreter`` and user-facing failure copy
/// to ``StartupFailure``, so this type reads as the process lifecycle and little else.
@MainActor
final class OzyuneProcessManager: ObservableObject {

    // MARK: - State

    /// The consumer-facing shape of startup, observed by `ContentView`.
    enum State: Equatable {
        case idle
        case starting
        case running(URL)
        case failed(String)
    }

    static let shared = OzyuneProcessManager()

    @Published private(set) var state: State = .idle

    /// Whether Ozyune currently owns a live host process.
    var hasManagedProcess: Bool { process != nil }

    // MARK: - Configuration

    /// Values that differ between a real launch and a test launch.
    ///
    /// Kept injectable so the lifecycle can be exercised without shelling out to `npx`.
    struct Configuration {
        /// Login *and* interactive shell: Homebrew's PATH and nvm/asdf are configured in shell
        /// startup files, so a non-interactive shell would not resolve `npx`.
        var shellPath = "/bin/zsh"
        var shellArguments = ["-lic", "exec npx --yes @deepseek-ai/dsh web --no-open --port 0"]

        /// How long dsh may take to announce its ready URL before startup is treated as failed.
        var startupTimeout: Duration = .seconds(90)
        /// Grace period for the process to exit after `SIGTERM`.
        var gracefulTerminationTimeout: Duration = .seconds(3)
        /// How long to wait for the exit to be observed after `SIGKILL`.
        var forcedTerminationTimeout: Duration = .seconds(1)

        static let `default` = Configuration()

        /// ``startupTimeout`` in whole seconds, for user-facing messages.
        var startupTimeoutSeconds: Int { Int(startupTimeout.components.seconds) }
    }

    // MARK: - Owned process

    private let configuration: Configuration

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var output = DshOutputInterpreter()

    private var startupTimeoutTask: Task<Void, Never>?
    private var exitWaiter: ExitWaiter?

    /// True while ``stop()`` is tearing the process down, so the resulting termination is not
    /// reported as an unexpected crash.
    private var isStopping = false

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Lifecycle

    /// Launches the host process. Does nothing when a process is already owned.
    func start() {
        guard process == nil else { return }

        state = .starting
        isStopping = false
        output = DshOutputInterpreter()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let process = makeProcess(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        do {
            try process.run()
            armStartupTimeout()
        } catch {
            clearManagedProcess()
            state = .failed(StartupFailure.launchFailed(error).message)
        }
    }

    /// Tears down any owned process, then starts a fresh one.
    ///
    /// A retry must not leave the previous process behind — see `docs/architecture.md`.
    func restart() {
        Task {
            await stop()
            start()
        }
    }

    /// Terminates the owned process, escalating to `SIGKILL` when it ignores `SIGTERM`.
    ///
    /// Mirrors the shutdown lifecycle in `docs/architecture.md`. Each waiter is registered
    /// *before* the signal is sent, so an immediate exit cannot slip past the wait.
    func stop() async {
        cancelStartupTimeout()

        guard let process else {
            state = .idle
            return
        }

        isStopping = true
        // Detach first: output produced during teardown must not drive state changes.
        detachPipeHandlers()

        if process.isRunning {
            let gracefulExit = ExitWaiter(timeout: configuration.gracefulTerminationTimeout)
            exitWaiter = gracefulExit
            process.terminate()

            let exitedGracefully = await gracefulExit.wait()

            if !exitedGracefully, process.isRunning {
                let forcedExit = ExitWaiter(timeout: configuration.forcedTerminationTimeout)
                exitWaiter = forcedExit
                kill(process.processIdentifier, SIGKILL)
                _ = await forcedExit.wait()
            }

            exitWaiter = nil
        }

        clearManagedProcess()
        state = .idle
        isStopping = false
    }

    // MARK: - Startup

    /// Builds the process and wires its output and termination callbacks.
    private func makeProcess(stdoutPipe: Pipe, stderrPipe: Pipe) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.shellPath)
        process.arguments = configuration.shellArguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        // Both streams feed the same interpreter: readiness may be announced on either, and the
        // resulting transcript doubles as the diagnostics shown when startup fails.
        for pipe in [stdoutPipe, stderrPipe] {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                Task { @MainActor in
                    self?.recordOutput(data)
                }
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor in
                self?.processDidTerminate(terminatedProcess)
            }
        }

        return process
    }

    /// Arms the startup deadline. Cancelled once the ready URL arrives or teardown begins.
    private func armStartupTimeout() {
        cancelStartupTimeout()

        startupTimeoutTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: self.configuration.startupTimeout)
            } catch {
                return  // Cancelled: the process became ready, or teardown began.
            }

            guard case .starting = self.state else { return }

            let diagnostics = self.output.transcript
            await self.stop()
            self.state = .failed(
                StartupFailure.startupTimedOut(
                    seconds: self.configuration.startupTimeoutSeconds,
                    diagnostics: diagnostics
                ).message
            )
        }
    }

    private func cancelStartupTimeout() {
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
    }

    /// Records host output and promotes startup to `.running` at the first ready URL.
    private func recordOutput(_ data: Data) {
        guard let readyURL = output.consume(data) else { return }
        guard case .starting = state else { return }

        cancelStartupTimeout()
        state = .running(readyURL)
    }

    // MARK: - Termination

    private func processDidTerminate(_ terminatedProcess: Process) {
        guard process === terminatedProcess else { return }

        cancelStartupTimeout()
        detachPipeHandlers()

        let wasStopping = isStopping
        let exitStatus = terminatedProcess.terminationStatus
        let diagnostics = output.transcript

        clearManagedProcess()
        // Release any shutdown that is waiting on this exit.
        exitWaiter?.finish(exited: true)

        guard !wasStopping else { return }

        state = .failed(
            StartupFailure.unexpectedExit(status: exitStatus, diagnostics: diagnostics).message
        )
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

    // MARK: - Helpers

    /// One-shot "the process has exited" signal that can be awaited with a deadline.
    ///
    /// A single waiter suffices because Ozyune owns at most one process at a time. It always
    /// resumes — on exit or on its deadline — so a process that ignores both signals delays
    /// shutdown by exactly the configured timeouts rather than hanging it.
    @MainActor
    private final class ExitWaiter {
        private let timeout: Duration
        private var continuation: CheckedContinuation<Bool, Never>?
        private var deadlineTask: Task<Void, Never>?

        init(timeout: Duration) {
            self.timeout = timeout
        }

        /// - Returns: `true` when the process exited, `false` when the deadline elapsed first.
        func wait() async -> Bool {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                deadlineTask = Task { [weak self, timeout] in
                    try? await Task.sleep(for: timeout)
                    self?.finish(exited: false)
                }
            }
        }

        /// Resumes the waiter. Calling this more than once has no additional effect.
        func finish(exited: Bool) {
            guard let continuation else { return }

            self.continuation = nil
            deadlineTask?.cancel()
            deadlineTask = nil
            continuation.resume(returning: exited)
        }
    }

    /// User-facing startup failures, so the copy lives in one place instead of being assembled
    /// at each call site.
    private enum StartupFailure {
        case launchFailed(Error)
        case startupTimedOut(seconds: Int, diagnostics: String)
        case unexpectedExit(status: Int32, diagnostics: String)

        var message: String {
            switch self {
            case .launchFailed(let error):
                return "Failed to launch the Ozyune host process.\n\n\(error.localizedDescription)"

            case .startupTimedOut(let seconds, let diagnostics):
                return Self.summary(
                    "Ozyune did not become ready within \(seconds) seconds.",
                    appending: diagnostics
                )

            case .unexpectedExit(let status, let diagnostics):
                return Self.summary(
                    "Ozyune host exited unexpectedly with status \(status).",
                    appending: diagnostics
                )
            }
        }

        private static func summary(_ headline: String, appending diagnostics: String) -> String {
            let detail = diagnostics.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? headline : "\(headline)\n\n\(detail)"
        }
    }
}
