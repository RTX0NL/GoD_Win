//
//  GXTextureCMPRCorpusTests.swift
//  ColosseumTests
//
//  CMPR is DXT1, and a decoded DXT1 block cannot be *re-compressed* back into
//  itself: the endpoints survive into the decoded pixels only where some pixel
//  used index 0 or 1, and the two interpolated entries sit off the 5/6/5 grid,
//  so quantizing them loses the pair they came from. 58 % of real blocks are in
//  one of those shapes.
//
//  `GXTextureDecoder` therefore inverts a block before it compresses one —
//  solving for endpoints whose palette reproduces the sixteen pixels exactly.
//  This suite holds that to the real corpus: decode → encode → decode must be
//  pixel-identical, and the share of sub-blocks that come back byte-identical
//  must not fall. Validated on all 1,437 CMPR textures of the Colosseum, XD and
//  Battle Revolution dumps — point GODDESS_XD_FILES at each in turn.
//
//  Skips cleanly without the dump. GODDESS_XD_FILES points at the corpus,
//  GODDESS_CMPR_LIMIT raises the sample size (`all` for every texture).
//

import XCTest
import Foundation
import GoDFoundation
import GTX
import TestSupport

final class GXTextureCMPRCorpusTests: XCTestCase {

    /// Debug builds re-encode a megabyte of blocks per second or so, and the
    /// corpus holds 1,437 CMPR textures, so the default is a sample.
    private var limit: Int {
        guard let raw = ProcessInfo.processInfo.environment["GODDESS_CMPR_LIMIT"] else { return 80 }
        return raw == "all" ? Int.max : (Int(raw) ?? 80)
    }

