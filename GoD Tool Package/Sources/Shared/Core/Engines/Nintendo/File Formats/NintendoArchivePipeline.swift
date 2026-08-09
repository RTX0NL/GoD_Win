//
//  NintendoArchivePipeline.swift
//
//  Moves an archive between its packed bytes and a project folder: the
//  contents as ordinary editable files, plus a manifest holding everything
//  about the container the contents don't imply.
//
//  Layout for an archive called `homeBtn.arc` unpacked into `<folder>`:
//
//      <folder>/homeBtn.arc.json      the manifest
//      <folder>/homeBtn/…             the contents
//
//  A U8's contents keep the directory tree they had inside the archive. A
//  NARC's are laid out flat: by name where it has a name table, and by
//  zero-padded index where it doesn't, because there the index *is* the
//  file's identity and sorting by name has to keep it recoverable.
//

import Foundation
import GoDFoundation

public extension NintendoEngine {

    struct ArchiveUnpackResult {
        public let registry: NintendoArchiveRegistry
        public let manifestFile: File
        public let writtenFiles: [File]
    }

    // MARK: - Unpack

    /// Reads `data` as whichever archive its magic says it is and writes the
    /// contents plus a manifest into `folder`.
    @discardableResult
    func unpackArchive(
        data: GoDData,
        archiveName: String,
        into folder: Folder,
        fileSystem: FileSystemTree,
        overwrite: Bool = true,
        logger: Logger? = nil
    ) throws -> ArchiveUnpackResult {
        guard let signature = NintendoArchiveSignature.detect(data) else {
            throw NintendoArchiveError.unrecognizedMagic(found: Array(data.rawBytes.prefix(4)))
        }

        let contents = folder.folder(NintendoArchiveRegistry.contentsFolderName(forArchive: archiveName))
        var entries: [NintendoArchiveRegistry.Entry] = []
        var written: [File] = []
        var rawNameTable: [UInt8]?

        switch signature.format {
        case .u8:
            let archive = try U8Archive(data: data, engine: self)
            for node in archive.nodes {
                guard case let .file(payload) = node.kind else {
                    entries.append(.init(archivePath: node.path, file: nil, isDirectory: true))
                    continue
                }
                let destination = contents.file(node.path)
                try fileSystem.writeFile(payload, at: destination, overwrite: overwrite)
                written.append(destination)
                entries.append(
                    .init(archivePath: node.path, file: relative(destination, to: folder), isDirectory: false)
                )
            }

        case .narc:
            let archive = try NARCArchive(data: data, engine: self)
            rawNameTable = archive.rawNameTable
            for (index, entry) in archive.entries.enumerated() {
                let name = entry.name ?? Self.indexedEntryName(index)
                let destination = contents.file(name)
                try fileSystem.writeFile(entry.data, at: destination, overwrite: overwrite)
                written.append(destination)
                entries.append(
                    .init(archivePath: entry.name, file: relative(destination, to: folder), isDirectory: false)
                )
            }
        }

        let registry = NintendoArchiveRegistry(
            format: signature.format,
            byteOrder: signature.byteOrder,
            archiveName: archiveName,
            entries: entries,
            rawNameTable: rawNameTable
        )
        let manifestFile = folder.file(NintendoArchiveRegistry.manifestName(forArchive: archiveName))
        try fileSystem.writeJSON(registry, at: manifestFile, overwrite: overwrite)

        logger?.log(.info("Unpacked \(archiveName) — \(signature.description), \(written.count) files"))
        return ArchiveUnpackResult(registry: registry, manifestFile: manifestFile, writtenFiles: written)
    }

    // MARK: - Pack

    /// Rebuilds an archive from the manifest at `manifestFile` and the files
    /// beside it.
    func packArchive(
        manifestFile: File,
        fileSystem: FileSystemTree
    ) throws -> GoDData {
        let registry: NintendoArchiveRegistry = try fileSystem.decodeJSON(from: manifestFile)
        guard let folder = manifestFile.parentFolder else {
            throw FSTErrors.fileNotFound(manifestFile, .init())
        }
        return try packArchive(registry: registry, sourceFolder: folder, fileSystem: fileSystem)
    }

    /// Rebuilds an archive from an already-decoded manifest whose entry
    /// paths resolve against `sourceFolder`.
    func packArchive(
        registry: NintendoArchiveRegistry,
        sourceFolder: Folder,
        fileSystem: FileSystemTree
    ) throws -> GoDData {
        func payload(_ entry: NintendoArchiveRegistry.Entry) throws -> GoDData {
            guard let file = entry.file else {
                throw NintendoArchiveError.malformed(
                    format: registry.format.displayName,
                    reason: "entry \"\(entry.archivePath ?? "?")\" has no file to read"
                )
            }
            let path = sourceFolder.file(file.path)
            guard let data = fileSystem.readFile(at: path)?.allData else {
                throw FSTErrors.fileNotFound(path, .init())
            }
            return data
        }

        switch registry.format {
        case .u8:
            var nodes: [U8Archive.Node] = []
            for entry in registry.entries {
                guard let path = entry.archivePath else {
                    throw NintendoArchiveError.malformed(
                        format: "U8", reason: "an entry has no path inside the archive"
                    )
                }
                nodes.append(
                    U8Archive.Node(
                        path: path,
                        kind: entry.isDirectory ? .directory : .file(try payload(entry))
                    )
                )
            }
            return try U8Archive(byteOrder: registry.byteOrder, nodes: nodes).data(engine: self)

        case .narc:
            let entries = try registry.entries.map { entry in
                NARCArchive.Entry(name: entry.archivePath, data: try payload(entry))
            }
            return try NARCArchive(
                byteOrder: registry.byteOrder,
                entries: entries,
                rawNameTable: registry.rawNameTable
            ).data(engine: self)
        }
    }

    // MARK: - Helpers

    /// Name for a NARC entry that has none of its own. Zero-padded so a
    /// directory listing stays in index order, which for these archives is
    /// the order that carries the meaning.
    static func indexedEntryName(_ index: Int) -> String {
        String(format: "%04d.bin", index)
    }

    /// A file's path relative to `folder`, which is what the manifest
    /// stores so the whole unpacked folder can be moved or renamed.
    private func relative(_ file: File, to folder: Folder) -> File {
        let base = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        guard file.path.hasPrefix(base) else { return File(file.fileName) }
        return File(String(file.path.dropFirst(base.count)))
    }
}
