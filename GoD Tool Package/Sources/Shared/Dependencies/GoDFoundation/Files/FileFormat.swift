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

public enum FileFormatErrors: Error, CustomStringConvertible {
    case invalidFileData(format: FileFormat.Type, ErrorTrace)
    case failedToEncode(format: FileFormat.Type, target: String, ErrorTrace)
    
    public var description: String {
        switch self {
        case let .invalidFileData(format, errorTrace):
            return "Error: Invalid data for file format '\(format.formatName)'\n\(errorTrace)"
        case let .failedToEncode(format, target, errorTrace):
            return "Error: Failed to encode file format '\(format.formatName)' to '\(target)'\n\(errorTrace)"
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
}
