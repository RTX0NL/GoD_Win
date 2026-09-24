//
//  GCIOperationTests.swift
//  GODOpsTests
//
//  Runs the real GCI dump/build operations against an InMemoryFST with
//  synthetic .gci files.
//
//  Two properties matter and are asserted throughout. A save splits on
//  the region list its engine declares, or on one derived from its own
//  directory entry when no engine claims it — and an unedited save
//  rebuilds byte-identically either way, images and comments included.
//

import XCTest
import Foundation
import GoDFoundation
import GameCube
import GeniusSonority
import Colosseum
@testable import GODOps

final class GCIOperationTests: XCTestCase {

    /// A synthetic save with a hand-laid directory entry and a
    /// deterministic body, parametrised on everything the tests vary.
    ///
    /// Defaults describe the Genius Sonority shape: an RGB5A3 banner at
    /// 0x40, eight shared-palette icon frames, comments at 0.
    private func makeGCIBytes(
        gamecode: String,
        blockCount: Int,
        flags: UInt8 = 0x02,
        imageOffset: UInt32 = 0x40,
        iconFormat: UInt16 = 0x5555,
        animationSpeed: UInt16 = 0x5555,
        commentsAddress: UInt32 = 0
    ) -> GoDData {
        let bodyLength = blockCount * GCIFile.blockSize
        var bytes = [UInt8](repeating: 0, count: GCIFile.headerSize + bodyLength)

        let code = Array(gamecode.utf8)
        for i in 0..<min(4, code.count) { bytes[i] = code[i] }
        bytes[0x04] = 0x30; bytes[0x05] = 0x31      // makercode "01"
        bytes[0x06] = 0xFF                          // unused1
        bytes[0x07] = flags
        let filename: [UInt8] = Array("pokemon_storys".utf8)
        for i in 0..<filename.count { bytes[0x08 + i] = filename[i] }
        bytes[0x28] = 0x12; bytes[0x29] = 0x34      // modtime = 0x12345678
        bytes[0x2A] = 0x56; bytes[0x2B] = 0x78
        bytes[0x2C] = UInt8(truncatingIfNeeded: imageOffset >> 24)
        bytes[0x2D] = UInt8(truncatingIfNeeded: imageOffset >> 16)
        bytes[0x2E] = UInt8(truncatingIfNeeded: imageOffset >> 8)
        bytes[0x2F] = UInt8(truncatingIfNeeded: imageOffset)
        bytes[0x30] = UInt8(truncatingIfNeeded: iconFormat >> 8)
        bytes[0x31] = UInt8(truncatingIfNeeded: iconFormat)
        bytes[0x32] = UInt8(truncatingIfNeeded: animationSpeed >> 8)
        bytes[0x33] = UInt8(truncatingIfNeeded: animationSpeed)
        bytes[0x34] = 0x04                          // permissions
        bytes[0x37] = 0x05                          // firstBlock
        bytes[0x38] = UInt8((blockCount >> 8) & 0xFF)
        bytes[0x39] = UInt8(blockCount & 0xFF)
        bytes[0x3A] = 0xFF; bytes[0x3B] = 0xFF      // unused2
        bytes[0x3C] = UInt8(truncatingIfNeeded: commentsAddress >> 24)
        bytes[0x3D] = UInt8(truncatingIfNeeded: commentsAddress >> 16)
        bytes[0x3E] = UInt8(truncatingIfNeeded: commentsAddress >> 8)
        bytes[0x3F] = UInt8(truncatingIfNeeded: commentsAddress)

        var rng: UInt32 = 0xDEADBEEF
        for i in 0..<bodyLength {
            rng = rng &* 1664525 &+ 1013904223
            bytes[GCIFile.headerSize + i] = UInt8(truncatingIfNeeded: rng >> 24)
        }

        // Comment fields have to be decodable text for the dump to treat
        // them as editable; random bytes would demote them to raw, which
        // is a different path and has its own test.
        let title = Array("POKEMON XD".utf8)
        let subtitle = Array("SAVE FILE".utf8)
        let commentStart = GCIFile.headerSize + Int(commentsAddress)
        if commentStart + CardComments.byteCount <= bytes.count {
            for i in 0..<CardComments.byteCount { bytes[commentStart + i] = 0 }
            for (i, byte) in title.enumerated() { bytes[commentStart + i] = byte }
            for (i, byte) in subtitle.enumerated() {
                bytes[commentStart + CardComments.fieldLength + i] = byte
            }
        }
        if ["GXX", "GC6"].contains(String(gamecode.prefix(3))) {
            let rule = GeniusSonorityEngine.Data.geniusSonorityMetadataChecksum

            // Everything from just past the checksum to the first save
            // slot is zero on every one of the 61 real saves measured.
            // The fixture has to match: those bytes belong to no
            // artifact, so the rebuild fills them, and random bytes here
            // would be a save the tool correctly refuses.
            let fillFrom = GCIFile.headerSize + rule.storeAt + 4
            let fillTo = GCIFile.headerSize
                + GeniusSonorityEngine.Data.geniusSonorityMetadataLength
            for i in fillFrom..<min(fillTo, bytes.count) { bytes[i] = 0 }

            // Genius Sonority saves keep a word sum of their metadata
            // region and the game checks it, so a realistic fixture has
            // to carry a valid one. Without this the rebuild's
            // recomputed checksum would differ from the fixture's random
            // bytes and every round-trip assertion would fail for the
            // wrong reason.
            var sum: UInt32 = 0
            for offset in stride(from: rule.offset, to: rule.offset + rule.length, by: 4) {
                let at = GCIFile.headerSize + offset
                let word = UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16
                    | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
                sum = sum &+ word
            }
            let at = GCIFile.headerSize + rule.storeAt
            bytes[at] = UInt8(truncatingIfNeeded: sum >> 24)
            bytes[at + 1] = UInt8(truncatingIfNeeded: sum >> 16)
            bytes[at + 2] = UInt8(truncatingIfNeeded: sum >> 8)
            bytes[at + 3] = UInt8(truncatingIfNeeded: sum)
        }

        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    /// Compare two byte runs, reporting the first difference rather than
    /// letting XCTest print two whole save files.
    private func assertBytesEqual(
        _ actual: [UInt8], _ expected: [UInt8], _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard actual.count == expected.count else {
            return XCTFail(
                "\(label): length \(actual.count), expected \(expected.count)",
                file: file, line: line
            )
        }
        if let index = (0..<actual.count).first(where: { actual[$0] != expected[$0] }) {
            XCTFail(
                "\(label): first difference at \(String(format: "%#x", index)) — "
                + "\(String(format: "%02X", actual[index])) vs "
                + "\(String(format: "%02X", expected[index]))",
                file: file, line: line
            )
        }
    }

    private func bodySlice(of gci: GoDData, _ range: Range<Int>) -> [UInt8] {
        let raw = gci.rawBytes
        return Array(
            raw[(GCIFile.headerSize + range.lowerBound)..<(GCIFile.headerSize + range.upperBound)]
        )
    }

    private func dump(
        _ gci: GoDData,
        to outputFolder: Folder,
        in fst: InMemoryFST
    ) throws {
        try fst.writeFile(gci, at: File("/project/save.gci"), overwrite: true)
        let config = GCIOps.DumpConfig(operations: [
            OperationConfig(
                operation: .dumpGCI(
                    gciFile: File("/project/save.gci"),
                    outputFolder: outputFolder,
                    overwrite: true,
                    saveEngine: nil
                ),
                enabled: .yes
            )
        ])
        try GCIOps.dump(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
    }

    private func build(from inputFolder: Folder, to gciFile: File, in fst: InMemoryFST) throws {
        let config = GCIOps.BuildConfig(operations: [
            OperationConfig(
                operation: .buildGCI(
                    inputFolder: inputFolder,
                    gciFile: gciFile,
                    overwrite: true
                ),
                enabled: .yes
            )
        ])
        try GCIOps.build(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
    }

    private func manifest(
        in folder: Folder, _ fst: InMemoryFST
    ) throws -> GCIOps.SaveManifest {
        try fst.decodeJSON(from: folder.file("gci-manifest.json"))
    }

    // MARK: - Declared layouts

    func testDumpXDGCISplitsOnTheDeclaredRegions() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(gamecode: "GXXE", blockCount: 0x2B)  // 0x56000 body
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        let manifest = try manifest(in: out, fst)
        XCTAssertEqual(manifest.header.gamecode, "GXXE")
        XCTAssertEqual(manifest.header.filename, "pokemon_storys")
        XCTAssertEqual(manifest.header.blockCount, 0x2B)
        XCTAssertEqual(manifest.layoutSource, .declared)
        XCTAssertEqual(manifest.regions.map(\.name), ["metadata", "slot-a", "slot-b"])

        // Game-data regions are written whole.
        let regions: [(name: String, range: Range<Int>)] = [
            ("slot-a.bin", 0x06000..<0x2E000),
            ("slot-b.bin", 0x2E000..<0x56000),
        ]
        for region in regions {
            let data = try XCTUnwrap(
                fst.readFile(at: out.file(region.name))?.allData, "Missing \(region.name)"
            )
            assertBytesEqual(
                data.rawBytes, bodySlice(of: gci, region.range), region.name
            )
        }

        // The metadata region gets no file at all. Its comments, images
        // and checksum are all derivable, and the rest is fill, so the
        // rebuild recreates it rather than copying it forward.
        XCTAssertNil(
            fst.readFile(at: out.file("metadata.bin"))?.allData,
            "the metadata region should not be written out"
        )
        XCTAssertNil(fst.readFile(at: out.file("metadata-residue.bin"))?.allData)

        // And none of the old, wrong region files.
        XCTAssertNil(fst.readFile(at: out.file("banner.bin"))?.allData)
        XCTAssertNil(fst.readFile(at: out.file("header0.bin"))?.allData)
    }

    /// Nothing of the dumped save is carried into the rebuild. Deleting
    /// the input before building proves it: the artifacts and the
    /// manifest are the whole source.
    func testRebuildNeedsNothingFromTheOriginalSave() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(gamecode: "GXXE", blockCount: 0x2B)
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        try fst.deleteFile(at: File("/project/save.gci"))

        try build(from: out, to: File("/project/rebuilt.gci"), in: fst)
        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.gci"))?.allData)
        assertBytesEqual(rebuilt.rawBytes, gci.rawBytes, "rebuilt save")
    }

    /// The banner and every live icon frame come out as their own PNG,
    /// which is what makes them editable at all.
    func testDumpWritesBannerAndIconPNGs() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(gamecode: "GXXE", blockCount: 0x2B)
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        let images = try XCTUnwrap(manifest(in: out, fst).card?.images)
        XCTAssertEqual(images.bannerFormat, .rgb5a3)
        XCTAssertEqual(images.animationOrder, .loop)
        XCTAssertEqual(images.frames.count, 8)
        XCTAssertEqual(images.frames.map(\.slot), Array(0..<8))
        XCTAssertEqual(images.frames.first?.videoFrames, 4)

        XCTAssertNotNil(fst.readFile(at: out.file("Card/banner.png"))?.allData)
        for slot in 0..<8 {
            XCTAssertNotNil(
                fst.readFile(at: out.file("Card/icon-\(slot).png"))?.allData,
                "Missing icon-\(slot).png"
            )
        }
    }

