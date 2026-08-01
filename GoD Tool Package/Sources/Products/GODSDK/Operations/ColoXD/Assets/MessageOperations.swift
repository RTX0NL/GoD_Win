//
//  MessageOperations.swift
//  GODOps
//
//  Message tables (`.msg`) <-> JSON.
//
//  The binary layout is shared between Colosseum and XD; only the string
//  rendering differs, so the dump side has to be told which variant it is
//  reading. The build side doesn't — the JSON records it.
//

import Foundation
import GoDFoundation
import GeniusSonority

extension ColoXD {

    static func dumpMessages(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        variant: String,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let parsedVariant = MSGFile.Variant(configValue: variant)
        try dumpBatch(
            in: folder,
            matching: { $0.fileType == "msg" },
            label: "message",
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                try messageArtifacts(file: file, stem: stem, variant: parsedVariant, fileSystem: fileSystem)
            }
        )
    }

    static func dumpMessage(
        msgFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        variant: String,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let parsedVariant = MSGFile.Variant(configValue: variant)
        try dumpSingle(
            file: msgFile,
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                try messageArtifacts(file: file, stem: stem, variant: parsedVariant, fileSystem: fileSystem)
            }
        )
    }

    static func buildMessages(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        try buildBatch(
            in: folder,
            matching: { $0.fileType == "json" },
            stem: { $0.fileName.withoutExtensions },
            label: "message",
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            binaries: { manifest, stem in
                [try messageBinary(manifest: manifest, stem: stem, fileSystem: fileSystem)]
            }
        )
    }

    static func buildMessage(
        jsonFile: File,
        outputFile: File,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let stem = outputFile.fileName.withoutExtensions
        let binary = try messageBinary(manifest: jsonFile, stem: stem, fileSystem: fileSystem)
        try fileSystem.writeFile(binary.data, at: outputFile, overwrite: overwrite)
        logger?.log(.info("  \(stem) → \(outputFile.fileName)"))
    }

    // MARK: - Format work

    private static func messageArtifacts(
        file: File,
        stem: String,
        variant: MSGFile.Variant,
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        guard let data = fileSystem.readFile(at: file) else {
            throw FSTErrors.fileNotFound(file, .init())
        }
        var parsed = try MSGFile(binary: data, variant: variant)
        parsed.name = stem
        return try parsed.outputs
    }

    private static func messageBinary(
        manifest: File,
        stem: String,
        fileSystem: FileSystemTree
    ) throws -> FileData {
        guard let manifestData = fileSystem.readFile(at: manifest) else {
            throw FSTErrors.fileNotFound(manifest, .init())
        }
        let file = try MSGFile(outputs: [
            FileData(file: File("\(stem).msg.json"), data: manifestData)
        ])
        return FileData(fileName: "\(stem).msg", data: try file.binaryData)
    }
}
