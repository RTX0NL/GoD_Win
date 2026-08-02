//
//  CISOOperationTests.swift
//  GODOpsTests
//
//  Runs the real CISOBuild/CISODump operations against an InMemoryFST with a
//  synthetic ISO of mixed zero / non-zero 32 KiB blocks (0x8000 is the spec
//  minimum block size — keeps the test cheap vs the 2 MiB default).
//

import XCTest
import Foundation
import GoDFoundation
import Dolphin
@testable import GODOps

final class CISOOperationTests: XCTestCase {

    private static let blockSize: UInt32 = 0x8000

    /// Pattern ends on a non-zero block so the parser's trimmed block map
    /// implies exactly the original disc size (nil targetDiscSize restores
    /// byte-for-byte).
    private static let pattern = [true, false, true, true, false, false, true]

    private static func syntheticISO() -> GoDData {
        let bs = Int(blockSize)
        let out = GoDData(byteOrder: .big)
        for (i, present) in pattern.enumerated() {
            for b in 0..<bs {
                // Explicitly typed: a bare ternary in this DataConvertible
                // context type-checks as a wider integer and appends 4 bytes.
                let byte: UInt8 = present ? UInt8(truncatingIfNeeded: i * 13 + b) : 0
                out.append(byte)
            }
        }
        return out
    }

    @discardableResult
    private func seedISO(in fst: InMemoryFST) -> GoDData {
        let iso = Self.syntheticISO()
        try? fst.writeFile(iso, at: File("/project/game.iso"), overwrite: true)
        return iso
    }

