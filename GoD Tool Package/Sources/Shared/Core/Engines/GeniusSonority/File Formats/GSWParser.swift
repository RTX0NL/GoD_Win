import Foundation
import GoDFoundation
import GoDEngine
import GTX

/// Static parse/serialize helpers for `GSWFile`. Pure functions — no FileSystem.
public enum GSWParser {

    // MARK: - Constants

    /// Header byte length. `Init__9FlashMenuFPvUl.s` initializes the tag-stream
    /// read position to `0x30`, fixing the header size.
    public static let headerSize = 0x30

    /// Maximum valid tag code per the dispatch table at `data5/lbl_8041A100.s`.
    public static let maxTagCode: UInt32 = 0x30

    /// Size of the GTX-style header inside an embedded texture.
    public static let embeddedTextureHeaderSize = 0x80

    /// 2-byte signature read at `markerOffset + 0x24` (matches the legacy
    /// `XGGSWTextures.swift` check). `0x0801` = BPP=8 + indexed flag.
    private static let embeddedTextureSignature: UInt16 = 0x0801

    private static func embeddedTextureMarker(id: Int) -> [UInt8] {
        [0x03, 0x00, 0x00, UInt8(id & 0xFF)]
    }

    // MARK: - Parse

    /// Parses a GSW file into structured tags and decoded textures.
    /// Returns the structured `GSWFile` plus a parallel array of `GoDImage`s,
    /// one per `file.allTextureRefs` entry (in iteration order across tags).
    ///
    /// `name` is retained for compatibility with callers that passed it
    /// (e.g. to build PNG filenames at a higher layer). No field on
    /// GSWTextureRef records it — the filename is derived at serialize
    /// time in `GSWFile+FileFormat`.
    public static func parse(data: GoDData, name: String = "") throws -> (file: GSWFile, images: [GoDImage]) {
        data.setByteOrder(.big)
        guard data.length >= headerSize else { throw FileFormatErrors.invalid(format: GSWFile.formatName) }

        let header = parseHeader(data: data)
        let raw = data.rawBytes

        // Walk the tag stream from headerSize to EOF using the asm-confirmed
        // (u32 BE code, u32 BE size, u8 payload[size]) encoding. This walk
        // lands exactly at EOF for every observed real sample.
        var tags = [GSWTag]()
        var pos = headerSize
        while pos < raw.count {
            guard pos + 8 <= raw.count else { throw FileFormatErrors.invalid(format: GSWFile.formatName) }
            let code = readU32BE(raw, at: pos)
            let size = readU32BE(raw, at: pos + 4)
            guard code <= maxTagCode else { throw FileFormatErrors.invalid(format: GSWFile.formatName) }
            let payloadStart = pos + 8
            let payloadEnd = payloadStart + Int(size)
            guard payloadEnd <= raw.count else { throw FileFormatErrors.invalid(format: GSWFile.formatName) }
            let payload = Array(raw[payloadStart..<payloadEnd])
            tags.append(GSWTag(code: code, payload: Data(payload)))
            pos = payloadEnd
        }
        guard pos == raw.count else { throw FileFormatErrors.invalid(format: GSWFile.formatName) }

        // Scan each tag's payload for embedded textures. Iterate ids
        // 1..spriteDepthCount and skip ids that don't match (real samples have
        // non-contiguous ids like [1, 3, 5]).
        let decoder = GXTextureDecoder()
        var images = [GoDImage]()
        let maxId = max(1, min(Int(header.spriteDepthCount), 0xFF))
        for id in 1...maxId {
            // Search every tag in order; the first match wins.
            for tagIndex in tags.indices {
                let payloadBytes = Array(tags[tagIndex].payload)
                guard let extracted = findEmbeddedTexture(
                    in: payloadBytes,
                    id: id,
                    decoder: decoder
                ) else { continue }
                _ = name  // retained for source compatibility; not stored
                tags[tagIndex].textures.append(GSWTextureRef(
                    id: id,
                    payloadOffset: extracted.markerOffset,
                    blockSize: extracted.blockSize,
                    format: extracted.metadata.format,
                    paletteFormat: extracted.metadata.paletteFormat,
                    width: extracted.metadata.width,
                    height: extracted.metadata.height
                ))
                images.append(extracted.image)
                break
            }
        }

        return (GSWFile(header: header, tags: tags), images)
    }