    func testDumpDecodesComments() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(gamecode: "GXXE", blockCount: 0x2B)
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        let comments = try XCTUnwrap(manifest(in: out, fst).card?.comments)
        XCTAssertEqual(comments.encoding, .ansi)
        XCTAssertEqual(comments.title, "POKEMON XD")
        XCTAssertEqual(comments.subtitle, "SAVE FILE")
    }

    /// A Japanese gamecode means the comments are Shift-JIS, since a
    /// standalone save has no card header to say so.
    func testJapaneseSaveUsesShiftJISComments() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(gamecode: "GXXJ", blockCount: 0x2B)
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        let comments = try XCTUnwrap(manifest(in: out, fst).card?.comments)
        XCTAssertEqual(comments.encoding, .shiftJIS)
    }

    func testBuildXDGCIRoundTripsBytes() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(gamecode: "GXXE", blockCount: 0x2B)
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)
        try build(from: out, to: File("/project/rebuilt.gci"), in: fst)

        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.gci"))?.allData)
        assertBytesEqual(rebuilt.rawBytes, gci.rawBytes, "rebuilt save")
    }

    func testDumpColoGCISplitsOnItsThreeSlots() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(gamecode: "GC6E", blockCount: 0x30)  // 0x60000 body
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        let manifest = try manifest(in: out, fst)
        XCTAssertEqual(manifest.layoutSource, .declared)
        XCTAssertEqual(
            manifest.regions.map(\.name), ["metadata", "slot-1", "slot-2", "slot-3"]
        )

        XCTAssertNil(fst.readFile(at: out.file("metadata.bin"))?.allData)
        for i in 0..<ColoSaveCardFile.slotCount {
            let start = ColoSaveCardFile.preambleSize + i * ColoSaveCardFile.slotSize
            let slot = try XCTUnwrap(
                fst.readFile(at: out.file("slot-\(i + 1).bin"))?.allData,
                "Missing slot-\(i + 1).bin"
            )
            assertBytesEqual(
                slot.rawBytes, bodySlice(of: gci, start..<(start + ColoSaveCardFile.slotSize)),
                "slot-\(i + 1).bin"
            )
        }

        try build(from: out, to: File("/project/rebuilt.gci"), in: fst)
        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.gci"))?.allData)
        assertBytesEqual(rebuilt.rawBytes, gci.rawBytes, "rebuilt save")
    }

    // MARK: - Derived layouts

    /// A save from a game with no declared shape still gets its banner,
    /// icon and comments — that is the whole point of deriving the card
    /// metadata from the directory entry. Only the game's own data stays
    /// in one undivided region.
    func testUnknownGameStillGetsEditableCardMetadata() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(gamecode: "GALE", blockCount: 4)
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        let manifest = try manifest(in: out, fst)
        XCTAssertEqual(manifest.layoutSource, .derived)
        XCTAssertEqual(manifest.regions.map(\.name), ["metadata", "data"])
        XCTAssertTrue(manifest.integrity.isEmpty)

        let images = try XCTUnwrap(manifest.card?.images)
        XCTAssertNotNil(fst.readFile(at: out.file("Card/banner.png"))?.allData)
        XCTAssertNotNil(fst.readFile(at: out.file("data.bin"))?.allData)
        XCTAssertNil(fst.readFile(at: out.file("slot-a.bin"))?.allData)

        try build(from: out, to: File("/project/rebuilt.gci"), in: fst)
        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.gci"))?.allData)
        assertBytesEqual(rebuilt.rawBytes, gci.rawBytes, "rebuilt save")
    }

    /// Luigi's Mansion's shape: a CI8 banner, icon frames in slots 0, 3
    /// and 7 with empty slots between, and comments *after* the images
    /// rather than before them. Nothing here resembles the Pokémon
    /// layout, which is why it is worth a test of its own.
    func testSparseFramesAndTrailingCommentsRoundTrip() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(
            gamecode: "GLME", blockCount: 3,
            flags: 0x05, imageOffset: 0,
            iconFormat: 0x4041, animationSpeed: 0xFFFF,
            commentsAddress: 0x1C00
        )
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        let manifest = try manifest(in: out, fst)
        let images = try XCTUnwrap(manifest.card?.images)
        XCTAssertEqual(images.bannerFormat, .ci8)
        XCTAssertEqual(images.animationOrder, .pingPong)
        XCTAssertEqual(images.frames.map(\.slot), [0, 3, 7])
        XCTAssertEqual(images.frames.first?.videoFrames, 12)
        XCTAssertEqual(manifest.regions.first?.length, 0x1C40)

        for slot in [0, 3, 7] {
            XCTAssertNotNil(fst.readFile(at: out.file("Card/icon-\(slot).png"))?.allData)
        }
        XCTAssertNil(fst.readFile(at: out.file("Card/icon-1.png"))?.allData)

        try build(from: out, to: File("/project/rebuilt.gci"), in: fst)
        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.gci"))?.allData)
        assertBytesEqual(rebuilt.rawBytes, gci.rawBytes, "rebuilt save")
    }

    func testSaveWithNoImagesRoundTrips() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(
            gamecode: "GALE", blockCount: 2,
            flags: 0x00, imageOffset: CardImageBlock.noImageOffset,
            iconFormat: 0, animationSpeed: 0, commentsAddress: 0
        )
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        let manifest = try manifest(in: out, fst)
        XCTAssertNil(manifest.card?.images)
        XCTAssertNotNil(manifest.card?.comments)

        try build(from: out, to: File("/project/rebuilt.gci"), in: fst)
        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.gci"))?.allData)
        assertBytesEqual(rebuilt.rawBytes, gci.rawBytes, "rebuilt save")
    }

    // MARK: - Editing

    /// Editing a banner has to reach the rebuilt save, and the Genius
    /// Sonority metadata checksum has to be recomputed over the new
    /// bytes. Replaying the dumped checksum would hand the game a save
    /// it rejects.
    func testEditingTheBannerUpdatesTheSaveAndItsChecksum() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(gamecode: "GXXE", blockCount: 0x2B)
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        let rule = GeniusSonorityEngine.Data.geniusSonorityMetadataChecksum
        let manifest = try manifest(in: out, fst)
        XCTAssertEqual(manifest.integrity, [rule])

        // Repaint the banner and write it back over its artifact.
        let bannerPath = out.file("Card/banner.png")
        let original = try XCTUnwrap(fst.readFile(at: bannerPath)?.allData)
        let decoded = try XCTUnwrap(GoDImage.fromPNG(original))
        var pixels = decoded.pixels.rawBytes
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 0xF8      // red, exactly representable in RGB5A3
            pixels[i + 1] = 0x00
            pixels[i + 2] = 0x00
            pixels[i + 3] = 0xFF
        }
        let repainted = GoDImage(
            width: decoded.width, height: decoded.height,
            pixels: GoDData(byteStream: pixels, byteOrder: .big)
        )
        try fst.writeFile(
            try XCTUnwrap(repainted.pngData()), at: bannerPath, overwrite: true
        )

        try build(from: out, to: File("/project/rebuilt.gci"), in: fst)
        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.gci"))?.allData)
        XCTAssertNotEqual(rebuilt.rawBytes, gci.rawBytes, "the edit should have landed")

        let body = try XCTUnwrap(
            rebuilt.read(
                atAddress: UInt(GCIFile.headerSize),
                length: UInt(rebuilt.length - GCIFile.headerSize)
            )
        )
        XCTAssertTrue(rule.holds(in: body), "the metadata checksum was not recomputed")

        // The banner really is red now, and nothing else moved.
        let redecoded = try XCTUnwrap(
            CardImageBlock.decode(body: body, header: manifest.header)
        )
        guard case let .direct(banner)? = redecoded.banner else {
            return XCTFail("expected a direct-color banner")
        }
        XCTAssertEqual(Array(banner.pixels.rawBytes.prefix(4)), [0xF8, 0x00, 0x00, 0xFF])
    }

    func testEditingCommentsReachesTheRebuiltSave() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(gamecode: "GXXE", blockCount: 0x2B)
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        var manifest = try manifest(in: out, fst)
        manifest.card?.comments?.title = "EDITED TITLE"
        try fst.encodeJSON(
            manifest, to: out.file("gci-manifest.json"), overwrite: true
        )

        try build(from: out, to: File("/project/rebuilt.gci"), in: fst)
        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.gci"))?.allData)
        let body = try XCTUnwrap(
            rebuilt.read(
                atAddress: UInt(GCIFile.headerSize),
                length: UInt(rebuilt.length - GCIFile.headerSize)
            )
        )
        let comments = try XCTUnwrap(
            CardComments.decode(body: body, header: manifest.header)
        )
        XCTAssertEqual(comments.title, "EDITED TITLE")
        XCTAssertEqual(comments.subtitle, "SAVE FILE")
    }

    // MARK: - Errors

    func testDumpMissingInputThrows() throws {
        let fst = InMemoryFST()
        let config = GCIOps.DumpConfig(operations: [
            OperationConfig(
                operation: .dumpGCI(
                    gciFile: File("/project/missing.gci"),
                    outputFolder: Folder("/project/Dump"),
                    overwrite: true,
                    saveEngine: nil
                ),
                enabled: .yes
            )
        ])
        XCTAssertThrowsError(
            try GCIOps.dump(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
        ) { error in
            guard case GCIOpsErrors.inputNotFound = error else {
                return XCTFail("Expected GCIOpsErrors.inputNotFound, got \(error)")
            }
        }
    }

    /// A byte in the metadata region that no artifact explains and that
    /// isn't the region's fill means this save cannot be rebuilt from
    /// scratch. The dump refuses rather than quietly keeping a copy,
    /// because a stored copy would make the rebuild a patch.
    func testUnreproducibleMetadataByteIsRefused() throws {
        let fst = InMemoryFST()
        var bytes = makeGCIBytes(gamecode: "GXXE", blockCount: 0x2B).rawBytes
        // 0x3A44 is past the images, the comments and the checksum word,
        // in the run every real save leaves zero.
        bytes[GCIFile.headerSize + 0x3A44] = 0x5A
        let gci = GoDData(byteStream: bytes, byteOrder: .big)

        XCTAssertThrowsError(try dump(gci, to: Folder("/project/Dump"), in: fst)) { error in
            guard case let GCIOpsErrors.metadataNotReproducible(_, _, _, count, samples, _) = error
            else {
                return XCTFail("Expected metadataNotReproducible, got \(error)")
            }
            XCTAssertEqual(count, 1)
            XCTAssertEqual(samples.first?.offset, 0x3A44)
            XCTAssertEqual(samples.first?.value, 0x5A)
        }
    }
}
