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
/// The `outputs` dictionary is keyed by the relative path (under a caller-
/// chosen base name) of each artifact, including any extension. A format
/// with a single JSON dump uses `["json": …]`; a texture format uses
/// `["png": …, "json": …]`; a multi-asset format can nest paths like
/// `"textures/tex_03.png"`.
public protocol FileFormat {
    static var formatName: String { get }
    init(binary: GoDData) throws
    init(outputs: [String: GoDData]) throws
    var binaryData: GoDData { get throws }
    var outputs: [String: GoDData] { get throws }
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
