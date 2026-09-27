import Foundation

/// A moment where the dsh agent needs the user's attention.
///
/// Signals are derived from the WebSocket traffic between the dsh Web UI and its
/// host, so they are delivered while the app is running only — see
/// `docs/architecture.md`, "Agent attention signals".
enum AgentSignal: String, CaseIterable {
    /// The agent paused for a human decision: a permission approval, an
    /// `ask_user_question` prompt, or an `exit_plan_mode` plan review.
    case needsJudgment
    /// The agent finished the current run and is idle again.
    case taskComplete
    /// The run ended on a model or runtime error.
    case runFailed
    /// The run ended without finishing: a rejected step, or an output-token
    /// ceiling that stopped it. Not a failure, but not a completion either.
    case runStopped
}

/// Tracing switch for the whole signal pipeline (`OZYUNE_DEBUG_SIGNALS=1`).
///
/// Used by both the page-side bridge and the notification controller so one
/// environment variable explains every decision the pipeline makes.
enum AgentSignalDebug {
    static let isEnabled = ProcessInfo.processInfo.environment["OZYUNE_DEBUG_SIGNALS"] == "1"
}

/// Turns raw dsh Web UI WebSocket frames into ``AgentSignal``s.
///
/// Server-to-client frames are compact JSON envelopes of shape
/// `{ "type": "item", "streamId": …, "value": … }` (`dsh-api-gateway`). Live
/// session events ride the follow stream as `{ "type": "event", "event": … }`
/// items whose `event.type` is the durable event name (`dsh-session`), e.g.
/// `approval/asked`, `tool/call`, `turn/end`.
///
/// Classification is structural — the frame is parsed and only live `event`
/// items are considered. This deliberately ignores follow snapshots (which
/// replay history records) and assistant chunk frames, and it cannot be fooled
/// by message *content* that merely quotes an event name: inside JSON strings
/// the quotes are escaped, so the structural fields are unambiguous.
///
/// The type is a pure function of its input: no clock, no state, no UI. The
/// marker vocabulary lives here alone — the page-side prefilter is generated
/// from ``frameMarkers`` — so a dsh wire-format change has exactly one place to
/// update. `scripts/check-signal-classifier.sh` pins the behaviour with real
/// frame fixtures.
struct AgentSignalClassifier {

    /// Tool calls that put a human decision in front of the user.
    private static let judgmentToolNames: Set<String> = [
        "ask_user_question",
        "exit_plan_mode",
    ]

    /// Cheap substring gate checked before any JSON parsing. `JSON.stringify`
    /// emits compact JSON, so these exact tokens appear only in real structure —
    /// never in message content, where the quotes would be escaped.
    ///
    /// The page-side observer filters on the same tokens, so uninteresting
    /// frames (above all the assistant's streaming chunks) never cross the
    /// JavaScript-to-native bridge.
    static let frameMarkers: [String] = [
        "\"type\":\"approval/asked\"",
        "\"type\":\"tool/call\"",
        "\"type\":\"turn/end\"",
    ]

    /// ``frameMarkers`` as a JavaScript array literal. JSON string encoding is
    /// valid JavaScript, so the escaping is handled by the serializer rather
    /// than by hand.
    static var javaScriptFrameMarkers: String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: frameMarkers),
            let literal = String(data: data, encoding: .utf8)
        else { return "[]" }

        return literal
    }

    /// Whether a frame carries any marker worth classifying, so frames that
    /// cannot matter never pay for JSON parsing.
    ///
    /// Private on purpose: the only other consumer of the vocabulary is the
    /// page-side prefilter, which is generated from ``frameMarkers`` and must not
    /// depend on this gate's behaviour.
    private static func hasMarker(_ frameText: String) -> Bool {
        frameMarkers.contains(where: frameText.contains)
    }

    /// - Returns: the signal a frame announces, or `nil` for the (vast majority
    ///   of) frames that carry nothing reportable.
    static func classify(frameText: String) -> AgentSignal? {
        guard hasMarker(frameText) else { return nil }
        guard
            let frame = try? JSONSerialization.jsonObject(with: Data(frameText.utf8)) as? [String: Any],
            frame["type"] as? String == "item",
            let value = frame["value"] as? [String: Any],
            // Only live journal entries; snapshots replay history and must not notify.
            value["type"] as? String == "event",
            let event = value["event"] as? [String: Any],
            let eventType = event["type"] as? String
        else { return nil }

        switch eventType {
        case "approval/asked":
            return .needsJudgment

        case "tool/call":
            let data = event["data"] as? [String: Any]
            guard let name = data?["name"] as? String else { return nil }
            return judgmentToolNames.contains(name) ? .needsJudgment : nil

        case "turn/end":
            let data = event["data"] as? [String: Any]
            return signal(forTurnEndReason: data?["reason"] as? [String: Any])

        default:
            return nil
        }
    }

    /// Maps the reason a turn ended to a signal.
    ///
    /// `turn/end` carries `reason`, a merge-extensible sum type
    /// (`TurnEndReasonMap` in `dsh-session`) whose variants today are
    /// `completed`, `aborted`, `blocked`, `error`, `max-tokens` and
    /// `interrupted`. Reporting every end as "finished" would tell the user a
    /// task completed when it was in fact cancelled or failed, so only ends the
    /// user did not ask for are reported:
    ///
    /// - `completed` — the run finished normally.
    /// - `error` — model or runtime failure; the user should know.
    /// - `blocked` / `max-tokens` — the run ended without finishing (a rejected
    ///   step, or an output-token ceiling).
    /// - `aborted` — stopped on purpose, by `user`, `parent`, `hook` or
    ///   `disposed`; whoever stopped it already knows, and the user is most
    ///   often the one who pressed stop.
    /// - `interrupted` — a crash-recovery closer for a stored log; the live loop
    ///   never emits it.
    ///
    /// An absent reason (older wire) or an unknown future variant falls back to
    /// `taskComplete`, the behaviour from before reasons were distinguished.
    private static func signal(forTurnEndReason reason: [String: Any]?) -> AgentSignal? {
        switch reason?["kind"] as? String {
        case "completed":
            return .taskComplete
        case "error":
            return .runFailed
        case "blocked", "max-tokens":
            return .runStopped
        case "aborted", "interrupted":
            return nil
        default:
            return .taskComplete
        }
    }
}
