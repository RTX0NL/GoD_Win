//
//  NKitGCConverterTests.swift
//  DolphinTests
//
//  Round-trips a synthetic GameCube ISO through the NKit encoder and
//  decoder. The disc is small (1 MiB) but shaped like a real one — boot
//  sector, apploader, DOL, FST, one file — and its junk run starts with
//  the zero allowance a real disc's does, so the gaps encode the way
//  retail ones do.
//
//  The gate that matters is `NKitRealCorpusTests`, which runs against an
//  actual NKit v1 image. These cover the refusals and the edges one real
//  disc doesn't reach.
//

import XCTest
import Foundation
import GoDFoundation
@testable import Dolphin

final class NKitGCConverterTests: XCTestCase {

    private static let gameID = "GXXE"
    private static let discNumber: UInt8 = 0
    private static let totalLength = 0x10_0000     // 1 MiB, a whole number of PRNG blocks
    private static let fileEnd = 0x6000            // where the trailing gap starts

    /// What the trailing gap holds.
    private enum Tail {
        /// Zero allowance then junk — what a retail disc looks like.
        case junk
        /// Entirely zeros, as a scrubbed image would be.
        case scrubbed
        /// Junk with a block of real data in the middle, so the gap can
        /// only be described block by block.
        case mixed
    }

    // MARK: - Fixture

    private static func syntheticISO(
        gameID: String = gameID,
        disc: UInt8 = discNumber,
        tail: Tail = .junk
    ) -> GoDData {
        let iso = GoDData(length: totalLength, byteOrder: .big)

        for (index, byte) in Array(gameID.utf8).enumerated() {
            _ = iso.write(byte, atAddress: index)
        }
        _ = iso.write(disc, atAddress: 0x06)
        _ = iso.write(UInt32(0xC233_9F3D), atAddress: 0x1C)
        for (index, byte) in Array("SYNTHETIC DISC".utf8).enumerated() {
            _ = iso.write(byte, atAddress: 0x20 + index)
        }

        let dolOffset = 0x3000
        let fstOffset = 0x4000
        _ = iso.write(UInt32(dolOffset), atAddress: 0x420)
        _ = iso.write(UInt32(fstOffset), atAddress: 0x424)
        _ = iso.write(UInt32(32), atAddress: 0x428)          // FST size

        _ = iso.write(UInt32(1), atAddress: 0x2454)          // apploader size
        _ = iso.write(UInt32(0), atAddress: 0x2458)          // apploader trailer size

        _ = iso.write(UInt32(0x100), atAddress: dolOffset)          // text[0] offset
        _ = iso.write(UInt32(0x200), atAddress: dolOffset + 0x90)   // text[0] size

        _ = iso.write(UInt8(1), atAddress: fstOffset)               // root directory
        _ = iso.write(UInt32(2), atAddress: fstOffset + 8)          // entry count
        _ = iso.write(UInt8(0), atAddress: fstOffset + 12)          // entry 1 is a file
        _ = iso.write(UInt32(0x5000), atAddress: fstOffset + 16)
        _ = iso.write(UInt32(0x1000), atAddress: fstOffset + 20)

        for offset in 0x5000 ..< fileEnd {
            _ = iso.write(UInt8(truncatingIfNeeded: offset &* 7 &+ 3), atAddress: offset)
        }

        guard tail != .scrubbed else { return iso }
        // A junk run begins with the zero allowance, exactly as a real
        // disc's does — `nullsAllowance` bytes past the 4-byte aligned
        // end of the file before it.
        let junkStart = fileEnd + NKitGCImage.nullsAllowance
        let junk = JunkStream(gameID: gameID, disc: disc, length: NKitGCImage.gamecubeDiscSize)
        let bytes = junk.read(at: UInt64(junkStart), count: totalLength - junkStart)
        _ = iso.write(GoDData(byteStream: bytes, byteOrder: .big), atAddress: junkStart)

        if tail == .mixed {
            // One 0x100 block of content the PRNG can't produce, which
            // forces the whole gap onto the block-by-block encoding.
            let at = fileEnd + 0x1000
            for offset in at ..< at + 0x100 {
                _ = iso.write(UInt8(truncatingIfNeeded: offset &* 31 &+ 17), atAddress: offset)
            }
        }
        return iso
    }

    // MARK: - Round trip

