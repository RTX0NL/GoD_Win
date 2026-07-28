import GoDFoundation

/// Target source language for Colosseum script decompilation. Both dialects
/// round-trip byte-exactly to identical binaries; this only selects the text
/// syntax written to (and parsed back from) disk.
public enum ColoScriptLanguage: String, Codable, CaseIterable, Sendable {
    case swift
    case python

    /// Output file extension for decompiled scripts in this language
    public var fileExtension: String {
        switch self {
        case .swift: return "swift"
        case .python: return "py"
        }
    }
}

/// Emits the decompiled source preamble: script-level constants for the
/// header fields that cannot be rederived when compiling text back to binary.
///
/// Reserved identifiers (never used for generated variables or functions):
/// - Swift:  `__scriptType`, `__compilerMetadata`, `__globalVarCount`
/// - Python: `__SCRIPT_TYPE__`, `__COMPILER_METADATA__`, `__GLOBAL_VAR_COUNT__`
///
/// Everything else is rederivable and therefore *not* emitted
/// (header semantics confirmed against the US engine disassembly):
/// - header bytes 0x02 (always 0x0101), 0x0A (runtime relocated-flag) and
///   0x14 (runtime next pointer) — 0 on disk
/// - byte 0x06 (relocation count) and both table pointers at 0x0C/0x10, from
///   the relocation entries (which a recompiler derives from string-pointer
///   immediates) and the function count
/// - the function table (count, offsets, order) from emission order, with
///   null entries represented as stub functions
/// - inter-run padding (none — code runs are contiguous)
/// - tail padding (files are zero-padded to a 32-byte boundary)
///
/// `__globalVarCount` sizes the script's global-variable arena. It is a real
/// source-level declaration (scripts index globals dynamically, so the count
/// cannot be recovered from static analysis alone).
///
/// `__compilerMetadata` (header 0x08) is never read by the engine; it is
/// preserved verbatim for byte-exact output.
///
/// When a corpus assumption is violated (e.g. an EU/JP script with a
/// different constant), the differing field is emitted as an extra constant
/// so the text stays lossless rather than silently normalized.
public struct ColoScriptSourceHeader {

    /// Alias kept for the emitter/formatter/parser call sites that refer to
    /// the rendering flavour as "syntax".
    public typealias Syntax = ColoScriptLanguage

    public init() {}

    public func preamble(for script: ColoScript, syntax: Syntax) -> String {
        var lines = [String]()

        lines.append(constant("scriptType", value: hex(Int(script.scriptTypeID)), syntax: syntax))
        lines.append(constant("compilerMetadata", value: hex(Int(script.compilerMetadata)), syntax: syntax))

        // Corpus-constant / runtime-zero fields: only emitted when they deviate
        if script.headerField2 != 0x0101 {
            lines.append(constant("headerField2", value: hex(Int(script.headerField2)), syntax: syntax))
        }
        if script.relocatedFlag != 0 {
            lines.append(constant("relocatedFlag", value: hex(Int(script.relocatedFlag)), syntax: syntax))
        }
        if script.runtimeNextPointer != 0 {
            lines.append(constant("runtimeNextPointer", value: hex(Int(script.runtimeNextPointer)), syntax: syntax))
        }

        return lines.joined(separator: "\n")
    }

    /// Global-variable declarations: one per arena slot, in slot order — the
    /// declaration count *is* the arena size. The initializer spells the
    /// slot's primitive type (`0` int, `0.0` float); slots only ever read via
    /// the rare 0x20-flag form are declared as `Object`.
    public func gvarDeclarations(types: [ColoValueType?], syntax: Syntax) -> [String] {
        types.enumerated().map { index, type in
            let name = "gvar\(index)"
            switch (type, syntax) {
            case (.float, .swift): return "var \(name) = 0.0"
            case (.float, .python): return "\(name) = 0.0"
            case (.void, .swift): return "var \(name): Object = 0"
            case (.void, .python): return "\(name): Object = 0"
            case (_, .swift): return "var \(name) = 0"
            case (_, .python): return "\(name) = 0"
            }
        }
    }

    /// Stub declaration for a null function-table entry (offset 0, no bytecode)
    public func nullFunctionStub(index: Int, syntax: Syntax) -> String {
        switch syntax {
        case .swift:
            return "func function_\(index)()  // null entry — no bytecode"
        case .python:
            return "def function_\(index)(): ...  # null entry — no bytecode"
        }
    }

    // MARK: - Helpers

    private func constant(_ name: String, value: String, syntax: Syntax) -> String {
        switch syntax {
        case .swift:
            return "static let __\(name) = \(value)"
        case .python:
            return "__\(screamingSnake(name))__ = \(value)"
        }
    }

    private func hex(_ value: Int) -> String {
        "0x\(String(value, radix: 16, uppercase: true))"
    }

    private func screamingSnake(_ name: String) -> String {
        var result = ""
        for character in name {
            if character.isUppercase { result.append("_") }
            result.append(character.uppercased())
        }
        return result
    }
}
