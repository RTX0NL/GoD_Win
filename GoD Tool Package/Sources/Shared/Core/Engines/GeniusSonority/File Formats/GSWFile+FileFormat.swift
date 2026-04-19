//
//  GSWFile+FileFormat.swift
//
//  Bridges GSWParser.parse / GSWParser.serialize onto the FileFormat
//  contract. Outputs are one JSON metadata file plus per-texture PNGs
//  nested under `textures/` — each GSWTextureRef's `pngPath` points at
//  its sidecar, so the JSON is self-describing.
//

import Foundation
import GoDFoundation
import GTX

extension GSWFile {
    public static let flashMenuJSON = File("flashmenu.json")

    public init(binary: GoDData) throws {
        let parsed = try GSWParser.parse(data: binary)
        self.init(header: parsed.file.header, tags: parsed.file.tags, images: parsed.images)
    }

    public var binaryData: GoDData {
        get throws {
            try GSWParser.serialize(file: self, images: images)
        }
    }

    public init(outputs: [File: GoDData]) throws {
        guard let jsonData = outputs[GSWFile.flashMenuJSON] else {
            throw GSWFile.missingOutputError(key: GSWFile.flashMenuJSON.path)
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
    }

    public var outputs: [File: GoDData] {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(self)

            var artifacts: [File: GoDData] = [
                GSWFile.flashMenuJSON: GoDData(data: jsonData, byteOrder: .big)
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