    func testShrinksAndRestoresAJunkTail() throws {
        let iso = Self.syntheticISO(tail: .junk)
        let nkit = try NKitGCConverter.build(iso: iso)

        XCTAssertLessThan(nkit.length, iso.length, "packing the files should shrink the image")
        XCTAssertEqual(
            Array(nkit.rawBytes[NKitHeader.blockOffset ..< NKitHeader.blockOffset + 8]),
            NKitHeader.magic
        )
        XCTAssertEqual(DiscImageFormat.detect(in: nkit), .nkitGC)

        let header = try NKitHeader(binary: nkit, platform: .gamecube)
        XCTAssertEqual(header.originalImageSize, UInt64(iso.length))
        XCTAssertEqual(header.originalCRC, CRC32.compute(iso.rawBytes))
        XCTAssertNil(header.junkOverrideID)

        XCTAssertEqual(try NKitGCConverter.dump(nkit: nkit).rawBytes, iso.rawBytes)
    }

    func testShrinksAndRestoresAScrubbedTail() throws {
        let iso = Self.syntheticISO(tail: .scrubbed)
        let nkit = try NKitGCConverter.build(iso: iso)
        XCTAssertLessThan(nkit.length, iso.length)
        XCTAssertEqual(try NKitGCConverter.dump(nkit: nkit).rawBytes, iso.rawBytes)
    }

    func testShrinksAndRestoresAGapThatIsNeitherJunkNorZeros() throws {
        // Exercises the block-by-block encoding: junk, one block of real
        // data, junk again.
        let iso = Self.syntheticISO(tail: .mixed)
        let nkit = try NKitGCConverter.build(iso: iso)
        XCTAssertLessThan(nkit.length, iso.length)
        XCTAssertEqual(try NKitGCConverter.dump(nkit: nkit).rawBytes, iso.rawBytes)
    }

    func testBuiltImageCarriesTheOriginalDiscCRC() throws {
        // The force value at 0x20C: the shrunk file's own CRC-32 comes
        // out equal to the original disc's, so a Redump hash matches
        // without restoring first.
        let iso = Self.syntheticISO()
        let nkit = try NKitGCConverter.build(iso: iso)
        XCTAssertEqual(CRC32.compute(nkit.rawBytes), CRC32.compute(iso.rawBytes))
    }

    func testTheImageIsPaddedToAWholeSector() throws {
        let nkit = try NKitGCConverter.build(iso: Self.syntheticISO())
        XCTAssertEqual(nkit.length % NKitGCImage.imageAlignment, 0)
    }

    func testJunkOverrideIDSeedsBothDirections() throws {
        // A disc whose padding was written under another title's ID: the
        // override has to reach the decoder through the header.
        let iso = Self.syntheticISO(tail: .scrubbed)
        let junkStart = Self.fileEnd + NKitGCImage.nullsAllowance
        let junk = JunkStream(gameID: "GC6E", disc: 0, length: NKitGCImage.gamecubeDiscSize)
        let bytes = junk.read(at: UInt64(junkStart), count: Self.totalLength - junkStart)
        _ = iso.write(GoDData(byteStream: bytes, byteOrder: .big), atAddress: junkStart)

        let nkit = try NKitGCConverter.build(iso: iso, junkOverrideID: "GC6E")
        XCTAssertEqual(try NKitHeader(binary: nkit, platform: .gamecube).junkOverrideID, "GC6E")
        XCTAssertEqual(try NKitGCConverter.dump(nkit: nkit).rawBytes, iso.rawBytes)

        // Without it the disc's own ID doesn't reproduce that run, so the
        // gap has to be stored rather than regenerated — still correct,
        // just bigger.
        let unseeded = try NKitGCConverter.build(iso: iso)
        XCTAssertGreaterThan(unseeded.length, nkit.length)
        XCTAssertEqual(try NKitGCConverter.dump(nkit: unseeded).rawBytes, iso.rawBytes)
    }

    // MARK: - Refusals

    func testDumpRefusesAnImageThatDoesNotRestoreToItsRecordedCRC() throws {
        // The gate that actually holds. A structural check can't see a
        // packed image — NKit rewrites the FST to the packed layout, so
        // every file fits by construction — and a real Pokemon XD US
        // image once restored 99.24 % wrong and reported success.
        let nkit = try NKitGCConverter.build(iso: Self.syntheticISO())
        let recorded = try NKitHeader(binary: nkit, platform: .gamecube).originalCRC
        _ = nkit.write(recorded ^ 0xFFFF_FFFF, atAddress: NKitHeader.blockOffset + 0x08)

        XCTAssertThrowsError(try NKitGCConverter.dump(nkit: nkit)) { error in
            guard case let NKitGCConverter.Error.restoredImageCRCMismatch(expected, actual) = error else {
                return XCTFail("Expected restoredImageCRCMismatch, got \(error)")
            }
            XCTAssertEqual(expected, recorded ^ 0xFFFF_FFFF)
            XCTAssertEqual(actual, recorded)
        }
    }

