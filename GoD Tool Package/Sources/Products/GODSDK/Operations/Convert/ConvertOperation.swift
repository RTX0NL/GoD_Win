//
//  ConvertOperation.swift
//  GODOps
//

import Foundation
import GoDFoundation
import Structs
import GoDEngine
import GeniusSonority

extension Convert {
    static func run(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        for operation in config.operations.enabledEntries {
            switch operation {
            case let .decodeFile(inputFile, outputFolder, overwrite, format):
                try decodeFile(inputFile: inputFile, outputFolder: outputFolder,
                               overwrite: overwrite, format: format, fileSystem: fileSystem)

            case let .encodeFile(inputFolder, outputFolder, overwrite, format):
                try encodeFile(inputFolder: inputFolder, outputFolder: outputFolder,
                               overwrite: overwrite, format: format, fileSystem: fileSystem)

            case let .decodeStruct(inputFile, outputFolder, overwrite, structName, engines, fileOffset):
                try decodeStruct(inputFile: inputFile, outputFolder: outputFolder, overwrite: overwrite,
                                 structName: structName, engineFolders: engines, fileOffset: fileOffset ?? 0,
                                 fileSystem: fileSystem, logger: logger)

            case let .encodeStruct(inputFile, outputFolder, overwrite, structName, engines, insertOffset):
                try encodeStruct(inputFile: inputFile, outputFolder: outputFolder, overwrite: overwrite,
                                 structName: structName, engineFolders: engines, insertOffset: insertOffset,
                                 fileSystem: fileSystem, logger: logger)

            case let .decodeStructTable(inputFile, outputFolder, overwrite, structName, engines, fileOffset, count):
                try decodeStructTable(inputFile: inputFile, outputFolder: outputFolder, overwrite: overwrite,
                                      structName: structName, engineFolders: engines, fileOffset: fileOffset ?? 0,
                                      count: count, fileSystem: fileSystem, logger: logger)

            case let .encodeStructTable(inputFile, outputFolder, overwrite, structName, engines, insertOffset):
                try encodeStructTable(inputFile: inputFile, outputFolder: outputFolder, overwrite: overwrite,
                                      structName: structName, engineFolders: engines, insertOffset: insertOffset,
                                      fileSystem: fileSystem, logger: logger)
            }
        }
    }

    // MARK: - File formats

    private static func decodeFile(
        inputFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        format: FileFormatSelection,
        fileSystem: FileSystemTree
    ) throws {
        guard let bytes = fileSystem.readFile(at: inputFile)?.allData else {
            throw ConvertErrors.inputFileNotFound(file: inputFile, .init())
        }
        // The format names the game where the extension alone is ambiguous
        // (`.fnt`), so it also decides which engine's registry serves it —
        // never the bytes.
        let registry = format.registry
        let stemCandidate = inputFile.fileName.withoutExtensions
        let stem = stemCandidate.isEmpty ? format.fileExtension : stemCandidate

        let artifacts: [FileData]
        if let variant = format.msgVariant {
            // The registry's `.msg` handler always decodes as XD; go direct
            // so the requested variant drives the string rendering.
            artifacts = try MSGFile(binary: bytes, variant: variant, name: stem).outputs
        } else {
            guard let handler = registry.handler(for: format.fileExtension) else {
                throw FileFormatRegistry.RegistryError.unregistered(ext: format.fileExtension)
            }
            var inputs = [FileData(file: File("\(stem).\(format.fileExtension)"), data: bytes)]
            if let dataExtension = format.pairedDataExtension {
                // Paired format: read the data half sitting next to the
                // header input (same folder, same stem, swapped extension).
                let dataFile = inputFile.parentFolder?.file("\(stem).\(dataExtension)")
                    ?? File("\(stem).\(dataExtension)")
                guard let dataBytes = fileSystem.readFile(at: dataFile)?.allData else {
                    throw ConvertErrors.inputFileNotFound(file: dataFile, .init())
                }
                inputs.append(FileData(file: File("\(stem).\(dataExtension)"), data: dataBytes))
            }
            artifacts = try handler.dump(inputs)
        }
        try write(artifacts: artifacts, into: outputFolder, fileSystem: fileSystem, overwrite: overwrite)
    }

    private static func encodeFile(
        inputFolder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        format: FileFormatSelection,
        fileSystem: FileSystemTree
    ) throws {
        let registry = format.registry
        // Rebuild reads the whole artifact bundle (JSON manifest + companions)
        // and reconstructs the format's binaries; the msg variant is recovered
        // from its JSON so no selection variant is needed here.
        let binaries = try registry.build(extension: format.fileExtension, from: inputFolder, fileSystem: fileSystem)
        try write(artifacts: binaries, into: outputFolder, fileSystem: fileSystem, overwrite: overwrite)
    }

