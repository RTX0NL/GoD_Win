import GoDFoundation

enum RunExecutableErrors: Error, CustomStringConvertible {
    /// The program never started. `reason` is the launcher's own account,
    /// which already names the path it tried.
    case couldNotLaunch(reason: String, ErrorTrace)
    case exitedNonZero(executable: File, code: Int32, standardError: String, ErrorTrace)
    case killedBySignal(executable: File, signal: Int32, standardError: String, ErrorTrace)

    var description: String {
        switch self {
        case let .couldNotLaunch(reason, trace):
            return "Run executable: \(reason)\n\(trace)"
        case let .exitedNonZero(executable, code, standardError, trace):
            return "Run executable: \(executable.fileName) exited with status \(code)"
                + Self.tail(standardError)
                + "\n\(trace)"
        case let .killedBySignal(executable, signal, standardError, trace):
            return "Run executable: \(executable.fileName) was killed by signal \(signal)"
                + Self.tail(standardError)
                + "\n\(trace)"
        }
    }

    /// The last few lines the program printed to standard error, which is
    /// where a failing program says why. The whole stream can be megabytes,
    /// so only the tail goes in the message — the rest is in the log.
    private static func tail(_ standardError: String, lines limit: Int = 10) -> String {
        let all = standardError
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        guard !all.isEmpty else { return "" }
        let tail = all.suffix(limit)
        let elided = all.count > tail.count ? "\n  … \(all.count - tail.count) earlier lines\n" : "\n"
        return ". Its last output was:" + elided + tail.map { "  " + $0 }.joined(separator: "\n")
    }
}
