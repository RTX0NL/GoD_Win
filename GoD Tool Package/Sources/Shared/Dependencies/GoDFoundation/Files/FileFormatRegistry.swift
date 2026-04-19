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
        /// Parse `bytes` as this format and return its output artifacts.
        public let dump: (GoDData) throws -> [String: GoDData]
        /// Reconstruct the binary from a set of output artifacts.
        public let build: ([String: GoDData]) throws -> GoDData
        /// The format type, for diagnostics.
        public let formatType: FileFormat.Type
    }

    public private(set) var handlers: [String: Handler] = [:]

    public init() {}

    /// Register a format under a file extension (lowercased, no leading dot).
    public mutating func register<F: FileFormat>(_ ext: String, _ type: F.Type) {
        let key = ext.lowercased()
        handlers[key] = Handler(
            dump: { bytes in try F(binary: bytes).outputs },
            build: { outputs in try F(outputs: outputs).binaryData },
            formatType: F.self
        )
    }

    public func handler(for ext: String) -> Handler? {
        handlers[ext.lowercased()]
    }

    /// True if a handler is registered for the given extension.
    public func isRegistered(_ ext: String) -> Bool {
        handlers[ext.lowercased()] != nil
    }

    // MARK: - Filesystem convenience

    /// Dump `bytes` as `ext` into `folder`, writing each output artifact under
    /// `<baseName>.<key>` when `key` has no slash, or `<baseName>/<key>`
    /// otherwise. Returns the list of written files.
    @discardableResult
    public func dump(
        bytes: GoDData,
        extension ext: String,
        baseName: String,
        into folder: Folder,
        fileSystem: FileSystemTree,
        overwrite: Bool = true
    ) throws -> [File] {
        guard let handler = handler(for: ext) else {
            throw RegistryError.unregistered(ext: ext)
        }
        let artifacts = try handler.dump(bytes)
        var written: [File] = []
        for (key, data) in artifacts {
            let outFile = file(for: baseName, key: key, in: folder)
            if !fileSystem.writeFile(data, at: outFile, overwrite: overwrite) {
                throw RegistryError.writeFailed(file: outFile)
            }
            written.append(outFile)
        }
        return written
    }

    /// Read every artifact belonging to `baseName` under `folder` and rebuild
    /// the binary via the handler registered for `ext`. Artifacts are keyed
    /// by the same suffix pattern `dump` uses.
    public func build(
        extension ext: String,
        baseName: String,
        from folder: Folder,
        fileSystem: FileSystemTree
    ) throws -> GoDData {
        guard let handler = handler(for: ext) else {
            throw RegistryError.unregistered(ext: ext)
        }
        let outputs = try readArtifacts(baseName: baseName, in: folder, fileSystem: fileSystem)
        return try handler.build(outputs)
    }

    // MARK: - Internals

    /// Resolves the on-disc path for a single artifact.
    /// - `key = "json"` → `<folder>/<baseName>.json`
    /// - `key = "textures/tex_03.png"` → `<folder>/<baseName>/textures/tex_03.png`
    private func file(for baseName: String, key: String, in folder: Folder) -> File {
        if key.contains("/") {
            let parts = key.split(separator: "/").map(String.init)
            var f = folder.folder(baseName)
            for part in parts.dropLast() { f = f.folder(part) }
            return f.file(parts.last!)
        } else {
            return folder.file("\(baseName).\(key)")
        }
    }

    /// Walks `folder` and collects every artifact that belongs to `baseName`,
    /// returning them keyed by the suffix shape `dump` writes with.
    private func readArtifacts(
        baseName: String,
        in folder: Folder,
        fileSystem: FileSystemTree
    ) throws -> [String: GoDData] {
        var outputs: [String: GoDData] = [:]

        // Flat files: <baseName>.<key>
        if let folderMeta = fileSystem.inspectFolder(at: folder) {
            for file in folderMeta.files where file.fileName.hasPrefix("\(baseName).") {
                guard let data = fileSystem.readFile(at: file) else { continue }
                let key = String(file.fileName.dropFirst(baseName.count + 1))
                outputs[key] = data
            }
        }

        // Nested artifacts under <folder>/<baseName>/...
        let nested = folder.folder(baseName)
        if fileSystem.inspectFolder(at: nested) != nil {
            collectNested(prefix: "", in: nested, fileSystem: fileSystem, into: &outputs)
        }

        if outputs.isEmpty {
            throw RegistryError.noArtifactsFound(baseName: baseName, folder: folder.path)
        }
        return outputs
    }

    private func collectNested(
        prefix: String,
        in folder: Folder,
        fileSystem: FileSystemTree,
        into outputs: inout [String: GoDData]
    ) {
        guard let meta = fileSystem.inspectFolder(at: folder) else { return }
        for file in meta.files {
            let key = prefix.isEmpty ? file.fileName : "\(prefix)/\(file.fileName)"
            if let data = fileSystem.readFile(at: file) {
                outputs[key] = data
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
        case noArtifactsFound(baseName: String, folder: String)

        public var description: String {
            switch self {
            case .unregistered(let ext):
                return "FileFormatRegistry: no handler registered for extension '\(ext)'"
            case .writeFailed(let file):
                return "FileFormatRegistry: failed to write artifact at \(file.path)"
            case .noArtifactsFound(let baseName, let folder):
                return "FileFormatRegistry: no artifacts found for '\(baseName)' under '\(folder)'"
            }
        }
    }
}
