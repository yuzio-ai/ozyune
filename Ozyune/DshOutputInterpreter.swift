import Foundation

/// Interprets the raw output stream of the dsh host process.
///
/// Readiness is inferred from a line dsh prints, which makes this the most failure-prone part of
/// launching. The rules therefore live in a type with no `Process`, `Pipe` or UI dependency:
/// they can be exercised without spawning anything, and `OzyuneProcessManager` is left owning
/// lifecycle alone.
struct DshOutputInterpreter {
    /// Marker dsh prints immediately before the URL it is listening on.
    private static let readinessMarker = "dsh web:"

    /// Upper bound on retained output, so a noisy process cannot grow memory without limit.
    private static let transcriptLimit = 64 * 1024

    /// Everything consumed so far, with ANSI sequences removed.
    private(set) var transcript = ""

    /// The ready URL, once it has been seen. Memoised so subsequent chunks are appended without
    /// rescanning the whole transcript.
    private(set) var readyURL: URL?

    /// Records a chunk of process output.
    ///
    /// - Returns: the ready URL once one has appeared, `nil` before that.
    @discardableResult
    mutating func consume(_ data: Data) -> URL? {
        guard let chunk = String(data: data, encoding: .utf8) else { return readyURL }

        transcript = Self.appending(Self.strippingANSI(from: chunk), to: transcript)

        if readyURL == nil {
            readyURL = Self.extractReadyURL(from: transcript)
        }

        return readyURL
    }

    /// Finds the first usable URL in a `dsh web:` readiness line.
    ///
    /// Lines carrying the marker but no absolute URL are skipped rather than treated as failures,
    /// because dsh interleaves unrelated diagnostics with its startup output.
    static func extractReadyURL(from text: String) -> URL? {
        for line in text.split(whereSeparator: \.isNewline) {
            guard let marker = line.range(of: readinessMarker) else { continue }

            let remainder = line[marker.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard remainder.hasPrefix("http://") || remainder.hasPrefix("https://") else { continue }

            // The URL is the first whitespace-delimited token; anything after it is trailing text
            // that would make the string unparseable.
            let candidate = remainder.split(whereSeparator: \.isWhitespace).first.map(String.init)
                ?? remainder

            if let url = URL(string: candidate) {
                return url
            }
        }

        return nil
    }

    /// Removes ANSI escape sequences, so markers stay matchable in colourised terminal output.
    static func strippingANSI(from text: String) -> String {
        text.replacingOccurrences(
            of: #"\x{001B}\[[0-?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func appending(_ chunk: String, to transcript: String) -> String {
        String((transcript + chunk).suffix(transcriptLimit))
    }
}
