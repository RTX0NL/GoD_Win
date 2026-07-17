//
//  File.swift
//  
//
//  Created by Stars Momodu on 28/05/2022.
//

import Foundation

public struct File: PathRepresentable, Hashable, Equatable {
    public let path: String
    
    public init(_ path: String) {
        self.path = path
    }
    
    public var fileType: String? {
        let ext = path.fileExtension
        return ext.isEmpty ? nil : ext
    }
    
    public var fileName: String {
        name
    }
}

extension File: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String
    
    public init(stringLiteral value: Self.StringLiteralType) {
        self.init(value)
    }
}


extension File: Comparable {
    public static func < (lhs: File, rhs: File) -> Bool {
        return lhs.path < rhs.path
    }
}

extension File: Codable {
    enum CodingKeys: String, CodingKey {
        case path
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(path)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let path = try container.decode(String.self)
        self.init(path)
    }
}

extension [File] {
    public func withExtension(_ ext: String) -> [File] {
        let cleanExtension = ext.removingOccurences(of: ".")
        return self.filter { $0.fileType == cleanExtension }
    }
}

/// A `File` reference paired with its contents. Used as the common
/// currency for `FileFormat` inputs/outputs and anywhere else a blob
/// needs to travel with its destination/source path.
public struct FileData {
    public let file: File
    public let data: GoDData

    public init(file: File, data: GoDData) {
        self.file = file
        self.data = data
    }

    /// Convenience: accept a bare filename and wrap it as a `File`.
    public init(fileName: String, data: GoDData) {
        self.init(file: File(fileName), data: data)
    }

    /// Path-level filename of the backing `File`.
    public var fileName: String { file.fileName }
}