    /// Serializes a `GSWFile` back to bytes. `images` must be parallel to
    /// `file.allTextureRefs`. Re-encodes each texture and splices it into its
    /// containing tag's payload at the recorded offset.
    public static func serialize(file: GSWFile, images: [GoDImage]) throws -> GoDData {
        let allRefs = file.allTextureRefs
        guard images.count == allRefs.count else {
            throw FileFormatErrors.failedToEncode(format: GSWFile.formatName, target: "image count mismatch (got \(images.count), expected \(allRefs.count))")
        }

        let decoder = GXTextureDecoder()
        var imageCursor = 0
        var serializedTags = [(code: UInt32, payload: [UInt8])]()
        serializedTags.reserveCapacity(file.tags.count)

        for tag in file.tags {
            var payload = Array(tag.payload)
            for ref in tag.textures {
                let texMeta = GXTextureMetadata(
                    width: ref.width,
                    height: ref.height,
                    format: ref.format,
                    paletteFormat: ref.paletteFormat
                )
                guard imageCursor < images.count,
                      let encoded = decoder.encode(image: images[imageCursor], metadata: texMeta) else {
                    throw FileFormatErrors.failedToEncode(format: GSWFile.formatName, target: "texture \(ref.id)")
                }
                let encodedBytes = encoded.rawBytes
                guard encodedBytes.count == ref.blockSize else {
                    throw FileFormatErrors.failedToEncode(
                        format: GSWFile.formatName,
                        target: "texture \(ref.id) size \(encodedBytes.count) != original \(ref.blockSize)"
                    )
                }
                let textureStart = ref.payloadOffset + 0x20
                guard textureStart + ref.blockSize <= payload.count else {
                    throw FileFormatErrors.failedToEncode(format: GSWFile.formatName, target: "texture \(ref.id) splice out of bounds")
                }
                for i in 0..<encodedBytes.count {
                    payload[textureStart + i] = encodedBytes[i]
                }
                imageCursor += 1
            }
            serializedTags.append((tag.code, payload))
        }

        var totalBodySize = 0
        for entry in serializedTags { totalBodySize += 8 + entry.payload.count }

        var bytes = [UInt8]()
        bytes.reserveCapacity(headerSize + totalBodySize)
        appendHeader(file.header, to: &bytes)
        for entry in serializedTags {
            appendU32BE(entry.code, to: &bytes)
            appendU32BE(UInt32(entry.payload.count), to: &bytes)
            bytes.append(contentsOf: entry.payload)
        }
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    // MARK: - Header

    private static func parseHeader(data: GoDData) -> GSWHeader {
        data.setByteOrder(.big)
        let version: UInt32 = data.readSafely(atAddress: 0x00)
        let canvasW: UInt16 = data.readSafely(atAddress: 0x04)
        let canvasH: UInt16 = data.readSafely(atAddress: 0x06)
        let tagDataSize: UInt32 = data.readSafely(atAddress: 0x08)
        let unk0C: UInt16 = data.readSafely(atAddress: 0x0C)
        let frameRate: UInt16 = data.readSafely(atAddress: 0x0E)
        let unk10: UInt32 = data.readSafely(atAddress: 0x10)
        let unk14: UInt32 = data.readSafely(atAddress: 0x14)
        let depths: UInt16 = data.readSafely(atAddress: 0x18)
        let chars: UInt16 = data.readSafely(atAddress: 0x1A)
        let padding = Data(data.rawBytes[0x1C..<0x2C])
        let unk2C: UInt32 = data.readSafely(atAddress: 0x2C)
        return GSWHeader(
            version: version,
            canvasWidthTwips: canvasW,
            canvasHeightTwips: canvasH,
            tagDataSize: tagDataSize,
            unknown_0x0C: unk0C,
            frameRate: frameRate,
            unknown_0x10: unk10,
            unknown_0x14: unk14,
            spriteDepthCount: depths,
            characterCount: chars,
            padding_0x1C: padding,
            unknown_0x2C: unk2C
        )
    }

    private static func appendHeader(_ h: GSWHeader, to bytes: inout [UInt8]) {
        appendU32BE(h.version, to: &bytes)
        appendU16BE(h.canvasWidthTwips, to: &bytes)
        appendU16BE(h.canvasHeightTwips, to: &bytes)
        appendU32BE(h.tagDataSize, to: &bytes)
        appendU16BE(h.unknown_0x0C, to: &bytes)
        appendU16BE(h.frameRate, to: &bytes)
        appendU32BE(h.unknown_0x10, to: &bytes)
        appendU32BE(h.unknown_0x14, to: &bytes)
        appendU16BE(h.spriteDepthCount, to: &bytes)
        appendU16BE(h.characterCount, to: &bytes)
        var pad = Array(h.padding_0x1C)
        if pad.count < 0x10 { pad += [UInt8](repeating: 0, count: 0x10 - pad.count) }
        bytes.append(contentsOf: pad.prefix(0x10))
        appendU32BE(h.unknown_0x2C, to: &bytes)
    }

    // MARK: - Embedded texture extraction

    private struct ExtractedTexture {
        let markerOffset: Int
        let blockSize: Int
        let metadata: GXTextureMetadata
        let image: GoDImage
    }

    /// Searches `payload` for a `[0x03, 0x00, 0x00, id]` marker followed by a
    /// valid embedded texture. Returns the extracted block + decoded image,
    /// or nil if no match is found.
    private static func findEmbeddedTexture(
        in payload: [UInt8],
        id: Int,
        decoder: GXTextureDecoder
    ) -> ExtractedTexture? {
        let marker = embeddedTextureMarker(id: id)
        guard payload.count >= 0x20 + 0x80 else { return nil }
        var search = 0
        while search + 4 <= payload.count {
            if payload[search] == marker[0],
               payload[search + 1] == marker[1],
               payload[search + 2] == marker[2],
               payload[search + 3] == marker[3] {
                let textureStart = search + 0x20
                if textureStart + embeddedTextureHeaderSize <= payload.count {
                    let sigHi = payload[search + 0x24]
                    let sigLo = payload[search + 0x25]
                    let signature = (UInt16(sigHi) << 8) | UInt16(sigLo)
                    if signature == embeddedTextureSignature {
                        let payloadData = GoDData(byteStream: payload, byteOrder: .big)
                        if let meta = decoder.parseHeader(data: payloadData, headerOffset: textureStart),
                           let image = decoder.decode(data: payloadData, headerOffset: textureStart) {
                            let palettePtr: UInt32 = payloadData.readSafely(atAddress: textureStart + 0x48)
                            let palByteSize = meta.format.isIndexed
                                ? meta.format.paletteEntryCount * 2
                                : 0
                            let blockSize = Int(palettePtr) + palByteSize
                            if blockSize > 0, textureStart + blockSize <= payload.count {
                                return ExtractedTexture(
                                    markerOffset: search,
                                    blockSize: blockSize,
                                    metadata: meta,
                                    image: image
                                )
                            }
                        }
                    }
                }
            }
            search += 1
        }
        return nil
    }

    // MARK: - BE primitives

    private static func readU32BE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private static func appendU16BE(_ v: UInt16, to bytes: inout [UInt8]) {
        bytes.append(UInt8((v >> 8) & 0xFF))
        bytes.append(UInt8(v & 0xFF))
    }

    private static func appendU32BE(_ v: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8((v >> 24) & 0xFF))
        bytes.append(UInt8((v >> 16) & 0xFF))
        bytes.append(UInt8((v >> 8) & 0xFF))
        bytes.append(UInt8(v & 0xFF))
    }
}
