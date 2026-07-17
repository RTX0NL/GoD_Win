//
//  FileFormatRegistry.swift
//
//
//  Created by Stars Momodu on 2026-04-17.
//

import Foundation

/// Dispatches bytes/artifacts to the right `FileFormat` based on a file
/// extension. Not a singleton — construct one and inject it where dump or
/// build routing is needed (disassembly operations, ColoXD ops, tests).
public struct FileFormatRegistry {

    public struct Handler {
        /// Parse a set of raw game-side binaries as this format and return
        /// its editable output artifacts (JSON manifest + companions).
        public let dump: ([FileData]) throws -> [FileData]
        /// Reconstruct the raw game-side binaries from an artifact bundle.
        public let build: ([FileData]) throws -> [FileData]
        /// The format type, for diagnostics.
        public let formatType: FileFormat.Type
    }

    public private(set) var handlers: [String: Handler] = [:]

    public init() {}

    /// Register a format under a file extension (lowercased, no leading dot).
    public mutating func register<F: FileFormat>(_ ext: String, _ type: F.Type) {
        let key = ext.lowercased()
        handlers[key] = Handler(
            dump: { binaries in try F(binaries: binaries).outputs },
            build: { outputs in try F(outputs: outputs).binaries },
            formatType: F.self
        )
    }

    public func handler(for ext: String) -> Handler? {
        handlers[ext.lowercased()]
    }

    /// Merge another registry's handlers into this one. Conflicting
    /// extensions are overwritten by `other`.
    public mutating func merge(_ other: FileFormatRegistry) {
        for (ext, handler) in other.handlers {
            handlers[ext] = handler
        }
    }

    /// True if a handler is registered for the given extension.
    public func isRegistered(_ ext: String) -> Bool {
        handlers[ext.lowercased()] != nil
    }

    // MARK: - Filesystem convenience

    /// Dump `bytes` as `ext` into `folder`, writing each output artifact at
    /// `<folder>/<key.path>`. Each format picks its own filenames — callers
    /// providing a shared folder should namespace by passing a per-source
    /// subfolder. Returns the list of written files.
    @discardableResult
    public func dump(
        bytes: GoDData,
        extension ext: String,
        into folder: Folder,
        fileSystem: FileSystemTree,
        overwrite: Bool = true
    ) throws -> [File] {
        try dump(
            binaries: [FileData(file: File("input.\(ext)"), data: bytes)],
            extension: ext,
            into: folder,
            fileSystem: fileSystem,
            overwrite: overwrite
        )
    }

    /// Multi-binary variant: pass paired inputs (e.g. ISF's ISH + ISD) as
    /// an ordered `[FileData]` list. Each entry's `file` is used only for
    /// name-stem recovery inside the format — the actual output layout is
    /// decided by the format itself.
    @discardableResult
    public func dump(
        binaries: [FileData],
        extension ext: String,
        into folder: Folder,
        fileSystem: FileSystemTree,
        overwrite: Bool = true
    ) throws -> [File] {
        guard let handler = handler(for: ext) else {
            throw RegistryError.unregistered(ext: ext)
        }
        let artifacts = try handler.dump(binaries)
        var written: [File] = []
        for artifact in artifacts {
            let outFile = resolve(artifact.file, in: folder)
            if !fileSystem.writeFile(artifact.data, at: outFile, overwrite: overwrite) {
                throw RegistryError.writeFailed(file: outFile)
            }
            written.append(outFile)
        }
        return written
    }

    /// Read every file under `folder` and rebuild the binaries via the
    /// handler registered for `ext`. Every regular file beneath `folder`
    /// becomes a `FileData` entry keyed by its path relative to `folder`.
    /// Returns the reconstructed binary list in the format's canonical
    /// order.
    public func build(
        extension ext: String,
        from folder: Folder,
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        guard let handler = handler(for: ext) else {
            throw RegistryError.unregistered(ext: ext)
        }
        let outputs = try readArtifacts(in: folder, fileSystem: fileSystem)
        return try handler.build(outputs)
    }

    /// Single-binary convenience for the common case.
    public func buildSingle(
        extension ext: String,
        from folder: Folder,
        fileSystem: FileSystemTree
    ) throws -> GoDData {
        let built = try build(extension: ext, from: folder, fileSystem: fileSystem)
        guard let first = built.first else {
            throw RegistryError.noArtifactsFound(folder: folder.path)
        }
        return first.data
    }

    // MARK: - Internals

    /// Resolves an artifact's relative path against a target folder.
    private func resolve(_ relative: File, in folder: Folder) -> File {
        var path = relative.path
        if path.hasPrefix("/") { path.removeFirst() }
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return folder.file(path) }
        var current = folder
        for part in parts.dropLast() { current = current.folder(part) }
        return current.file(parts.last!)
    }

    private func readArtifacts(
        in folder: Folder,
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        var outputs: [FileData] = []
        collectNested(prefix: "", in: folder, fileSystem: fileSystem, into: &outputs)
        if outputs.isEmpty {
            throw RegistryError.noArtifactsFound(folder: folder.path)
        }
        return outputs
    }

    private func collectNested(
        prefix: String,
        in folder: Folder,
        fileSystem: FileSystemTree,
        into outputs: inout [FileData]
    ) {
        guard let meta = fileSystem.inspectFolder(at: folder) else { return }
        for file in meta.files {
            let key = prefix.isEmpty ? file.fileName : "\(prefix)/\(file.fileName)"
            if let data = fileSystem.readFile(at: file) {
                outputs.append(FileData(file: File(key), data: data))
            }
        }
        for sub in meta.subFolders {
            let nextPrefix = prefix.isEmpty ? sub.folderName : "\(prefix)/\(sub.folderName)"
            collectNested(prefix: nextPrefix, in: sub, fileSystem: fileSystem, into: &outputs)
        }
    }

    // MARK: - Errors

    public enum RegistryError: Error, CustomStringConvertible {
        case unregistered(ext: String)
        case writeFailed(file: File)
        case noArtifactsFound(folder: String)

        public var description: String {
            switch self {
            case .unregistered(let ext):
                return "FileFormatRegistry: no handler registered for extension '\(ext)'"
            case .writeFailed(let file):
                return "FileFormatRegistry: failed to write artifact at \(file.path)"
            case .noArtifactsFound(let folder):
                return "FileFormatRegistry: no artifacts found under '\(folder)'"
            }
        }
    }
}
