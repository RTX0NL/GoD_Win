//
//  GSWFile+FileFormat.swift
//
//  Bridges GSWParser.parse / GSWParser.serialize onto the FileFormat
//  contract. Artifacts (using project-wide naming):
//    <name>.gsw.json
//    <name>_texture_001.png, <name>_texture_002.png, ...
//

import Foundation
import GoDFoundation
import GTX

extension GSWFile {
    public init(binary: GoDData) throws {
        try self.init(binary: binary, name: "gsw")
    }

    public init(binary: GoDData, name: String) throws {
        let parsed = try GSWParser.parse(data: binary, name: name)
        self.init(header: parsed.file.header, tags: parsed.file.tags, images: parsed.images)
        self.name = name
    }

    public var binaryData: GoDData {
        get throws {
            try GSWParser.serialize(file: self, images: images)
        }
    }

    public init(outputs: [File: GoDData]) throws {
        let suffix = ".\(GSWFile.formatName).json"
        guard let jsonKey = outputs.keys.first(where: { $0.path.hasSuffix(suffix) }) else {
            throw GSWFile.missingOutputError(key: "*\(suffix)")
        }
        let stem = String(jsonKey.path.dropLast(suffix.count))
        guard let jsonData = outputs[jsonKey] else {
            throw GSWFile.missingOutputError(key: jsonKey.path)
        }
        let metadata: GSWFile
        do {
            metadata = try JSONDecoder().decode(GSWFile.self, from: jsonData.data)
        } catch {
            throw GSWFile.invalidFileError
        }

        var images = [GoDImage]()
        for ref in metadata.allTextureRefs {
            let key = File(GSWFile.normalizePNGPath(ref.pngPath))
            guard let pngData = outputs[key] else {
                throw GSWFile.missingOutputError(key: key.path)
            }
            guard let image = GoDImage.fromPNG(pngData) else {
                throw GSWFile.invalidFileError
            }
            images.append(image)
        }

        self.init(header: metadata.header, tags: metadata.tags, images: images)
        self.name = stem.isEmpty ? "gsw" : stem
    }

    public var outputs: [File: GoDData] {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(self)

            var artifacts: [File: GoDData] = [
                jsonFilename: GoDData(data: jsonData, byteOrder: .big)
            ]

            let refs = allTextureRefs
            guard refs.count == images.count else {
                throw FileFormatErrors.failedToEncode(
                    format: GSWFile.formatName,
                    target: "image count mismatch (got \(images.count), expected \(refs.count))"
                )
            }
            for (ref, image) in zip(refs, images) {
                guard let png = image.pngData() else {
                    throw GSWFile.failedToEncodeError(target: "PNG for texture \(ref.id)")
                }
                artifacts[File(GSWFile.normalizePNGPath(ref.pngPath))] = png
            }
            return artifacts
        }
    }

    /// Drops a leading `./` from a `GSWTextureRef.pngPath` so keys stay
    /// cleanly relative when placed into the outputs dict.
    private static func normalizePNGPath(_ path: String) -> String {
        var p = path
        if p.hasPrefix("./") { p.removeFirst(2) }
        return p
    }
}
