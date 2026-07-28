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

            case let .decodeStruct(inputFile, outputFolder, overwrite, structName, engine):
                try decodeStruct(inputFile: inputFile, outputFolder: outputFolder, overwrite: overwrite,
                                 structName: structName, engineFolder: engine, fileSystem: fileSystem)

            case let .encodeStruct(inputFile, outputFolder, overwrite, structName, engine):
                try encodeStruct(inputFile: inputFile, outputFolder: outputFolder, overwrite: overwrite,
                                 structName: structName, engineFolder: engine, fileSystem: fileSystem)

            case let .decodeStructTable(inputFile, outputFolder, overwrite, structName, engine):
                try decodeStructTable(inputFile: inputFile, outputFolder: outputFolder, overwrite: overwrite,
                                      structName: structName, engineFolder: engine, fileSystem: fileSystem)

            case let .encodeStructTable(inputFile, outputFolder, overwrite, structName, engine):
                try encodeStructTable(inputFile: inputFile, outputFolder: outputFolder, overwrite: overwrite,
                                      structName: structName, engineFolder: engine, fileSystem: fileSystem)
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
        guard let bytes = fileSystem.readFile(at: inputFile) else {
            throw ConvertErrors.inputFileNotFound(file: inputFile, .init())
        }
        let engine = try GeniusSonorityEngine(from: format.geniusSonorityEngine, in: fileSystem)
        let registry = engine.fileFormats()
        let stemCandidate = inputFile.fileName.withoutExtensions
        let stem = stemCandidate.isEmpty ? format.fileExtension : stemCandidate

        let artifacts: [FileData]
        switch format {
        case let .msg(_, variant):
            // The registry's `.msg` handler always decodes as XD; go direct
            // so the requested variant drives the string rendering.
            artifacts = try MSGFile(binary: bytes, variant: variant, name: stem).outputs
        case .gtx, .atx, .fnt, .gsw, .ish, .thh:
            guard let handler = registry.handler(for: format.fileExtension) else {
                throw FileFormatRegistry.RegistryError.unregistered(ext: format.fileExtension)
            }
            var inputs = [FileData(file: File("\(stem).\(format.fileExtension)"), data: bytes)]
            if let dataExtension = format.pairedDataExtension {
                // Paired format: read the data half sitting next to the
                // header input (same folder, same stem, swapped extension).
                let dataFile = inputFile.parentFolder?.file("\(stem).\(dataExtension)")
                    ?? File("\(stem).\(dataExtension)")
                guard let dataBytes = fileSystem.readFile(at: dataFile) else {
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
        let engine = try GeniusSonorityEngine(from: format.geniusSonorityEngine, in: fileSystem)
        let registry = engine.fileFormats()
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
        engineFolder: Folder,
        fileSystem: FileSystemTree
    ) throws {
        guard let bytes = fileSystem.readFile(at: inputFile) else {
            throw ConvertErrors.inputFileNotFound(file: inputFile, .init())
        }
        let engine = try GenericEngine(from: engineFolder, in: fileSystem)
        let definition: StructDefinition = try engine.getStruct(structName)
        guard definition.length > 0 else {
            throw ConvertErrors.emptyStruct(structName: structName, .init())
        }
        guard bytes.length == definition.length else {
            throw ConvertErrors.structSizeMismatch(
                structName: structName, structSize: definition.length, dataSize: bytes.length, .init())
        }
        let parsed = StructData(definition: definition, data: bytes)
        let outFile = outputFolder.file("\(inputFile.fileName.withoutExtensions).json")
        try fileSystem.encodeJSON(parsed, to: outFile, overwrite: overwrite)
    }

    private static func encodeStruct(
        inputFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        structName: String,
        engineFolder: Folder,
        fileSystem: FileSystemTree
    ) throws {
        guard let jsonBytes = fileSystem.readFile(at: inputFile) else {
            throw ConvertErrors.inputFileNotFound(file: inputFile, .init())
        }
        let engine = try GenericEngine(from: engineFolder, in: fileSystem)
        let definition: StructDefinition = try engine.getStruct(structName)
        let parsed = try StructData(definition: definition, json: jsonBytes)
        let binary = GoDData(byteStream: parsed.data.rawBytes, byteOrder: .big)
        let outFile = outputFolder.file("\(inputFile.fileName.withoutExtensions).bin")
        try fileSystem.writeFile(binary, at: outFile, overwrite: overwrite)
    }

    private static func decodeStructTable(
        inputFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        structName: String,
        engineFolder: Folder,
        fileSystem: FileSystemTree
    ) throws {
        guard let bytes = fileSystem.readFile(at: inputFile) else {
            throw ConvertErrors.inputFileNotFound(file: inputFile, .init())
        }
        let engine = try GenericEngine(from: engineFolder, in: fileSystem)
        let definition: StructDefinition = try engine.getStruct(structName)
        let entrySize = definition.length
        guard entrySize > 0 else {
            throw ConvertErrors.emptyStruct(structName: structName, .init())
        }
        // Entry count is the input size divided by the struct size, and the
        // struct must tile the input exactly — any remainder is an error.
        guard bytes.length % entrySize == 0 else {
            throw ConvertErrors.structDoesNotTile(
                structName: structName, structSize: entrySize, dataSize: bytes.length, .init())
        }
        let count = bytes.length / entrySize
        var rows: [StructData] = []
        rows.reserveCapacity(count)
        for i in 0..<count {
            let row = bytes.read(atAddress: i * entrySize, length: entrySize)
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
        engineFolder: Folder,
        fileSystem: FileSystemTree
    ) throws {
        guard let jsonBytes = fileSystem.readFile(at: inputFile) else {
            throw ConvertErrors.inputFileNotFound(file: inputFile, .init())
        }
        let engine = try GenericEngine(from: engineFolder, in: fileSystem)
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
        try fileSystem.writeFile(binary, at: outFile, overwrite: overwrite)
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
