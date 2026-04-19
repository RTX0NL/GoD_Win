//
//  ATXFile.swift
//
//  FileFormat wrapper around GXTextureDecoder's ATX (animated texture)
//  encode/decode. The wrapper owns the decoded image plus the parsed
//  ATXMetadata (animation frames, frame-rect lookup, inner-texture metadata)
//  so the registry can route `.atx` chunks just like `.gtx`.
//

import Foundation
import GoDFoundation
import GTX

public struct ATXFile: FileFormat {
    public static let formatName = "atx"

    public var image: GoDImage
    public var metadata: ATXMetadata

    public init(image: GoDImage, metadata: ATXMetadata) {
        self.image = image
        self.metadata = metadata
    }

    public init(binary: GoDData) throws {
        let decoder = GXTextureDecoder()
        guard let result = decoder.decodeATX(data: binary) else {
            throw ATXFile.invalidFileError
        }
        self.image = result.image
        self.metadata = result.metadata
    }

    public var binaryData: GoDData {
        get throws {
            let decoder = GXTextureDecoder()
            guard let data = decoder.encodeATX(image: image, metadata: metadata) else {
                throw ATXFile.failedToEncodeError(target: "atx")
            }
            return data
        }
    }

    public init(outputs: [String: GoDData]) throws {
        guard let png = outputs["png"] else {
            throw ATXFile.missingOutputError(key: "png")
        }
        guard let metaData = outputs["json"] else {
            throw ATXFile.missingOutputError(key: "json")
        }
        guard let image = GoDImage.fromPNG(png) else {
            throw ATXFile.invalidFileError
        }
        let meta: ATXMetadata
        do {
            meta = try JSONDecoder().decode(ATXMetadata.self, from: metaData.data)
        } catch {
            throw ATXFile.invalidFileError
        }
        self.image = image
        self.metadata = meta
    }

    public var outputs: [String: GoDData] {
        get throws {
            guard let png = image.pngData() else {
                throw ATXFile.failedToEncodeError(target: "png")
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(metadata)
            return [
                "png": png,
                "json": GoDData(data: jsonData, byteOrder: .big)
            ]
        }
    }
}
