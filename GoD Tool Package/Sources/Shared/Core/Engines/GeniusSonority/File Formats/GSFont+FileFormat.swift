//
//  GSFont+FileFormat.swift
//
//  Bridges GSFont's existing binary init / atlas export+import onto the
//  FileFormat contract. Artifact filenames follow the project-wide
//  pattern: `<name>.fnt.json` + `<name>.fnt.pgm` (default `name = "fnt"`).
//

import Foundation
import GoDFoundation

extension GSFont: FileFormat {
    public func atlasPGMFilename() -> File { File("\(name).\(GSFont.formatName).pgm") }

    public init(binary: GoDData) throws {
        try self.init(data: binary)
    }

    public var binaryData: GoDData {
        get throws { try data }
    }

    public init(outputs: [File: GoDData]) throws {
        let jsonSuffix = ".\(GSFont.formatName).json"
        let pgmSuffix = ".\(GSFont.formatName).pgm"
        guard let jsonKey = outputs.keys.first(where: { $0.path.hasSuffix(jsonSuffix) }) else {
            throw GSFont.missingOutputError(key: "*\(jsonSuffix)")
        }
        let stem = String(jsonKey.path.dropLast(jsonSuffix.count))
        let pgmKey = File("\(stem)\(pgmSuffix)")
        guard let metaData = outputs[jsonKey] else {
            throw GSFont.missingOutputError(key: jsonKey.path)
        }
        guard let pgm = outputs[pgmKey] else {
            throw GSFont.missingOutputError(key: pgmKey.path)
        }
        let metadata: GSFontAtlas.Metadata
        do {
            metadata = try JSONDecoder().decode(GSFontAtlas.Metadata.self, from: metaData.data)
        } catch {
            throw GSFont.invalidFileError
        }
        self = try GSFontAtlas.importAtlas(imageData: pgm, metadata: metadata)
        self.name = stem.isEmpty ? "fnt" : stem
    }

    public var outputs: [File: GoDData] {
        get throws {
            let pgm = atlasPGMFilename()
            let result = GSFontAtlas.exportAtlas(font: self, atlasPath: pgm.path)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(result.metadata)
            return [
                pgm: result.imageData,
                jsonFilename: GoDData(data: jsonData, byteOrder: .big)
            ]
        }
    }
}