    /// Every `.gtx` in the dump whose header says CMPR.
    private func cmprTextures(limit: Int) throws -> [(url: URL, data: GoDData, metadata: GXTextureMetadata)] {
        let root = SampleCorpus.xdGameFiles
        guard FileManager.default.fileExists(atPath: root),
              let walk = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil
              ) else {
            throw XCTSkip("CMPR corpus not available at \(root)")
        }
        let decoder = GXTextureDecoder()
        var found = [(url: URL, data: GoDData, metadata: GXTextureMetadata)]()
        var urls = [URL]()
        for case let url as URL in walk where url.pathExtension == "gtx" { urls.append(url) }
        for url in urls.sorted(by: { $0.path < $1.path }) {
            guard let raw = try? Data(contentsOf: url) else { continue }
            let data = GoDData(byteStream: [UInt8](raw), byteOrder: .big)
            guard let metadata = decoder.parseHeader(data: data), metadata.format == .CMPR else { continue }
            found.append((url, data, metadata))
            if found.count >= limit { break }
        }
        guard !found.isEmpty else { throw XCTSkip("no CMPR textures under \(root)") }
        return found
    }

    /// The pixel bytes of a texture, read back out of an encoded GTX.
    private func textureBody(_ data: GoDData, _ metadata: GXTextureMetadata) -> [UInt8] {
        let start: UInt32 = data.readSafely(atAddress: 0x28)
        let padded = { (value: Int, align: Int) in (value + align - 1) / align * align }
        let length = padded(metadata.width, 8) * padded(metadata.height, 8) / 2
        guard Int(start) + length <= data.length else { return [] }
        return Array(data.rawBytes[Int(start) ..< Int(start) + length])
    }

    /// The property that matters: a texture that came out of the game must
    /// survive decode → encode → decode without a single pixel moving. Before
    /// the encoder learned to invert a block, 40 % of blocks shifted — by up to
    /// 41 per channel where a block used neither endpoint.
    func testEveryCMPRTextureRoundTripsPixelIdentically() throws {
        let textures = try cmprTextures(limit: limit)
        let decoder = GXTextureDecoder()
        var blocks = 0, identicalBlocks = 0
        var failures = [String]()

        for texture in textures {
            guard let image = decoder.decode(data: texture.data) else {
                failures.append("\(texture.url.lastPathComponent): decode failed"); continue
            }
            guard let reEncoded = decoder.encode(image: image, metadata: texture.metadata) else {
                failures.append("\(texture.url.lastPathComponent): encode returned nil"); continue
            }
            guard let reDecoded = decoder.decode(data: reEncoded) else {
                failures.append("\(texture.url.lastPathComponent): re-decode returned nil"); continue
            }
            if reDecoded.pixels.rawBytes != image.pixels.rawBytes {
                let changed = zip(reDecoded.pixels.rawBytes, image.pixels.rawBytes).filter { $0 != $1 }.count
                failures.append("\(texture.url.lastPathComponent): \(changed) of "
                                + "\(image.pixels.rawBytes.count) channel bytes moved")
            }
            let before = textureBody(texture.data, texture.metadata)
            let after = textureBody(reEncoded, texture.metadata)
            guard before.count == after.count, !before.isEmpty else { continue }
            for start in stride(from: 0, to: before.count - 7, by: 8) {
                blocks += 1
                if before[start ..< start + 8] == after[start ..< start + 8] { identicalBlocks += 1 }
            }
        }

        XCTAssertTrue(failures.isEmpty,
                      "\(failures.count) of \(textures.count) CMPR textures did not round-trip: "
                      + failures.prefix(8).joined(separator: "; "))

        // Byte-identity is a bonus, not the contract. A block whose decoded
        // pixels use a single palette index does not determine its endpoints —
        // those described the *original uncompressed* spread — and how many
        // blocks are that shape is a property of the game's compressor, not of
        // this encoder: 26 % on Colosseum and XD, 43 % on Battle Revolution.
        // Measured over all 3,354,460 real sub-blocks, 72 % come back
        // byte-identical (XD 78 %, Colosseum 76 %, PBR 56 %) against 46 % for
        // re-compression, and each of those is within a point of the ceiling
        // its flat-block share allows. The floor catches a regression in the
        // conventions without pinning the figure. (Whole textures are a much
        // harsher measure — one flat block changes a file — so only ~23 % of
        // texture bodies match end to end.)
        guard blocks > 0 else { throw XCTSkip("no comparable texture bodies") }
        let share = Double(identicalBlocks) / Double(blocks)
        XCTAssertGreaterThan(share, 0.50,
                             "only \(identicalBlocks)/\(blocks) sub-blocks repacked byte-identically, "
                             + "below what the measured conventions explain")
        print("CMPR corpus: \(textures.count) textures, \(blocks) sub-blocks, "
              + "\(identicalBlocks) byte-identical (\(Int(share * 100)) %)")
    }

    /// The inversion must not reach for a block it cannot reproduce: an edited
    /// image falls through to compression, and compression must still produce a
    /// decodable block of the right size rather than throwing the pixels away.
    func testAnEditedImageStillEncodes() throws {
        let decoder = GXTextureDecoder()
        // A gradient no DXT1 palette can hold exactly in 4x4 tiles.
        var pixels = [UInt8]()
        for y in 0..<16 {
            for x in 0..<16 {
                pixels.append(contentsOf: [UInt8(x * 16), UInt8(y * 16), UInt8((x + y) * 8), 255])
            }
        }
        let image = GoDImage(width: 16, height: 16,
                             pixels: GoDData(byteStream: pixels, byteOrder: .big))
        let metadata = GXTextureMetadata(width: 16, height: 16, format: .CMPR, paletteFormat: nil)
        guard let encoded = decoder.encode(image: image, metadata: metadata),
              let reDecoded = decoder.decode(data: encoded) else {
            XCTFail("encode/decode of an edited CMPR image failed"); return
        }
        XCTAssertEqual(reDecoded.width, 16)
        XCTAssertEqual(reDecoded.height, 16)
        // Lossy, but the gradient must still be recognizably there.
        let original = image.pixels.rawBytes, result = reDecoded.pixels.rawBytes
        let worst = zip(original, result).map { abs(Int($0) - Int($1)) }.max() ?? 0
        XCTAssertLessThan(worst, 48, "compression fallback distorted the image badly")
    }

    /// An opaque black pixel in a block that also carries transparency must stay
    /// opaque. In three-color mode index 3 *is* the transparent entry, and the
    /// fallback used to pick it for any pixel nearest to black, which turned
    /// black pixels invisible.
    func testOpaqueBlackSurvivesABlockWithTransparency() throws {
        let decoder = GXTextureDecoder()
        var pixels = [UInt8]()
        for y in 0..<8 {
            for x in 0..<8 {
                // Half the block transparent, the rest opaque black and white.
                if x < 4 { pixels.append(contentsOf: [0, 0, 0, 0]) }
                else if y < 4 { pixels.append(contentsOf: [0, 0, 0, 255]) }
                else { pixels.append(contentsOf: [255, 255, 255, 255]) }
            }
        }
        let image = GoDImage(width: 8, height: 8,
                             pixels: GoDData(byteStream: pixels, byteOrder: .big))
        let metadata = GXTextureMetadata(width: 8, height: 8, format: .CMPR, paletteFormat: nil)
        guard let encoded = decoder.encode(image: image, metadata: metadata),
              let reDecoded = decoder.decode(data: encoded) else {
            XCTFail("encode/decode failed"); return
        }
        let result = reDecoded.pixels.rawBytes
        for y in 0..<8 {
            for x in 4..<8 {
                let offset = (y * 8 + x) * 4
                XCTAssertEqual(result[offset + 3], 255,
                               "opaque pixel at (\(x), \(y)) was written as transparent")
            }
        }
    }
}
