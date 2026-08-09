//
//  NintendoArchiveFormatTests.swift
//  NintendoTests
//
//  The magic's direction is the byte-order discriminator, so these pin both
//  halves of that claim: which format the bytes name, and which way round
//  its scalars read.
//

import XCTest
import Foundation
import GoDFoundation
@testable import Nintendo

final class NintendoArchiveFormatTests: XCTestCase {

    private func data(_ bytes: [UInt8]) -> GoDData {
        GoDData(byteStream: bytes, byteOrder: .big)
    }

    // MARK: - Detection

    func testU8ForwardsIsBigEndian() {
        let signature = NintendoArchiveSignature.detect(data([0x55, 0xAA, 0x38, 0x2D]))
        XCTAssertEqual(signature?.format, .u8)
        XCTAssertEqual(signature?.byteOrder, .big)
    }

    func testU8ReversedIsLittleEndian() {
        let signature = NintendoArchiveSignature.detect(data([0x2D, 0x38, 0xAA, 0x55]))
        XCTAssertEqual(signature?.format, .u8)
        XCTAssertEqual(signature?.byteOrder, .little)
    }

    /// `NARC` is the DS spelling, and the DS is little-endian — so unlike
    /// U8, the *forward* spelling here means little.
    func testNARCForwardsIsLittleEndian() {
        let signature = NintendoArchiveSignature.detect(data(Array("NARC".utf8)))
        XCTAssertEqual(signature?.format, .narc)
        XCTAssertEqual(signature?.byteOrder, .little)
    }

    /// `CRAN` is what Battle Revolution's big-endian port writes.
    func testNARCReversedIsBigEndian() {
        let signature = NintendoArchiveSignature.detect(data(Array("CRAN".utf8)))
        XCTAssertEqual(signature?.format, .narc)
        XCTAssertEqual(signature?.byteOrder, .big)
    }

    func testUnknownMagicIsNotDetected() {
        XCTAssertNil(NintendoArchiveSignature.detect(data(Array("YAZ0".utf8))))
        XCTAssertNil(NintendoArchiveSignature.detect(data([0x00, 0x00, 0x00, 0x00])))
    }

    func testTooShortIsNotDetected() {
        XCTAssertNil(NintendoArchiveSignature.detect(data([0x55, 0xAA, 0x38])))
        XCTAssertNil(NintendoArchiveSignature.detect(data([])))
    }

    // MARK: - Round trip through the signature

    func testSignatureRoundTripsItsOwnMagic() {
        for format in NintendoArchiveFormat.allCases {
            for byteOrder in [ByteOrder.big, .little] {
                let signature = NintendoArchiveSignature(format: format, byteOrder: byteOrder)
                XCTAssertEqual(
                    NintendoArchiveSignature.detect(magic: signature.magic), signature,
                    "\(signature.description) did not survive a round trip through its magic"
                )
            }
        }
    }

    func testNativeSpellingIsUsedForTheNativeByteOrder() {
        for format in NintendoArchiveFormat.allCases {
            let native = NintendoArchiveSignature(format: format, byteOrder: format.nativeByteOrder)
            XCTAssertEqual(native.magic, format.nativeMagic)
            let ported = NintendoArchiveSignature(format: format, byteOrder: format.nativeByteOrder.swapped)
            XCTAssertEqual(ported.magic, format.reversedMagic)
        }
    }

    func testFileExtensions() {
        XCTAssertEqual(NintendoArchiveFormat.u8.fileExtension, "arc")
        XCTAssertEqual(NintendoArchiveFormat.narc.fileExtension, "narc")
    }

    // MARK: - Primitives

    func testReaderRespectsByteOrder() throws {
        let bytes: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        let big = ArchiveReader(bytes: bytes, byteOrder: .big, format: "test")
        let little = ArchiveReader(bytes: bytes, byteOrder: .little, format: "test")
        XCTAssertEqual(try big.u32(0), 0x1234_5678)
        XCTAssertEqual(try little.u32(0), 0x7856_3412)
        XCTAssertEqual(try big.u16(0), 0x1234)
        XCTAssertEqual(try little.u16(0), 0x3412)
    }

    func testReaderThrowsPastTheEnd() {
        let reader = ArchiveReader(bytes: [0x00, 0x01], byteOrder: .big, format: "test")
        XCTAssertThrowsError(try reader.u32(0)) { error in
            guard case NintendoArchiveError.truncated = error else {
                return XCTFail("expected truncated, got \(error)")
            }
        }
    }

    func testWriterRespectsByteOrder() {
        var big = ArchiveWriter(byteOrder: .big)
        big.append(u32: 0x1234_5678)
        XCTAssertEqual(big.bytes, [0x12, 0x34, 0x56, 0x78])

        var little = ArchiveWriter(byteOrder: .little)
        little.append(u32: 0x1234_5678)
        XCTAssertEqual(little.bytes, [0x78, 0x56, 0x34, 0x12])
    }

    /// A magic is raw bytes, not a scalar — it must be written in the order
    /// given regardless of the archive's byte order, or the discriminator
    /// would flip itself.
    func testWriterLeavesRawBytesAlone() {
        var writer = ArchiveWriter(byteOrder: .little)
        writer.append(raw: [0x55, 0xAA, 0x38, 0x2D])
        XCTAssertEqual(writer.bytes, [0x55, 0xAA, 0x38, 0x2D])
    }

    func testErrorDescriptionsAreNonEmpty() {
        let errors: [NintendoArchiveError] = [
            .unrecognizedMagic(found: [1, 2, 3, 4]),
            .wrongFormat(expected: .u8, found: .narc),
            .truncated(format: "U8", needed: 10, available: 4),
            .malformed(format: "NARC", reason: "test"),
        ]
        for error in errors {
            XCTAssertFalse(error.description.isEmpty)
        }
    }
}
