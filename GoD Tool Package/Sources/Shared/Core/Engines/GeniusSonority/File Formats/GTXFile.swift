//
//  GTXFile.swift
//
//  FileFormat wrapper over GXTextureDecoder. The decoder itself is
//  stateless; this wrapper owns the decoded image + header metadata so the
//  registry can move GTX chunks uniformly (png + json artifacts).
//

import Foundation
import GoDFoundation
import GTX

public struct GTXFile: FileFormat {
    public static let formatName = "gtx"

    public var image: GoDImage
    public var metadata: GXTextureMetadata

    public init(image: GoDImage, metadata: GXTextureMetadata) {
        self.image = image
        self.metadata = metadata
    }

    public init(binary: GoDData) throws {
        let decoder = GXTextureDecoder()
        guard let meta = decoder.parseHeader(data: binary) else {
            throw GTXFile.invalidFileError
        }
        guard let image = decoder.decode(data: binary) else {
            throw GTXFile.invalidFileError
        }
        self.image = image
        self.metadata = meta
    }

    public var binaryData: GoDData {
        get throws {
            let decoder = GXTextureDecoder()
            guard let data = decoder.encode(image: image, metadata: metadata) else {
                throw GTXFile.failedToEncodeError(target: "gtx")
            }
            return data
        }
    }

    public init(outputs: [String: GoDData]) throws {
        guard let png = outputs["png"] else {
            throw GTXFile.missingOutputError(key: "png")
        }
        guard let metaData = outputs["json"] else {
            throw GTXFile.missingOutputError(key: "json")
        }
        guard let image = GoDImage.fromPNG(png) else {
            throw GTXFile.invalidFileError
        }
        let meta: GXTextureMetadata
        do {
            meta = try JSONDecoder().decode(GXTextureMetadata.self, from: metaData.data)
        } catch {
            throw GTXFile.invalidFileError
        }
        self.image = image
        self.metadata = meta
    }

    public var outputs: [String: GoDData] {
        get throws {
            guard let png = image.pngData() else {
                throw GTXFile.failedToEncodeError(target: "png")
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