    // MARK: - Structs

    private static func decodeStruct(
        inputFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        structName: String,
        engineFolders: [Folder],
        fileOffset: Int,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let bytes = fileSystem.readFile(at: inputFile)?.allData else {
            throw ConvertErrors.inputFileNotFound(file: inputFile, .init())
        }
        let engine = try structEngine(combining: engineFolders, structName: structName, fileSystem: fileSystem, logger: logger)
        let definition: StructDefinition = try engine.getStruct(structName)
        guard definition.length > 0 else {
            throw ConvertErrors.emptyStruct(structName: structName, .init())
        }
        let region = try window(of: bytes, structName: structName, offset: fileOffset, length: definition.length)
        let parsed = StructData(definition: definition, data: region)
        let outFile = outputFolder.file("\(inputFile.fileName.withoutExtensions).json")
        try fileSystem.encodeJSON(parsed, to: outFile, overwrite: overwrite)
    }

    private static func encodeStruct(
        inputFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        structName: String,
        engineFolders: [Folder],
        insertOffset: Int?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let jsonBytes = fileSystem.readFile(at: inputFile)?.allData else {
            throw ConvertErrors.inputFileNotFound(file: inputFile, .init())
        }
        let engine = try structEngine(combining: engineFolders, structName: structName, fileSystem: fileSystem, logger: logger)
        let definition: StructDefinition = try engine.getStruct(structName)
        let parsed = try StructData(definition: definition, json: jsonBytes)
        let binary = GoDData(byteStream: parsed.data.rawBytes, byteOrder: .big)
        let outFile = outputFolder.file("\(inputFile.fileName.withoutExtensions).bin")
        try write(binary, to: outFile, insertOffset: insertOffset, overwrite: overwrite,
                  fileSystem: fileSystem, logger: logger)
    }

    private static func decodeStructTable(
        inputFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        structName: String,
        engineFolders: [Folder],
        fileOffset: Int,
        count: Int?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let bytes = fileSystem.readFile(at: inputFile)?.allData else {
            throw ConvertErrors.inputFileNotFound(file: inputFile, .init())
        }
        let engine = try structEngine(combining: engineFolders, structName: structName, fileSystem: fileSystem, logger: logger)
        let definition: StructDefinition = try engine.getStruct(structName)
        let entrySize = definition.length
        guard entrySize > 0 else {
            throw ConvertErrors.emptyStruct(structName: structName, .init())
        }
        let entries: Int
        if let count {
            guard count >= 0 else {
                throw ConvertErrors.invalidCount(structName: structName, count: count, .init())
            }
            entries = count
        } else {
            // No count: tile from the offset to the end of the file, and the
            // struct must tile that span exactly — a partial trailing entry
            // is a mismatch, not something to silently drop.
            guard fileOffset >= 0, fileOffset <= bytes.length else {
                throw ConvertErrors.windowOutOfRange(
                    structName: structName, offset: fileOffset, length: entrySize, dataSize: bytes.length, .init())
            }
            let available = bytes.length - fileOffset
            guard available % entrySize == 0 else {
                throw ConvertErrors.structDoesNotTile(
                    structName: structName, structSize: entrySize, offset: fileOffset, dataSize: available, .init())
            }
            entries = available / entrySize
        }
        let region = try window(of: bytes, structName: structName, offset: fileOffset, length: entries * entrySize)
        var rows: [StructData] = []
        rows.reserveCapacity(entries)
        for i in 0..<entries {
            let row = region.read(atAddress: i * entrySize, length: entrySize)
                ?? GoDData(length: entrySize, byteOrder: .big)
            rows.append(StructData(definition: definition, data: row))
        }
        let outFile = outputFolder.file("\(inputFile.fileName.withoutExtensions).json")
        try fileSystem.encodeJSON(rows, to: outFile, overwrite: overwrite)
    }

