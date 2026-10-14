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
        let cleanPath = Self.clean(path)
        if !Self.isValidClean(cleanPath) {
            preconditionFailure("Folder path must be absolute (/...), relative (./... or ../...), or the current directory (. or ..): got \"\(path)\"")
        }
        self.path = cleanPath
    }

    /// Whether `init` accepts `path`. Code that takes paths from outside
    /// (config JSON, MCP arguments) checks this first and reports an error,
    /// rather than letting `init` trap and take the whole process down.
    public static func isValidPath(_ path: String) -> Bool {
        isValidClean(clean(path))
    }

    private static func clean(_ path: String) -> String {
        var cleanPath = path
        if cleanPath.last == "/", cleanPath != "/" {
            cleanPath.removeLast()
        }
        return cleanPath
    }

    private static func isValidClean(_ path: String) -> Bool {
        path.first == "/"
            || path.startsWith("../")
            || path.startsWith("./")
            || path == ".."
            || path == "."
    }

    public var folderName: String {
        return name.isEmpty ? "/" : name
    }

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
    /// Supports leading `..` and `.` components on `relativePath`.
    ///
    /// `..` that walks past the top is handled rather than trapped: on an
    /// absolute receiver it clamps at `/`, on a relative receiver it
    /// accumulates as further `..` components (ordinary path semantics).
    /// The result is never the empty string — a fully-consumed relative
    /// path collapses to `.`.
    public func folder(_ relativePath: String) -> Folder {
        let isAbsolute = self.path.startsWith("/")

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

        // A leading `.` is only a "this is relative" marker, not a real
        // component — drop it here and re-apply the prefix on the way out.
        if firstComponents.first == "." {
            firstComponents.removeFirst()
        }

        while let next = lastComponents.first, next == ".." || next == "." {
            lastComponents.removeFirst()
            guard next == ".." else { continue }

            if let tail = firstComponents.last, tail != ".." {
                // Ordinary parent step.
                firstComponents.removeLast()
            } else if !isAbsolute {
                // Walked off the top of a relative path — keep the `..`.
                firstComponents.append("..")
            }
            // Absolute path already at the root: `..` clamps to `/`.
        }

        let components = (firstComponents + lastComponents).joined(separator: "/")
        if isAbsolute {
            return Folder("/" + components)
        }
        if components.isEmpty {
            return Folder(".")
        }
        // `../…` is already a legal relative form; anything else needs the
        // explicit `./` prefix to satisfy `Folder.init`.
        return Folder(components.startsWith("..") ? components : "./" + components)
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
        #if os(Windows)
        // A config may spell an absolute path natively (`C:\...`); logical
        // paths pass through unchanged.
        let logical = PlatformPath.isNativeSpelling(path) ? PlatformPath.logical(from: path) : path
        #else
        let logical = path
        #endif
        guard Self.isValidPath(logical) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Folder path must be absolute (/...) or relative (./... or ../...): got \"\(path)\""
            )
        }
        self.init(logical)
    }
}
