//
//  FileFormat.swift
//
//
//  Created by Stars Momodu on 06/06/2024.
//

import Foundation

/// A file format that can be parsed from binary and serialized to a set of
/// editable artifacts (and back) without any external engine/context. These
/// are the formats eligible for `FileFormatRegistry` routing.
///
/// `outputs` is keyed by the relative `File` each artifact should be written
/// at (under a caller-chosen folder). Each format picks its own filenames;
/// callers providing a shared folder are expected to namespace via
/// subfolders to avoid collisions. A single-JSON format returns one entry
/// like `[File("metadata.json"): …]`; a texture format returns two like
/// `[File("metadata.json"): …, File("texture.png"): …]`; multi-asset
/// formats can nest paths like `File("textures/tex_03.png")`.
public protocol FileFormat {
    static var formatName: String { get }
    /// Base name (no extension) used to build output filenames. Default
    /// is `formatName`; set explicitly when dumping a known source file
    /// so artifacts are named after it (e.g. `name = "absol"` produces
    /// `absol.atx.json`, `absol_frame_000.png`).
    var name: String { get set }
    init(binary: GoDData) throws
    init(outputs: [File: GoDData]) throws
    var binaryData: GoDData { get throws }
    var outputs: [File: GoDData] { get throws }
}

public extension FileFormat {
    /// `<name>.<formatName>.json` — the metadata JSON every format emits.
    var jsonFilename: File { File("\(name).\(Self.formatName).json") }
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
