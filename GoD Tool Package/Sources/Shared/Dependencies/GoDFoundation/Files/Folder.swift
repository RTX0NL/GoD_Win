//
//  Folder.swift
//
//
//  Created by Stars Momodu on 31/05/2022.
//

import Foundation

public struct Folder: PathRepresentable, Hashable, Equatable {
    public let path: String

    public init(_ path: String) {
        var cleanPath = path
        if cleanPath.last == "/", cleanPath != "/" {
            cleanPath.removeLast()
        }
        if cleanPath.first != "/",
           !cleanPath.startsWith("../"),
           !cleanPath.startsWith("./"),
           cleanPath != "..",
           cleanPath != "." {
            preconditionFailure("Folder path must be absolute (/...), relative (./... or ../...), or the current directory (. or ..): got \"\(path)\"")
        }
        self.path = cleanPath
    }

    public var folderName: String {
        return name.isEmpty ? "/" : name
    }

    /// Get a file by appending a relative path string to this folder
    public func file(_ relativePath: String) -> File {
        var first = self.path
        if first.last == "/" {
            first.removeLast()
        }

        var last = relativePath
        if last.first == "/" {
            last.removeFirst()
        }

        return File(first + "/" + last)
    }

    /// Get a folder by resolving a relative path string against this folder.
    /// Supports `..` and `.` path components.
    public func folder(_ relativePath: String) -> Folder {
        var first = self.path
        if first.last == "/" {
            first.removeLast()
        }
        var last = relativePath
        if last.first == "/" {
            last.removeFirst()
        }

        var firstComponents = first.split(separator: "/")
        var lastComponents = last.split(separator: "/")

        while lastComponents.first == ".." || lastComponents.first == "." {
            if lastComponents.first == ".." {
                firstComponents.removeLast()
            }
            lastComponents.removeFirst()
        }

        let prefix = self.path.startsWith("/") ? "/" : ""
        let path = prefix + (firstComponents + lastComponents).joined(separator: "/")
        return Folder(path)
    }
}

extension Folder: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String

    public init(stringLiteral value: Self.StringLiteralType) {
        self.init(value)
    }
}

extension Folder: Comparable {
    public static func < (lhs: Folder, rhs: Folder) -> Bool {
        return lhs.path < rhs.path
    }
}

extension Folder: Codable {
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
