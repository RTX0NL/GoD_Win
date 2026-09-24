//
//  CardImageBlockTests.swift
//
//  Layout derivation and the encode/decode split for a GameCube save's
//  banner and animated icon.
//
//  The shapes worth covering are the ones real saves actually differ
//  over: which banner format, how many icon frames and in which slots,
//  whether the palette is shared or per-frame, and where the comments
//  sit relative to the images. Pokémon XD and Luigi's Mansion disagree
//  on nearly all of it, so both are modelled here.
//

import XCTest
@testable import GameCube
@testable import GoDFoundation
@testable import GTX

final class CardImageBlockTests: XCTestCase {

    // MARK: - Fixtures

    /// A directory entry with the image-related fields set and
    /// everything else left at plausible defaults.
    private func makeHeader(
        gamecode: String = "TEST",
        flags: UInt8,
        imageOffset: UInt32,
        iconFormat: UInt16,
        animationSpeed: UInt16,
        commentsAddress: UInt32 = 0,
        blockCount: UInt16 = 3
    ) -> GCIFile.Header {
        GCIFile.Header(
            gamecode: gamecode,
            makercode: "01",
            bannerAndIconFlags: flags,
            filename: "fixture",
            modtime: 0,
            imageOffset: imageOffset,
            iconFmt: iconFormat,
            animSpeed: animationSpeed,
            permissions: 4,
            copyCounter: 0,
            firstBlock: 5,
            blockCount: blockCount,
            commentsAddr: commentsAddress
        )
    }

