//
//  GSWFile+FileFormat.swift
//
//  Bridges GSWParser.parse / GSWParser.serialize onto the FileFormat
//  contract. Artifacts (using project-wide naming):
//    <name>.gsw.json
//    <name>_texture_001.png, <name>_texture_002.png, ...
//
//  The PNG filename for each GSWTextureRef is derived from the parent
//  GSWFile's `name` and the ref's id — not stored on the ref itself.
//

import Foundation
import GoDFoundation
import GTX

extension GSWFile {
    /// Filename for the PNG that backs a given texture ref.
    public func pngFilename(for ref: GSWTextureRef) -> File {
        File("\(name)_texture_\(String(format: "%03d", ref.id)).png")
    }

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
        var rebuilt = metadata
        rebuilt.name = stem.isEmpty ? "gsw" : stem

        var images = [GoDImage]()
        for ref in rebuilt.allTextureRefs {
            let key = rebuilt.pngFilename(for: ref)
            guard let pngData = outputs[key] else {
                throw GSWFile.missingOutputError(key: key.path)
            }
            guard let image = GoDImage.fromPNG(pngData) else {
                throw GSWFile.invalidFileError
            }
            images.append(image)
        }

        rebuilt.images = images
        self = rebuilt
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
                artifacts[pngFilename(for: ref)] = png
            }
            return artifacts
        }
    }
}
