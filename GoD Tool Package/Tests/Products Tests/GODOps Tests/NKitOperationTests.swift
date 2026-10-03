//
//  NKitOperationTests.swift
//  GODOpsTests
//
//  Runs the real NKitBuild/NKitDump operations against an InMemoryFST with a
//  synthetic GameCube ISO: boot sector, apploader, DOL, FST and one file,
//  then a gap that opens with the zero allowance a real disc's junk run
//  does. The gate that matters is `NKitRealCorpusTests`.
//

import XCTest
import Foundation
import GoDFoundation
import Dolphin
@testable import GODOps

final class NKitOperationTests: XCTestCase {

    private static let gameID = "GXXE"
    private static let totalLength = 0x10_0000   // 1 MiB, a whole number of PRNG blocks
    private static let fileEnd = 0x6000          // first junk byte

    private static let isoFile = File("/project/game.iso")
    private static let nkitFile = File("/project/game.nkit.iso")
    private static let restoredFile = File("/project/restored.iso")

    // MARK: - Fixture

    private static func syntheticISO(junkTail: Bool = true) -> GoDData {
        let iso = GoDData(length: totalLength, byteOrder: .big)

        for (index, byte) in Array(gameID.utf8).enumerated() {
            _ = iso.write(byte, atAddress: index)
        }
        _ = iso.write(UInt32(0xC233_9F3D), atAddress: 0x1C)

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

        for offset in 0x5000..<fileEnd {
            _ = iso.write(UInt8(truncatingIfNeeded: offset &* 7 &+ 3), atAddress: offset)
        }

        guard junkTail else { return iso }
        // A junk run begins with the zero allowance a real disc's does.
        let junkStart = fileEnd + 0x1C
        let junk = JunkStream(gameID: gameID, disc: 0, length: 1_459_978_240)
        let tail = junk.read(at: UInt64(junkStart), count: totalLength - junkStart)
        _ = iso.write(GoDData(byteStream: tail, byteOrder: .big), atAddress: junkStart)
        return iso
    }

    @discardableResult
    private func seedISO(in fst: InMemoryFST, junkTail: Bool = true) -> GoDData {
        let iso = Self.syntheticISO(junkTail: junkTail)
        try? fst.writeFile(iso, at: Self.isoFile, overwrite: true)
        return iso
    }

    private func buildNKit(in fst: InMemoryFST, overwrite: Bool = true, logger: Logger = SilentLogger()) throws {
        let config = NKitBuild.Config(
            isoPath: Self.isoFile,
            nkitPath: Self.nkitFile,
            overwrite: overwrite
        )
        try NKitBuild.build(config: config, settings: .default, fileSystem: fst, logger: logger)
    }

    // MARK: - Round trip

    func testNKitBuildProducesAShrunkImageWithTheNKitHeader() throws {
        let fst = InMemoryFST()
        let iso = seedISO(in: fst)
        try buildNKit(in: fst)

        let nkit = try XCTUnwrap(fst.readFile(at: Self.nkitFile)?.allData)
        XCTAssertLessThan(nkit.length, iso.length, "packing the files should shrink the image")

        let header = try NKitHeader(binary: nkit, platform: .gamecube)
        XCTAssertEqual(header.originalImageSize, UInt64(iso.length))
        XCTAssertEqual(header.originalCRC, CRC32.compute(iso.rawBytes))
        XCTAssertEqual(DiscImageFormat.detect(in: nkit), .nkitGC)
    }

    func testNKitDumpRestoresTheOriginalISOBytes() throws {
        let fst = InMemoryFST()
        let iso = seedISO(in: fst)
        try buildNKit(in: fst)

        let config = NKitDump.Config(nkitPath: Self.nkitFile, isoPath: Self.restoredFile)
        try NKitDump.dump(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())

        let restored = try XCTUnwrap(fst.readFile(at: Self.restoredFile)?.allData)
        XCTAssertEqual(restored.length, iso.length)
        XCTAssertEqual(restored.rawBytes, iso.rawBytes, "the junk tail must come back byte for byte")
    }

    func testNKitBuildWithAJunkOverrideIDRoundTrips() throws {
        // A disc whose padding was written under another title's ID: the
        // override is what lets the run be regenerated rather than stored.
        let fst = InMemoryFST()
        let iso = Self.syntheticISO(junkTail: false)
        let junkStart = Self.fileEnd + 0x1C
        let junk = JunkStream(gameID: "GC6E", disc: 0, length: 1_459_978_240)
        let tail = junk.read(at: UInt64(junkStart), count: Self.totalLength - junkStart)
        _ = iso.write(GoDData(byteStream: tail, byteOrder: .big), atAddress: junkStart)
        try fst.writeFile(iso, at: Self.isoFile, overwrite: true)

        let config = NKitBuild.Config(
            isoPath: Self.isoFile,
            nkitPath: Self.nkitFile,
            junkOverrideID: "GC6E"
        )
        try NKitBuild.build(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())

        let nkit = try XCTUnwrap(fst.readFile(at: Self.nkitFile)?.allData)
        XCTAssertLessThan(nkit.length, iso.length)

        try NKitDump.dump(
            config: .init(nkitPath: Self.nkitFile, isoPath: Self.restoredFile),
            settings: .default,
            fileSystem: fst,
            logger: SilentLogger()
        )
        let restored = try XCTUnwrap(fst.readFile(at: Self.restoredFile)?.allData)
        XCTAssertEqual(restored.rawBytes, iso.rawBytes)
    }

