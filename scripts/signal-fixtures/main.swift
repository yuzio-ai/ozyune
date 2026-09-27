import Foundation

// Fixture check for AgentSignalClassifier, compiled together with
// `Ozyune/AgentSignal.swift` by `scripts/check-signal-classifier.sh`.
//
// Frames are the compact JSON the dsh Web UI actually receives, so a dsh
// wire-format change fails this check instead of silently disabling
// notifications. Positive cases pin the mapping; negative cases pin the
// reasons a frame must stay quiet (history replay, assistant chunks, message
// content that merely quotes an event name, turn ends the user asked for).

// MARK: - Frame builders

/// A server-to-client `item` envelope as `dsh-api-gateway` serializes it.
func item(_ value: String) -> String {
    "{\"type\":\"item\",\"streamId\":\"s1\",\"value\":\(value)}"
}

/// A live session event of `type` with raw JSON `data`.
func event(_ type: String, data: String) -> String {
    item("{\"type\":\"event\",\"event\":{\"type\":\"\(type)\",\"seq\":1,\"time\":1,\"data\":\(data)}}")
}

/// A live `turn/end`, optionally with a reason kind (`TurnEndReasonMap`).
func turnEnd(reason: String?) -> String {
    let data = reason.map { "{\"turn\":1,\"reason\":{\"kind\":\"\($0)\"}}" } ?? "{\"turn\":1}"
    return event("turn/end", data: data)
}

/// A live `tool/call` for `name`, with `arguments` kept a raw JSON string as the
/// wire carries it.
func toolCall(_ name: String, arguments: String = "{}") -> String {
    event(
        "tool/call",
        data: "{\"turn\":1,\"step\":1,\"callId\":\"c1\",\"name\":\"\(name)\",\"arguments\":\"\(arguments)\"}"
    )
}

// MARK: - Cases

struct Case {
    let name: String
    let frame: String
    let expected: AgentSignal?
}

let cases: [Case] = [
    // Needs judgment.
    Case(
        name: "permission approval asks the user",
        frame: event("approval/asked", data: "{\"callId\":\"c1\"}"),
        expected: .needsJudgment
    ),
    Case(
        name: "ask_user_question tool call asks the user",
        frame: toolCall("ask_user_question", arguments: "{\\\"questions\\\":[]}"),
        expected: .needsJudgment
    ),
    Case(
        name: "exit_plan_mode tool call asks the user",
        frame: toolCall("exit_plan_mode"),
        expected: .needsJudgment
    ),

    // Run outcomes, by turn/end reason.
    Case(name: "turn/end completed", frame: turnEnd(reason: "completed"), expected: .taskComplete),
    Case(name: "turn/end error", frame: turnEnd(reason: "error"), expected: .runFailed),
    Case(name: "turn/end blocked", frame: turnEnd(reason: "blocked"), expected: .runStopped),
    Case(name: "turn/end max-tokens", frame: turnEnd(reason: "max-tokens"), expected: .runStopped),
    Case(name: "turn/end aborted is not reported", frame: turnEnd(reason: "aborted"), expected: nil),
    Case(name: "turn/end interrupted is not reported", frame: turnEnd(reason: "interrupted"), expected: nil),
    Case(name: "turn/end without a reason falls back to complete", frame: turnEnd(reason: nil), expected: .taskComplete),
    Case(
        name: "turn/end with a future reason falls back to complete",
        frame: turnEnd(reason: "some-future-kind"),
        expected: .taskComplete
    ),

    // Frames that must stay quiet.
    Case(
        name: "ordinary tool call is quiet",
        frame: toolCall("bash", arguments: "{\\\"command\\\":\\\"ls\\\"}"),
        expected: nil
    ),
    Case(
        name: "tool call quoting a marker in its arguments is quiet",
        frame: toolCall("bash", arguments: "{\\\"command\\\":\\\"grep turn/end\\\"}"),
        expected: nil
    ),
    Case(
        name: "follow snapshot replaying history is quiet",
        frame: item(
            "{\"type\":\"snapshot\",\"header\":{},\"cursor\":1,\"hasMore\":false,\"projections\":{},"
                + "\"records\":["
                + "{\"type\":\"event\",\"event\":{\"type\":\"approval/asked\",\"seq\":3,\"time\":1,\"data\":{}}},"
                + "{\"type\":\"event\",\"event\":{\"type\":\"turn/end\",\"seq\":4,\"time\":1,\"data\":{\"reason\":{\"kind\":\"completed\"}}}}"
                + "]}"
        ),
        expected: nil
    ),
    Case(
        name: "assistant message quoting event names is quiet",
        frame: event(
            "assistant/message",
            data: "{\"turn\":1,\"step\":1,\"message\":{\"role\":\"assistant\",\"content\":"
                + "[{\"type\":\"text\",\"text\":\"the event type \\\"approval/asked\\\" and \\\"turn/end\\\" matter\"}]}}"
        ),
        expected: nil
    ),
    Case(
        name: "assistant stream chunk is quiet",
        frame: item(
            "{\"type\":\"assistant-stream\",\"frame\":{\"type\":\"chunk\",\"attemptId\":\"a\","
                + "\"revision\":1,\"index\":3,\"time\":1,\"chunk\":\"turn/end\"}}"
        ),
        expected: nil
    ),
    Case(
        name: "control baseline item is quiet",
        frame: item("{\"type\":\"baseline\",\"queues\":{},\"jobs\":{},\"projections\":{}}"),
        expected: nil
    ),
    Case(name: "empty frame is quiet", frame: "", expected: nil),
    Case(name: "non-JSON frame is quiet", frame: "not json at all turn/end", expected: nil),
]

// MARK: - Runner

var failures = 0

for testCase in cases {
    let actual = AgentSignalClassifier.classify(frameText: testCase.frame)
    if actual == testCase.expected {
        print("ok   \(testCase.name)")
    } else {
        failures += 1
        print("FAIL \(testCase.name): got \(String(describing: actual)), expected \(String(describing: testCase.expected))")
    }
}

// The page-side prefilter is generated from the classifier's vocabulary; it must
// stay a usable JavaScript/JSON array of non-empty markers.
if
    let data = AgentSignalClassifier.javaScriptFrameMarkers.data(using: .utf8),
    let markers = try? JSONSerialization.jsonObject(with: data) as? [String],
    markers == AgentSignalClassifier.frameMarkers,
    !markers.isEmpty
{
    print("ok   page-side marker literal matches the native vocabulary")
} else {
    failures += 1
    print("FAIL page-side marker literal does not round-trip: \(AgentSignalClassifier.javaScriptFrameMarkers)")
}

if failures > 0 {
    print("\(failures) failure(s)")
    exit(1)
}

print("all \(cases.count + 1) checks passed")
