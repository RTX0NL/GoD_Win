//
//  DeckOperations.swift
//  GODOps
//
//  XD trainer decks (`DeckData_*.bin`) <-> a folder per deck: one CSV per
//  record section, the trainer tag strings as JSON, and a manifest that
//  keeps the section order and the header words.
//
//  The records are read through the engines' struct definitions, so species,
//  items, moves and types come out by name. Padding is the one thing a CSV
//  doesn't carry, and every padding byte in the retail decks is zero; a
//  section that wouldn't come back byte for byte is kept as a `.bin` instead,
//  so an unmodified deck always rebuilds exactly.
//
//  A record section's count follows its CSV: the game reads each section's
//  count from its header, so rows can be added or removed.
//

import Foundation
import GoDFoundation
import GoDEngine
import Structs
import XD

extension ColoXD {

    /// Record sections and the struct each one's rows are. A tag not listed
    /// here is kept as bytes.
    static let deckRecordSections: [String: (structType: String, fileName: String)] = [
        "DTNR": ("DeckTrainer", "Trainers.csv"),
        "DPKM": ("DeckTrainerPokemon", "Pokemon.csv"),
        "DTAI": ("DeckTrainerAI", "AI.csv"),
        "DDPK": ("DeckShadowPokemon", "ShadowPokemon.csv"),
    ]
    static let deckStringsTag = "DSTR"
    static let deckStringsFileName = "Strings.json"

    /// `<stem>.deck.json`: everything about a deck that isn't in its section
    /// files.
    struct DeckManifest: Codable, Equatable {
        struct Section: Codable, Equatable {
            var tag: String
            var file: String
            /// The struct a CSV's rows are; absent for strings and bytes.
            var structType: String?
            /// The stored count, for sections whose count isn't their row
            /// count (strings and bytes). Absent for CSVs.
            var count: UInt32?
            var reserved: UInt32
        }
        var deckID: UInt32
        var reserved: UInt32
        var sections: [Section]
    }

