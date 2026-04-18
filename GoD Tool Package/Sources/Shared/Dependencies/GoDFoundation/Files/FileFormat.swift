//
//  FileFormat.swift
//
//
//  Created by Stars Momodu on 06/06/2024.
//

import Foundation

public protocol FileFormat {
    static var formatName: String { get }
}

/// Refinement for file formats that can be dumped to a set of artifacts and
/// rebuilt back to binary without any external engine/context. These are the
/// formats eligible for `FileFormatRegistry`.
///
/// The `outputs` dictionary is keyed by the relative path (under a caller-
/// chosen base name) of each artifact, including any extension. A format with
/// a single JSON dump uses `["json": …]`; a texture format uses
/// `["png": …, "json": …]`; a multi-asset format can nest paths like
/// `"textures/tex_03.png"`.
public protocol DumpableFileFormat: FileFormat {
    init(binary: GoDData) throws
    init(outputs: [String: GoDData]) throws
    var binaryData: GoDData { get throws }
    var outputs: [String: GoDData] { get throws }
}

public enum FileFormatErrors: Error, CustomStringConvertible {
    case invalidFileData(format: FileFormat.Type, ErrorTrace)
    case failedToEncode(format: FileFormat.Type, target: String, ErrorTrace)
    case missingOutput(format: FileFormat.Type, key: String, ErrorTrace)
    case unsupportedOperation(format: FileFormat.Type, operation: String, ErrorTrace)

    public var description: String {
        switch self {
        case let .invalidFileData(format, errorTrace):
            return "Error: Invalid data for file format '\(format.formatName)'\n\(errorTrace)"
        case let .failedToEncode(format, target, errorTrace):
            return "Error: Failed to encode file format '\(format.formatName)' to '\(target)'\n\(errorTrace)"
        case let .missingOutput(format, key, errorTrace):
            return "Error: Missing output artifact '\(key)' for file format '\(format.formatName)'\n\(errorTrace)"
        case let .unsupportedOperation(format, operation, errorTrace):
            return "Error: Operation '\(operation)' is not supported by file format '\(format.formatName)'\n\(errorTrace)"
        }
    }
}

public extension FileFormat {
    static var invalidFileError: Error {
        FileFormatErrors.invalidFileData(format: Self.self, .init())
    }

    static func failedToEncodeError(target: String) -> Error {
        FileFormatErrors.failedToEncode(format: Self.self, target: target, .init())
    }

    static func missingOutputError(key: String) -> Error {
        FileFormatErrors.missingOutput(format: Self.self, key: key, .init())
    }
}