    private static func encodeStructTable(
        inputFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        structName: String,
        engineFolders: [Folder],
        insertOffset: Int?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let jsonBytes = fileSystem.readFile(at: inputFile)?.allData else {
            throw ConvertErrors.inputFileNotFound(file: inputFile, .init())
        }
        let engine = try structEngine(combining: engineFolders, structName: structName, fileSystem: fileSystem, logger: logger)
        let definition: StructDefinition = try engine.getStruct(structName)
        let root = try JSONSerialization.jsonObject(with: jsonBytes.data)
        guard let elements = root as? [Any] else {
            throw ConvertErrors.notAStructTable(file: inputFile, .init())
        }
        var out: [UInt8] = []
        for element in elements {
            let elementData = try JSONSerialization.data(withJSONObject: element)
            let parsed = try StructData(
                definition: definition,
                json: GoDData(byteStream: [UInt8](elementData), byteOrder: .big)
            )
            out.append(contentsOf: parsed.data.rawBytes)
        }
        let binary = GoDData(byteStream: out, byteOrder: .big)
        let outFile = outputFolder.file("\(inputFile.fileName.withoutExtensions).bin")
        try write(binary, to: outFile, insertOffset: insertOffset, overwrite: overwrite,
                  fileSystem: fileSystem, logger: logger)
    }

    /// The `length` bytes at `offset`. Everything outside that window is
    /// ignored; a window that isn't wholly inside the input is an error
    /// rather than a short read.
    private static func window(of bytes: GoDData, structName: String, offset: Int, length: Int) throws -> GoDData {
        guard offset >= 0, length >= 0, offset + length <= bytes.length,
              let region = bytes.read(atAddress: offset, length: length) else {
            throw ConvertErrors.windowOutOfRange(
                structName: structName, offset: offset, length: length, dataSize: bytes.length, .init())
        }
        return region
    }

    /// Writes an encoded binary. With `insertOffset` and an existing output
    /// file, the bytes are patched into that file in place — the patch has
    /// to sit wholly inside it, and `overwrite` doesn't apply because
    /// rewriting the file is the point. Otherwise the file is written whole.
    private static func write(
        _ binary: GoDData,
        to outFile: File,
        insertOffset: Int?,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let insertOffset else {
            try fileSystem.writeFile(binary, at: outFile, overwrite: overwrite)
            return
        }
        guard let existing = fileSystem.readFile(at: outFile)?.allData else {
            logger?.log(.warning(
                "\(outFile.path) doesn't exist, so insertOffset \(insertOffset) has nothing to patch into; "
                + "writing the file whole"
            ))
            try fileSystem.writeFile(binary, at: outFile, overwrite: overwrite)
            return
        }
        guard insertOffset >= 0, insertOffset + binary.length <= existing.length else {
            throw ConvertErrors.insertOutOfRange(
                file: outFile, offset: insertOffset, length: binary.length, fileSize: existing.length, .init())
        }
        existing.write(binary, atAddress: UInt(insertOffset))
        try fileSystem.writeFile(existing, at: outFile, overwrite: true)
    }

    /// The engine a struct name resolves against: every listed folder,
    /// combined in order. Mirrors the DOL/REL type-map path so a struct can
    /// reference an enum or sub-struct another engine declares, and so a
    /// name two engines both declare is called out rather than silently
    /// resolving to the first one.
    private static func structEngine(
        combining engineFolders: [Folder],
        structName: String,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> GenericEngine {
        guard !engineFolders.isEmpty else {
            throw ConvertErrors.noEngines(structName: structName, .init())
        }
        let engine = try GenericEngine(combining: engineFolders, in: fileSystem)
        let shadowed = engine.shadowedNames
        if !shadowed.structs.isEmpty {
            logger?.log(.warning(
                "Struct name(s) declared by more than one engine; the earliest listed engine wins: "
                + shadowed.structs.joined(separator: ", ")
            ))
        }
        if !shadowed.enums.isEmpty {
            logger?.log(.warning(
                "Enum name(s) declared by more than one engine; the earliest listed engine wins: "
                + shadowed.enums.joined(separator: ", ")
            ))
        }
        return engine
    }

    // MARK: - Helpers

    /// Writes each artifact into `folder`, resolving nested relative paths
    /// (mirrors `FileFormatRegistry`'s own artifact placement).
    private static func write(
        artifacts: [FileData],
        into folder: Folder,
        fileSystem: FileSystemTree,
        overwrite: Bool
    ) throws {
        for artifact in artifacts {
            let outFile = resolve(artifact.file, in: folder)
            try fileSystem.writeFile(artifact.data, at: outFile, overwrite: overwrite)
        }
    }

    private static func resolve(_ relative: File, in folder: Folder) -> File {
        var path = relative.path
        if path.hasPrefix("/") { path.removeFirst() }
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return folder.file(path) }
        var current = folder
        for part in parts.dropLast() { current = current.folder(part) }
        return current.file(parts.last!)
    }
}
