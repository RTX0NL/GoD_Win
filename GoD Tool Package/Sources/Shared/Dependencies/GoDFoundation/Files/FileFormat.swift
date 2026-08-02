//
//  FileFormat.swift
//
//
//  Created by Stars Momodu on 06/06/2024.
//

import Foundation

/// A file format that can be parsed from one or more raw binary files and
/// serialized to a set of editable artifacts (and back) without any external
/// engine/context. These are the formats eligible for `FileFormatRegistry`
/// routing.
///
/// Both sides are expressed as `[FileData]` — an ordered list where each
/// entry carries the `File` (path) its bytes belong to. Most formats have a
/// single binary (one `[FileData]` element on the binary side) and one or
/// more artifact files on the outputs side (a `.json` manifest plus any
/// companion assets it references).
///
/// Multi-binary formats (e.g. ISF's paired `.ish` + `.isd`) represent all
/// pieces on the binary side; their outputs still funnel through a single
/// `.json` manifest that carries paths to the companion files.
public protocol FileFormat {
    static var formatName: String { get }
    /// Base name (no extension) used to build output filenames. Default
    /// is `formatName`; set explicitly when dumping a known source file
    /// so artifacts are named after it (e.g. `name = "absol"` produces
    /// `absol.atx.json`, `absol_frame_000.png`).
    var name: String { get set }

    /// Parse from raw game-side binaries. For single-binary formats this
    /// is a one-element array; for paired formats (ISF) it carries every
    /// piece. Implementations should use the `File` on each entry to
    /// recover a sensible `name` stem when the caller hasn't set one.
    init(binaries: [FileData]) throws

    /// Rebuild the raw game-side binaries from the parsed state. Single-
    /// binary formats return one element; paired formats return each piece.
    var binaries: [FileData] { get throws }

    /// Parse from the editable artifact set (e.g. a `.json` manifest that
    /// points at companion assets, plus the assets themselves as they were
    /// read from the project folder). Build ops typically only need to
    /// supply the manifest — companion assets are read out of its declared
    /// paths — but the protocol accepts the fully-allData bundle to
    /// keep it self-describing.
    init(outputs: [FileData]) throws

    /// Serialize to an editable artifact bundle. The first entry is the
    /// JSON manifest (`<name>.<formatName>.json`); subsequent entries are
    /// whatever companion files the manifest's paths resolve to.
    var outputs: [FileData] { get throws }
}

public extension FileFormat {
    /// `<name>.<formatName>.json` — the metadata JSON every format emits.
    var jsonFilename: File { File("\(name).\(Self.formatName).json") }

    /// Single-binary convenience: returns the first binary's bytes. Formats
    /// with multiple binaries should call `binaries` directly.
    var binaryData: GoDData {
        get throws {
            let bins = try binaries
            guard let first = bins.first else {
                throw FileFormatErrors.failedToEncode(
                    format: Self.formatName,
                    target: "no binaries produced"
                )
            }
            return first.data
        }
    }

    /// Dict view of `outputs`, keyed by each artifact's `File`. Handy for
    /// formats that prefer keyed lookup while parsing back from artifacts.
    var outputsByFile: [File: GoDData] {
        get throws {
            Dictionary(uniqueKeysWithValues: try outputs.map { ($0.file, $0.data) })
        }
    }
}

public extension Array where Element == FileData {
    /// Dict view keyed by each entry's `File`. Used by format parsers that
    /// want keyed lookup over an ordered `[FileData]` input.
    var byFile: [File: GoDData] {
        Dictionary(uniqueKeysWithValues: map { ($0.file, $0.data) })
    }
}

public enum FileFormatErrors: Error, CustomStringConvertible {
    case invalidFileData(formatName: String, ErrorTrace)
    case failedToEncode(formatName: String, target: String, ErrorTrace)
    case missingOutput(formatName: String, key: String, ErrorTrace)
    case unsupportedOperation(formatName: String, operation: String, ErrorTrace)

    public var description: String {
        switch self {
        case let .invalidFileData(name, errorTrace):
            return "Error: Invalid data for file format '\(name)'\n\(errorTrace)"
        case let .failedToEncode(name, target, errorTrace):
            return "Error: Failed to encode file format '\(name)' to '\(target)'\n\(errorTrace)"
        case let .missingOutput(name, key, errorTrace):
            return "Error: Missing output artifact '\(key)' for file format '\(name)'\n\(errorTrace)"
        case let .unsupportedOperation(name, operation, errorTrace):
            return "Error: Operation '\(operation)' is not supported by file format '\(name)'\n\(errorTrace)"
        }
    }
}

public extension FileFormatErrors {
    /// Factories keyed by a raw format name, so types that hold a
    /// `static let formatName` but don't conform to `FileFormat` can still
    /// throw consistent errors.
    static func invalid(format name: String) -> Error {
        FileFormatErrors.invalidFileData(formatName: name, .init())
    }

    static func failedToEncode(format name: String, target: String) -> Error {
        FileFormatErrors.failedToEncode(formatName: name, target: target, .init())
    }

    static func missingOutput(format name: String, key: String) -> Error {
        FileFormatErrors.missingOutput(formatName: name, key: key, .init())
    }
}

public extension FileFormat {
    static var invalidFileError: Error {
        FileFormatErrors.invalid(format: Self.formatName)
    }

    static func failedToEncodeError(target: String) -> Error {
        FileFormatErrors.failedToEncode(format: Self.formatName, target: target)
    }

    static func missingOutputError(key: String) -> Error {
        FileFormatErrors.missingOutput(format: Self.formatName, key: key)
    }
}