    /// A body of deterministic pseudo-random bytes, so a dropped or
    /// duplicated run shows up rather than blending into zeros.
    private func makeBody(length: Int, seed: UInt32 = 0xC0FFEE) -> GoDData {
        var bytes = [UInt8](repeating: 0, count: length)
        var rng = seed
        for i in 0..<length {
            rng = rng &* 1664525 &+ 1013904223
            bytes[i] = UInt8(truncatingIfNeeded: rng >> 24)
        }
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    // MARK: - Layout derivation

    /// Pokémon XD and Colosseum: RGB5A3 banner, eight CI8 frames sharing
    /// one palette, images at 0x40 and comments before them at 0.
    func testDerivesTheGeniusSonorityLayout() throws {
        let header = makeHeader(
            flags: 0x02, imageOffset: 0x40, iconFormat: 0x5555, animationSpeed: 0x5555
        )
        let layout = try XCTUnwrap(CardImageBlock.layout(header: header))

        XCTAssertEqual(layout.bannerFormat, .rgb5a3)
        XCTAssertEqual(layout.animationOrder, .loop)
        XCTAssertEqual(layout.liveSlots, Array(0..<8))
        XCTAssertEqual(layout.offset, 0x40)
        XCTAssertEqual(layout.end, 0x3A40)
        XCTAssertEqual(layout.sharedPaletteOffset, 0x3840)

        // Banner 0x1800, then eight 0x400 frames, then one 0x200 palette.
        XCTAssertEqual(layout.pieces.count, 10)
        XCTAssertEqual(layout.pieces[0].offset, 0x40)
        XCTAssertEqual(layout.pieces[0].length, 0x1800)
        XCTAssertEqual(layout.pieces[1].offset, 0x1840)
        XCTAssertEqual(layout.pieces[1].length, 0x400)
    }

    /// Luigi's Mansion: CI8 banner, ping-pong animation, three frames in
    /// slots 0, 3 and 7 with dead slots between, and comments *after*
    /// the images. Nothing about this shape is like the Pokémon one.
    func testDerivesALayoutWithSparseFramesAndTrailingComments() throws {
        let header = makeHeader(
            flags: 0x05, imageOffset: 0, iconFormat: 0x4041,
            animationSpeed: 0xFFFF, commentsAddress: 0x1C00
        )
        let layout = try XCTUnwrap(CardImageBlock.layout(header: header))

        XCTAssertEqual(layout.bannerFormat, .ci8)
        XCTAssertEqual(layout.animationOrder, .pingPong)
        XCTAssertEqual(layout.liveSlots, [0, 3, 7])
        XCTAssertEqual(layout.offset, 0)
        // CI8 banner 0xE00, three shared-palette frames 0x400 each, palette 0x200.
        XCTAssertEqual(layout.end, 0x1C00)
        XCTAssertEqual(layout.sharedPaletteOffset, 0x1A00)

        // The comments start exactly where the images end.
        let derived = try CardSaveLayout.derived(header: header, bodyLength: 0x6000)
        XCTAssertEqual(derived.metadataRegion?.length, 0x1C40)
    }

    func testNoImagesWhenImageOffsetIsAbsent() {
        let header = makeHeader(
            flags: 0x02, imageOffset: CardImageBlock.noImageOffset,
            iconFormat: 0x5555, animationSpeed: 0x5555
        )
        XCTAssertNil(CardImageBlock.layout(header: header))
    }

    func testDeadSpeedSlotsAreSkipped() throws {
        // Two frames declared, but only the first has a speed.
        let header = makeHeader(
            flags: 0x00, imageOffset: 0, iconFormat: 0x0005, animationSpeed: 0x0001
        )
        let layout = try XCTUnwrap(CardImageBlock.layout(header: header))
        XCTAssertEqual(layout.liveSlots, [0])
        XCTAssertEqual(layout.end, 0x400 + 0x200)
    }

    /// A live frame after a dead slot is the one shape where libogc and
    /// Dolphin disagree. Real saves never do it; the flag exists so a
    /// caller can warn rather than silently pick a reading.
    func testFrameWalkAmbiguityIsReported() {
        // Slots 0 and 2 are live, slot 1 is dead. libogc skips slot 1 and
        // still finds slot 2; Dolphin stops at slot 1 and never sees it.
        let ambiguous = makeHeader(
            flags: 0x00, imageOffset: 0, iconFormat: 0x0011, animationSpeed: 0x0011
        )
        XCTAssertTrue(CardImageBlock.frameWalkIsAmbiguous(header: ambiguous))
        XCTAssertEqual(CardImageBlock.layout(header: ambiguous)?.liveSlots, [0, 2])

        let contiguous = makeHeader(
            flags: 0x02, imageOffset: 0x40, iconFormat: 0x5555, animationSpeed: 0x5555
        )
        XCTAssertFalse(CardImageBlock.frameWalkIsAmbiguous(header: contiguous))
    }

    func testUniquePaletteFramesCarryTheirOwnPalette() throws {
        // One frame, format 3 (CI8 with its own palette), no shared one.
        let header = makeHeader(
            flags: 0x00, imageOffset: 0, iconFormat: 0x0003, animationSpeed: 0x0001
        )
        let layout = try XCTUnwrap(CardImageBlock.layout(header: header))
        XCTAssertNil(layout.sharedPaletteOffset)
        XCTAssertEqual(layout.end, 0x400 + 0x200)
    }

    // MARK: - Decode / encode

    /// Every format combination has to survive a round trip exactly.
    /// RGB5A3 is invertible per channel, and paletted images keep their
    /// indices and palette order rather than being flattened to color,
    /// so neither has an excuse to drift.
    func testEveryFormatRoundTripsByteIdentically() throws {
        let cases: [(name: String, flags: UInt8, iconFormat: UInt16, speed: UInt16)] = [
            ("RGB5A3 banner, 8 shared-palette frames", 0x02, 0x5555, 0x5555),
            ("CI8 banner, sparse shared-palette frames", 0x05, 0x4041, 0xFFFF),
            ("no banner, RGB5A3 frames", 0x00, 0x000A, 0x0005),
            ("no banner, unique-palette frames", 0x00, 0x000F, 0x0005),
            ("RGB5A3 banner, mixed frame formats", 0x02, 0x0039, 0x0015),
            ("banner only, no frames", 0x01, 0x0000, 0x0000),
        ]

        for testCase in cases {
            let header = makeHeader(
                flags: testCase.flags, imageOffset: 0x40,
                iconFormat: testCase.iconFormat, animationSpeed: testCase.speed,
                blockCount: 8
            )
            let body = makeBody(length: 8 * GCIFile.blockSize)
            let block = try XCTUnwrap(
                CardImageBlock.decode(body: body, header: header),
                testCase.name
            )
            let reencoded = try block.encoded()

            let original = Array(
                body.rawBytes[block.layout.offset..<block.layout.end]
            )
            XCTAssertEqual(
                reencoded.rawBytes, original,
                "\(testCase.name) did not round-trip"
            )
        }
    }

    func testDecodedBannerHasTheRightDimensions() throws {
        let header = makeHeader(
            flags: 0x02, imageOffset: 0x40, iconFormat: 0x5555, animationSpeed: 0x5555,
            blockCount: 8
        )
        let body = makeBody(length: 8 * GCIFile.blockSize)
        let block = try XCTUnwrap(CardImageBlock.decode(body: body, header: header))

        guard case let .direct(banner)? = block.banner else {
            return XCTFail("RGB5A3 banner should decode as direct color")
        }
        XCTAssertEqual(banner.width, CardImageBlock.bannerWidth)
        XCTAssertEqual(banner.height, CardImageBlock.bannerHeight)

        XCTAssertEqual(block.frames.count, 8)
        guard case let .paletted(indices, palette) = block.frames[0].image else {
            return XCTFail("CI8 frame should decode as palette indices")
        }
        XCTAssertEqual(indices.count, CardImageBlock.iconWidth * CardImageBlock.iconHeight)
        XCTAssertEqual(palette.count, CardImageBlock.paletteEntryCount)
        XCTAssertEqual(palette, block.sharedPalette)
    }

    /// Only one shared palette is stored, so every frame using it has to
    /// agree. An edited frame that rebuilt its own palette would silently
    /// recolor its siblings if the encoder just picked one.
    func testMismatchedSharedPaletteIsRejected() throws {
        let header = makeHeader(
            flags: 0x00, imageOffset: 0, iconFormat: 0x0005, animationSpeed: 0x0005,
            blockCount: 4
        )
        let body = makeBody(length: 4 * GCIFile.blockSize)
        let block = try XCTUnwrap(CardImageBlock.decode(body: body, header: header))
        XCTAssertEqual(block.frames.count, 2)

        var drifted = try XCTUnwrap(block.sharedPalette)
        drifted[0] = GXColor(r: 1, g: 2, b: 3, a: 255)
        let tampered = CardImageBlock(
            layout: block.layout,
            banner: block.banner,
            frames: [
                block.frames[0],
                CardImageBlock.Frame(
                    slot: block.frames[1].slot,
                    format: block.frames[1].format,
                    speed: block.frames[1].speed,
                    image: .paletted(
                        indices: {
                            if case let .paletted(indices, _) = block.frames[1].image { return indices }
                            return []
                        }(),
                        palette: drifted
                    )
                ),
            ],
            sharedPalette: block.sharedPalette
        )

        XCTAssertThrowsError(try tampered.encoded()) { error in
            guard case CardImageBlockError.sharedPaletteMismatch = error else {
                return XCTFail("expected a shared-palette mismatch, got \(error)")
            }
        }
    }

    // MARK: - PNG artifacts

    /// The whole point of writing paletted images as indexed PNGs: a
    /// full trip out to PNG files and back has to reproduce the original
    /// bytes. An RGBA PNG would collapse duplicate palette entries and
    /// lose the index map, and this is the test that would catch it.
    func testEveryFormatRoundTripsThroughPNGArtifacts() throws {
        let cases: [(name: String, flags: UInt8, iconFormat: UInt16, speed: UInt16)] = [
            ("RGB5A3 banner, 8 shared-palette frames", 0x02, 0x5555, 0x5555),
            ("CI8 banner, sparse shared-palette frames", 0x05, 0x4041, 0xFFFF),
            ("no banner, RGB5A3 frames", 0x00, 0x000A, 0x0005),
            ("no banner, unique-palette frames", 0x00, 0x000F, 0x0005),
            ("RGB5A3 banner, mixed frame formats", 0x02, 0x0039, 0x0015),
        ]

        for testCase in cases {
            let header = makeHeader(
                flags: testCase.flags, imageOffset: 0x40,
                iconFormat: testCase.iconFormat, animationSpeed: testCase.speed,
                blockCount: 8
            )
            let body = makeBody(length: 8 * GCIFile.blockSize)
            let block = try XCTUnwrap(
                CardImageBlock.decode(body: body, header: header), testCase.name
            )
            XCTAssertTrue(block.verifies(against: body), "\(testCase.name) did not verify")

            let artifacts = try block.pngArtifacts()
            let rebuilt = try CardImageBlock.fromArtifacts(
                layout: block.layout, pngData: artifacts
            )
            let reencoded = try rebuilt.encoded()
            let original = Array(body.rawBytes[block.layout.offset..<block.layout.end])
            XCTAssertEqual(
                reencoded.rawBytes, original,
                "\(testCase.name) did not survive the PNG round trip"
            )
        }
    }

    /// A paletted image handed an RGBA PNG is refused rather than
    /// re-indexed, because re-indexing would invent a palette.
    func testPalettedImageRejectsAnRGBAPNG() throws {
        let rgba = GoDImage(
            width: CardImageBlock.iconWidth,
            height: CardImageBlock.iconHeight,
            pixels: makeBody(length: CardImageBlock.iconWidth * CardImageBlock.iconHeight * 4)
        )
        let png = try XCTUnwrap(rgba.pngData())

        XCTAssertThrowsError(
            try CardImageBlock.Image.fromPNG(
                png, paletted: true,
                width: CardImageBlock.iconWidth, height: CardImageBlock.iconHeight
            )
        ) { error in
            guard case CardImageBlockError.pngNotIndexed = error else {
                return XCTFail("expected a not-indexed error, got \(error)")
            }
        }
    }

    func testPNGArtifactsAreNamedAfterTheirSlot() throws {
        let header = makeHeader(
            flags: 0x05, imageOffset: 0, iconFormat: 0x4041, animationSpeed: 0xFFFF,
            blockCount: 4
        )
        let body = makeBody(length: 4 * GCIFile.blockSize)
        let block = try XCTUnwrap(CardImageBlock.decode(body: body, header: header))
        let artifacts = try block.pngArtifacts()

        XCTAssertEqual(
            Set(artifacts.keys),
            ["banner.png", "icon-0.png", "icon-3.png", "icon-7.png"]
        )
    }

    func testBlockPastTheEndOfTheBodyThrows() {
        let header = makeHeader(
            flags: 0x02, imageOffset: 0x40, iconFormat: 0x5555, animationSpeed: 0x5555,
            blockCount: 1
        )
        let body = makeBody(length: GCIFile.blockSize)
        XCTAssertThrowsError(try CardImageBlock.decode(body: body, header: header)) { error in
            guard case CardImageBlockError.blockOutOfBounds = error else {
                return XCTFail("expected an out-of-bounds error, got \(error)")
            }
        }
    }
}