    func testNKitBuildShrinksAScrubbedTailToo() throws {
        // A gap of zeros compresses to a marker just as a junk run does.
        let fst = InMemoryFST()
        let iso = seedISO(in: fst, junkTail: false)
        try buildNKit(in: fst)

        let nkit = try XCTUnwrap(fst.readFile(at: Self.nkitFile)?.allData)
        XCTAssertLessThan(nkit.length, iso.length)

        try NKitDump.dump(
            config: .init(nkitPath: Self.nkitFile, isoPath: Self.restoredFile),
            settings: .default,
            fileSystem: fst,
            logger: SilentLogger()
        )
        let restored = try XCTUnwrap(fst.readFile(at: Self.restoredFile)?.allData)
        XCTAssertEqual(restored.rawBytes, iso.rawBytes)
    }

    // MARK: - Refusals

    func testNKitBuildMissingISOThrows() {
        let config = NKitBuild.Config(isoPath: File("/project/missing.iso"), nkitPath: Self.nkitFile)
        XCTAssertThrowsError(
            try NKitBuild.build(config: config, settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger())
        ) { error in
            guard case NKitErrors.inputNotFound = error else {
                return XCTFail("Expected NKitErrors.inputNotFound, got \(error)")
            }
        }
    }

    func testNKitDumpMissingNKitThrows() {
        let config = NKitDump.Config(nkitPath: File("/project/missing.nkit.iso"), isoPath: Self.restoredFile)
        XCTAssertThrowsError(
            try NKitDump.dump(config: config, settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger())
        ) { error in
            guard case NKitErrors.inputNotFound = error else {
                return XCTFail("Expected NKitErrors.inputNotFound, got \(error)")
            }
        }
    }

    func testNKitBuildRefusesAnISOWithDataWhereTheHeaderGoes() throws {
        let fst = InMemoryFST()
        let iso = Self.syntheticISO()
        _ = iso.write(UInt8(0x41), atAddress: NKitHeader.blockOffset + 4)
        try fst.writeFile(iso, at: Self.isoFile, overwrite: true)

        XCTAssertThrowsError(try buildNKit(in: fst)) { error in
            guard case NKitGCConverter.Error.metadataRegionNotEmpty = error else {
                return XCTFail("Expected metadataRegionNotEmpty, got \(error)")
            }
        }
        XCTAssertNil(fst.readFile(at: Self.nkitFile), "a refused build must not leave an output behind")
    }

    // MARK: - Overwrite

    func testNKitBuildRespectsOverwriteFlag() throws {
        let fst = InMemoryFST()
        seedISO(in: fst)
        let sentinel = GoDData(byteStream: [0xDE, 0xAD], byteOrder: .big)
        try fst.writeFile(sentinel, at: Self.nkitFile, overwrite: true)

        let logger = RecordingLogger()
        XCTAssertThrowsError(try buildNKit(in: fst, overwrite: false, logger: logger)) { error in
            guard case FSTErrors.itemExists = error else {
                return XCTFail("Expected FSTErrors.itemExists, got \(error)")
            }
        }
        XCTAssertFalse(
            logger.entries.contains { if case .info(let message) = $0 { return message.hasPrefix("Shrunk") } else { return false } },
            "Skipped write must not log success"
        )

        let after = try XCTUnwrap(fst.readFile(at: Self.nkitFile)?.allData)
        XCTAssertEqual(after.rawBytes, [0xDE, 0xAD], "overwrite=false must not replace an existing NKit image")
    }

    func testNKitDumpRespectsOverwriteFlag() throws {
        let fst = InMemoryFST()
        seedISO(in: fst)
        try buildNKit(in: fst)
        let sentinel = GoDData(byteStream: [0xBE, 0xEF], byteOrder: .big)
        try fst.writeFile(sentinel, at: Self.restoredFile, overwrite: true)

        let config = NKitDump.Config(nkitPath: Self.nkitFile, isoPath: Self.restoredFile, overwrite: false)
        let logger = RecordingLogger()
        XCTAssertThrowsError(
            try NKitDump.dump(config: config, settings: .default, fileSystem: fst, logger: logger)
        ) { error in
            guard case FSTErrors.itemExists = error else {
                return XCTFail("Expected FSTErrors.itemExists, got \(error)")
            }
        }
        XCTAssertFalse(
            logger.entries.contains { if case .info(let message) = $0 { return message.hasPrefix("Restored") } else { return false } },
            "Skipped write must not log success"
        )

        let after = try XCTUnwrap(fst.readFile(at: Self.restoredFile)?.allData)
        XCTAssertEqual(after.rawBytes, [0xBE, 0xEF], "overwrite=false must not replace an existing ISO")
    }
}
