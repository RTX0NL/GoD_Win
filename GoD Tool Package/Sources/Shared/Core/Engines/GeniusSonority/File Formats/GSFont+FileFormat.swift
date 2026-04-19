//
//  GSFont+FileFormat.swift
//
//  Bridges GSFont's existing binary init / atlas export+import onto the
//  FileFormat contract so the registry can route `.fnt` chunks
//  automatically.
//

import Foundation
import GoDFoundation

extension GSFont: FileFormat {
    /// Filenames under which this format emits its artifacts. The JSON's
    /// internal `atlasPath` references `atlasPGM.fileName` so the pair is
    /// self-describing.
    public static let fontJSON = File("font.json")
    public static let atlasPGM = File("atlas.pgm")

    public init(binary: GoDData) throws {
        try self.init(data: binary)
    }

    public var binaryData: GoDData {
        get throws { try data }
    }

    public init(outputs: [File: GoDData]) throws {
        guard let pgm = outputs[GSFont.atlasPGM] else {
            throw GSFont.missingOutputError(key: GSFont.atlasPGM.path)
        }
        guard let metaData = outputs[GSFont.fontJSON] else {
            throw GSFont.missingOutputError(key: GSFont.fontJSON.path)
        }
        let metadata: GSFontAtlas.Metadata
        do {
            metadata = try JSONDecoder().decode(GSFontAtlas.Metadata.self, from: metaData.data)
        } catch {
            throw GSFont.invalidFileError
        }
        self = try GSFontAtlas.importAtlas(imageData: pgm, metadata: metadata)
    }

    public var outputs: [File: GoDData] {
        get throws {
            let result = GSFontAtlas.exportAtlas(
                font: self,
                atlasPath: GSFont.atlasPGM.path
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(result.metadata)
            return [
                GSFont.atlasPGM: result.imageData,
                GSFont.fontJSON: GoDData(data: jsonData, byteOrder: .big)
            ]
        }
    }
}
