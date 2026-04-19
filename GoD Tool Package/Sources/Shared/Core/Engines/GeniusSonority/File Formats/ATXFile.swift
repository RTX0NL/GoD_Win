//
//  ATXFile.swift
//
//  FileFormat wrapper around GXTextureDecoder's ATX (animated texture)
//  encode/decode. The wrapper owns the decoded image plus the parsed
//  ATXMetadata (animation frames, frame-rect lookup, inner-texture metadata)
//  so the registry can route `.atx` chunks just like `.gtx`.
//
//  Artifacts:
//    animation.json  — ATX metadata (animations, frameTable, `pngPath`)
//    animation.png   — RGBA8888 decoded inner texture
//

import Foundation
import GoDFoundation
import GTX

public struct ATXFile: FileFormat {
    public static let formatName = "atx"

    public static let animationJSON = File("animation.json")
    public static let animationPNG = File("animation.png")

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

    /// ATX JSON adds a `pngPath` sibling to the raw ATXMetadata so the
    /// artifact pair is self-describing.
    public struct DTO: Codable {
        public let texture: GXTextureMetadata
        public let frameTableOffset: Int
        public let innerTextureSize: Int
        public let innerTextureOffset: Int
        public let animations: [ATXAnimation]
        public let frameTable: Data
        public let trailing: Data
        public let pngPath: String

        public init(metadata: ATXMetadata, pngPath: String) {
            self.texture = metadata.texture
            self.frameTableOffset = metadata.frameTableOffset
            self.innerTextureSize = metadata.innerTextureSize
            self.innerTextureOffset = metadata.innerTextureOffset
            self.animations = metadata.animations
            self.frameTable = metadata.frameTable
            self.trailing = metadata.trailing
            self.pngPath = pngPath
        }

        public var metadata: ATXMetadata {
            ATXMetadata(
                texture: texture,
                frameTableOffset: frameTableOffset,
                innerTextureSize: innerTextureSize,
                innerTextureOffset: innerTextureOffset,
                animations: animations,
                frameTable: frameTable,
                trailing: trailing
            )
        }
    }

    public init(outputs: [File: GoDData]) throws {
        guard let jsonData = outputs[ATXFile.animationJSON] else {
            throw ATXFile.missingOutputError(key: ATXFile.animationJSON.path)
        }
        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: jsonData.data)
        } catch {
            throw ATXFile.invalidFileError
        }
        let pngKey = File(dto.pngPath)
        guard let pngData = outputs[pngKey] else {
            throw ATXFile.missingOutputError(key: dto.pngPath)
        }
        guard let image = GoDImage.fromPNG(pngData) else {
            throw ATXFile.invalidFileError
        }
        self.image = image
        self.metadata = dto.metadata
    }

    public var outputs: [File: GoDData] {
        get throws {
            guard let png = image.pngData() else {
                throw ATXFile.failedToEncodeError(target: "png")
            }
            let dto = DTO(metadata: metadata, pngPath: ATXFile.animationPNG.path)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(dto)
            return [
                ATXFile.animationPNG: png,
                ATXFile.animationJSON: GoDData(data: jsonData, byteOrder: .big)
            ]
        }
    }
}