    private func buildCISO(in fst: InMemoryFST) throws {
        let config = CISOBuild.Config(
            isoPath: File("/project/game.iso"),
            cisoPath: File("/project/game.ciso"),
            blockSize: Self.blockSize,
            overwrite: true
        )
        try CISOBuild.build(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
    }

    func testCisoBuildProducesParsableCISO() throws {
        let fst = InMemoryFST()
        let iso = seedISO(in: fst)
        try buildCISO(in: fst)

        let ciso = try XCTUnwrap(fst.readFile(at: File("/project/game.ciso"))?.allData)
        XCTAssertEqual(Array(ciso.rawBytes.prefix(4)), CISOFile.magic)

        let parsed = try CISOFile(binary: ciso, discSize: UInt64(iso.length))
        XCTAssertEqual(parsed.blockSize, Self.blockSize)
        XCTAssertEqual(parsed.blockMap, Self.pattern)

        // Header + one body block per present map entry, zero blocks dropped.
        let presentBlocks = Self.pattern.filter { $0 }.count
        XCTAssertEqual(ciso.length, CISOFile.headerSize + presentBlocks * Int(Self.blockSize))
    }

    func testCisoDumpRestoresOriginalISOBytes() throws {
        let fst = InMemoryFST()
        let iso = seedISO(in: fst)
        try buildCISO(in: fst)

        let dumpConfig = CISODump.Config(
            cisoPath: File("/project/game.ciso"),
            isoPath: File("/project/restored.iso")
        )
        try CISODump.dump(config: dumpConfig, settings: .default, fileSystem: fst, logger: SilentLogger())

        let restored = try XCTUnwrap(fst.readFile(at: File("/project/restored.iso"))?.allData)
        XCTAssertEqual(restored.length, iso.length)
        XCTAssertEqual(restored.rawBytes, iso.rawBytes, "zero blocks must be restored in place")
    }

    func testCisoDumpWithTargetDiscSizePadsToLength() throws {
        let fst = InMemoryFST()
        let iso = seedISO(in: fst)
        try buildCISO(in: fst)

        let target = UInt64(iso.length) + 2 * UInt64(Self.blockSize)
        let dumpConfig = CISODump.Config(
            cisoPath: File("/project/game.ciso"),
            isoPath: File("/project/restored.iso"),
            targetDiscSize: target
        )
        try CISODump.dump(config: dumpConfig, settings: .default, fileSystem: fst, logger: SilentLogger())

        let restored = try XCTUnwrap(fst.readFile(at: File("/project/restored.iso"))?.allData)
        XCTAssertEqual(UInt64(restored.length), target)
        XCTAssertEqual(Array(restored.rawBytes.prefix(iso.length)), iso.rawBytes)
        XCTAssertTrue(restored.rawBytes[iso.length...].allSatisfy { $0 == 0 },
                      "bytes past the block map must be zero-filled")
    }

    func testCisoBuildMissingISOThrows() {
        let config = CISOBuild.Config(
            isoPath: File("/project/missing.iso"),
            cisoPath: File("/project/game.ciso")
        )
        XCTAssertThrowsError(
            try CISOBuild.build(config: config, settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger())
        ) { error in
            guard case CISOErrors.inputNotFound = error else {
                return XCTFail("Expected CISOErrors.inputNotFound, got \(error)")
            }
        }
    }

    func testCisoDumpMissingCISOThrows() {
        let config = CISODump.Config(
            cisoPath: File("/project/missing.ciso"),
            isoPath: File("/project/restored.iso")
        )
        XCTAssertThrowsError(
            try CISODump.dump(config: config, settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger())
        ) { error in
            guard case CISOErrors.inputNotFound = error else {
                return XCTFail("Expected CISOErrors.inputNotFound, got \(error)")
            }
        }
    }

    func testCisoBuildRespectsOverwriteFlag() throws {
        // overwrite=false with an existing output must fail loudly (no
        // success log, no completed status) and leave the existing bytes.
        let fst = InMemoryFST()
        seedISO(in: fst)
        let sentinel = GoDData(byteStream: [0xDE, 0xAD], byteOrder: .big)
        try fst.writeFile(sentinel, at: File("/project/game.ciso"), overwrite: true)

        let config = CISOBuild.Config(
            isoPath: File("/project/game.iso"),
            cisoPath: File("/project/game.ciso"),
            blockSize: Self.blockSize,
            overwrite: false
        )
        let logger = RecordingLogger()
        XCTAssertThrowsError(
            try CISOBuild.build(config: config, settings: .default, fileSystem: fst, logger: logger)
        ) { error in
            // `overwrite: false` against an existing file now reports the
            // specific reason rather than a generic write failure.
            guard case FSTErrors.itemExists = error else {
                return XCTFail("Expected FSTErrors.itemExists, got \(error)")
            }
        }
        XCTAssertFalse(
            logger.entries.contains { if case .info(let message) = $0 { return message.hasPrefix("Shrunk") } else { return false } },
            "Skipped write must not log success"
        )

        let after = try XCTUnwrap(fst.readFile(at: File("/project/game.ciso"))?.allData)
        XCTAssertEqual(after.rawBytes, [0xDE, 0xAD], "overwrite=false must not replace an existing CISO")
    }

    func testCisoDumpRespectsOverwriteFlag() throws {
        let fst = InMemoryFST()
        seedISO(in: fst)
        try buildCISO(in: fst)
        let sentinel = GoDData(byteStream: [0xBE, 0xEF], byteOrder: .big)
        try fst.writeFile(sentinel, at: File("/project/restored.iso"), overwrite: true)

        let config = CISODump.Config(
            cisoPath: File("/project/game.ciso"),
            isoPath: File("/project/restored.iso"),
            overwrite: false
        )
        let logger = RecordingLogger()
        XCTAssertThrowsError(
            try CISODump.dump(config: config, settings: .default, fileSystem: fst, logger: logger)
        ) { error in
            // `overwrite: false` against an existing file now reports the
            // specific reason rather than a generic write failure.
            guard case FSTErrors.itemExists = error else {
                return XCTFail("Expected FSTErrors.itemExists, got \(error)")
            }
        }
        XCTAssertFalse(
            logger.entries.contains { if case .info(let message) = $0 { return message.hasPrefix("Restored") } else { return false } },
            "Skipped write must not log success"
        )

        let after = try XCTUnwrap(fst.readFile(at: File("/project/restored.iso"))?.allData)
        XCTAssertEqual(after.rawBytes, [0xBE, 0xEF], "overwrite=false must not replace an existing ISO")
    }
}