    static func dumpXDDecks(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        engines: [Folder],
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let engine = try GenericEngine(combining: engines, in: fileSystem)
        try dumpBatch(
            in: folder,
            matching: { $0.fileName.hasPrefix("DeckData_") && $0.fileType == "bin" },
            label: "deck",
            outputFolder: outputFolder,
            layout: .perAssetFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                guard let data = fileSystem.readFile(at: file)?.allData else {
                    throw FSTErrors.fileNotFound(file, .init())
                }
                return try deckArtifacts(data.rawBytes, stem: stem, engine: engine, logger: logger)
            }
        )
    }

    static func buildXDDecks(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        engines: [Folder],
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let engine = try GenericEngine(combining: engines, in: fileSystem)
        try buildBatch(
            in: folder,
            matching: { $0.fileName.hasSuffix(".deck.json") },
            stem: { $0.fileName.withoutExtensions },
            label: "deck",
            outputFolder: outputFolder,
            layout: .perAssetFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            binaries: { manifest, stem in
                [FileData(
                    fileName: "\(stem).bin",
                    data: GoDData(byteStream: try deckBinary(manifest: manifest, engine: engine, fileSystem: fileSystem),
                                  byteOrder: .big)
                )]
            }
        )
    }

    // MARK: - Format work

    static func deckArtifacts(
        _ bytes: [UInt8],
        stem: String,
        engine: GenericEngine,
        logger: Logger?
    ) throws -> [FileData] {
        let deck = try XDDeck(bytes: bytes)
        var artifacts = [FileData]()
        var sections = [DeckManifest.Section]()
        for (index, section) in deck.sections.enumerated() {
            if let csv = try recordCSV(section, engine: engine) {
                let fileName = deckRecordSections[section.tag]!.fileName
                artifacts.append(FileData(fileName: fileName, data: GoDData(string: csv, format: .utf8)))
                sections.append(.init(tag: section.tag, file: fileName,
                                      structType: deckRecordSections[section.tag]!.structType,
                                      reserved: section.reserved))
            } else if section.tag == deckStringsTag, let strings = XDDeck.decodeStrings(section.body) {
                let json: GoDData = try prettyJSON(strings)
                artifacts.append(FileData(fileName: deckStringsFileName, data: json))
                sections.append(.init(tag: section.tag, file: deckStringsFileName,
                                      count: section.count, reserved: section.reserved))
            } else {
                // A tag this op doesn't know, or a section that wouldn't
                // come back byte for byte as CSV: its bytes are its source.
                let fileName = "\(index)-\(section.tag).bin"
                if deckRecordSections[section.tag] != nil || section.tag == deckStringsTag {
                    logger?.log(.warning("\(stem): \(section.tag) doesn't round-trip as text, kept as \(fileName)"))
                }
                artifacts.append(FileData(fileName: fileName,
                                          data: GoDData(byteStream: section.body, byteOrder: .big)))
                sections.append(.init(tag: section.tag, file: fileName,
                                      count: section.count, reserved: section.reserved))
            }
        }
        let manifest = DeckManifest(deckID: deck.deckID, reserved: deck.reserved, sections: sections)
        artifacts.append(FileData(fileName: "\(stem).deck.json", data: try prettyJSON(manifest)))
        return artifacts
    }

    /// A record section as CSV, or nil when it isn't one, its struct isn't in
    /// the engines, its size isn't a whole number of records, or the CSV
    /// wouldn't rebuild these exact bytes.
    private static func recordCSV(_ section: XDDeck.Section, engine: GenericEngine) throws -> String? {
        guard let (structType, _) = deckRecordSections[section.tag],
              let definition = try? engine.getStruct(structType) as StructDefinition,
              definition.length > 0,
              section.body.count % definition.length == 0,
              section.body.count / definition.length == Int(section.count) else {
            return nil
        }
        let rows = stride(from: 0, to: section.body.count, by: definition.length).map {
            StructData(definition: definition,
                       data: GoDData(byteStream: Array(section.body[$0 ..< $0 + definition.length]), byteOrder: .big))
        }
        let csv = try StructTableCSV.encode(entries: rows, definition: definition)
        let rebuilt = try StructTableCSV.decode(csv, definition: definition).entries.flatMap(\.data.rawBytes)
        return rebuilt == section.body ? csv : nil
    }

    static func deckBinary(manifest file: File, engine: GenericEngine, fileSystem: FileSystemTree) throws -> [UInt8] {
        guard let manifestData = fileSystem.readFile(at: file)?.allData else {
            throw FSTErrors.fileNotFound(file, .init())
        }
        let manifest = try JSONDecoder().decode(DeckManifest.self, from: Data(manifestData.rawBytes))
        let folder = file.parentFolder ?? Folder("/")

        var sections = [XDDeck.Section]()
        for entry in manifest.sections {
            let sectionFile = folder.file(entry.file)
            guard let data = fileSystem.readFile(at: sectionFile)?.allData else {
                throw DeckOpsError.missingSectionFile(sectionFile, .init())
            }
            if let structType = entry.structType {
                let definition = try engine.getStruct(structType) as StructDefinition
                let decoded = try StructTableCSV.decode(data.string(format: .utf8), definition: definition)
                sections.append(.init(tag: entry.tag, count: UInt32(decoded.entries.count),
                                      reserved: entry.reserved,
                                      body: decoded.entries.flatMap(\.data.rawBytes)))
            } else if entry.file.hasSuffix(".json") {
                let strings = try JSONDecoder().decode([XDDeck.TaggedString].self, from: Data(data.rawBytes))
                let texts = strings.map(\.text)
                // A trainer's stringID is its string's byte offset, and the
                // CSV can't follow a string that moves. Say which one moved
                // rather than build a deck whose trainers name the wrong tag.
                for (string, offset) in zip(strings, XDDeck.stringOffsets(texts)) where string.offset != offset {
                    throw DeckOpsError.stringMoved(text: string.text, listed: string.offset, actual: offset, .init())
                }
                sections.append(.init(tag: entry.tag, count: entry.count ?? 0, reserved: entry.reserved,
                                      body: XDDeck.encodeStrings(texts)))
            } else {
                sections.append(.init(tag: entry.tag, count: entry.count ?? 0, reserved: entry.reserved,
                                      body: data.rawBytes))
            }
        }
        return XDDeck(deckID: manifest.deckID, reserved: manifest.reserved, sections: sections).bytes
    }

    private static func prettyJSON<T: Encodable>(_ value: T) throws -> GoDData {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return GoDData(byteStream: [UInt8](try encoder.encode(value)), byteOrder: .big)
    }
}

enum DeckOpsError: Error, CustomStringConvertible {
    case missingSectionFile(File, ErrorTrace)
    case stringMoved(text: String, listed: Int, actual: Int, ErrorTrace)

    var description: String {
        switch self {
        case let .missingSectionFile(file, trace):
            return "Deck section file \(file.path) is missing\n\(trace)"
        case let .stringMoved(text, listed, actual, trace):
            return """
            Deck string '\(text)' is listed at offset \(listed) but now lands at \(actual): a string before it \
            changed length. Trainers point at strings by offset, so keep earlier strings the same length \
            (pad with spaces) or update the offsets and every stringID that uses them.
            \(trace)
            """
        }
    }
}
