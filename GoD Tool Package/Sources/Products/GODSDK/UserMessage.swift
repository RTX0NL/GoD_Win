//
//  UserMessage.swift
//  GODOps
//
//  Most GoDError descriptions start with "Error:" and carry an ErrorTrace
//  line ("in <function> of <source file> at line #N"). That suits the CLI,
//  where the trace helps whoever runs it, but an MCP client should get one
//  readable sentence.
//

import Foundation
import GoDFoundation

extension GODOps {

    /// `error` as one message for a client: a single `Error: ` prefix and
    /// no source-location lines. Advice lines after the trace are kept.
    public static func userMessage(for error: Error) -> String {
        let lines = "\(error)"
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !isTraceLine($0) }
        var text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("Error:") {
            text = String(text.dropFirst("Error:".count)).trimmingCharacters(in: .whitespaces)
        }
        return "Error: " + text
    }

    /// Matches `ErrorTrace.description`.
    private static func isTraceLine(_ line: Substring) -> Bool {
        line.hasPrefix("in ") && line.contains(" of ") && line.contains(" at line #")
    }
}