    func testBuildRefusesAnISOWithDataInTheMetadataRegion() {
        let iso = Self.syntheticISO()
        _ = iso.write(UInt8(0x41), atAddress: NKitHeader.blockOffset + 4)
        XCTAssertThrowsError(try NKitGCConverter.build(iso: iso)) { error in
            guard case NKitGCConverter.Error.metadataRegionNotEmpty(let offset) = error else {
                return XCTFail("Expected metadataRegionNotEmpty, got \(error)")
            }
            XCTAssertEqual(offset, NKitHeader.blockOffset + 4)
        }
    }

    func testBuildRefusesAnImageThatIsAlreadyNKit() throws {
        let nkit = try NKitGCConverter.build(iso: Self.syntheticISO())
        XCTAssertThrowsError(try NKitGCConverter.build(iso: nkit)) { error in
            guard case NKitGCConverter.Error.alreadyNKit = error else {
                return XCTFail("Expected alreadyNKit, got \(error)")
            }
        }
    }

    func testBuildRefusesSomethingThatIsNotAGameCubeISO() {
        let notADisc = GoDData(length: Self.totalLength, byteOrder: .big)
        XCTAssertThrowsError(try NKitGCConverter.build(iso: notADisc)) { error in
            guard case NKitGCConverter.Error.notAGameCubeISO = error else {
                return XCTFail("Expected notAGameCubeISO, got \(error)")
            }
        }
    }

    func testBuildRefusesAJunkOverrideThatIsNotFourCharacters() {
        XCTAssertThrowsError(try NKitGCConverter.build(iso: Self.syntheticISO(), junkOverrideID: "GC6")) { error in
            guard case NKitGCConverter.Error.invalidJunkOverrideID = error else {
                return XCTFail("Expected invalidJunkOverrideID, got \(error)")
            }
        }
    }

    func testBothDirectionsRefuseAWiiImage() throws {
        let iso = Self.syntheticISO()
        _ = iso.write(UInt32(0x5D1C_9EA3), atAddress: 0x18)
        XCTAssertThrowsError(try NKitGCConverter.build(iso: iso)) { error in
            guard case NKitGCConverter.Error.wiiNotSupported = error else {
                return XCTFail("Expected wiiNotSupported, got \(error)")
            }
        }

        let nkit = try NKitGCConverter.build(iso: Self.syntheticISO())
        _ = nkit.write(UInt32(0x5D1C_9EA3), atAddress: 0x18)
        XCTAssertThrowsError(try NKitGCConverter.dump(nkit: nkit)) { error in
            guard case NKitGCConverter.Error.wiiNotSupported = error else {
                return XCTFail("Expected wiiNotSupported, got \(error)")
            }
        }
    }

    // MARK: - Layout rules

    func testAFileOccupiesItsLengthRoundedUpToFourBytes() {
        // The rule that decides where the next gap starts: a three-byte
        // file is followed by one byte that belongs to it, not the gap.
        XCTAssertEqual(NKitGCImage.align4(0), 0)
        XCTAssertEqual(NKitGCImage.align4(1), 4)
        XCTAssertEqual(NKitGCImage.align4(3), 4)
        XCTAssertEqual(NKitGCImage.align4(4), 4)
        XCTAssertEqual(NKitGCImage.align4(5), 8)
    }

    func testTheZeroAllowanceRunsOutAndDisappearsOnALargeInteriorGap() {
        let allowance = NKitGCImage.nullsAllowance
        // A gap shorter than the allowance is entirely zeros.
        XCTAssertEqual(
            NKitGCImage.leadingNulls(gapSize: 8, position: 0, nullsPos: allowance, firstOrLast: false),
            8
        )
        // An ordinary gap takes the whole allowance.
        XCTAssertEqual(
            NKitGCImage.leadingNulls(gapSize: 0x1000, position: 0, nullsPos: allowance, firstOrLast: false),
            allowance
        )
        // A large interior gap gets none...
        XCTAssertEqual(
            NKitGCImage.leadingNulls(
                gapSize: NKitGCImage.largeGapThreshold, position: 0,
                nullsPos: allowance, firstOrLast: false
            ),
            0
        )
        // ...unless it is the first or last, which keeps it.
        XCTAssertEqual(
            NKitGCImage.leadingNulls(
                gapSize: NKitGCImage.largeGapThreshold, position: 0,
                nullsPos: allowance, firstOrLast: true
            ),
            allowance
        )
    }
}
