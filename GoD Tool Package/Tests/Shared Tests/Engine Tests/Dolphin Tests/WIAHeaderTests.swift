import XCTest
import Foundation
import GoDFoundation
import Dolphin

final class WIAHeaderTests: XCTestCase {

    // MARK: - WIAFileHeader

    func testWIAFileHeader_roundtrip() throws {
        let original = WIAFileHeader(
            version: 0x01_00_00_00,
            versionCompatible: 0x01_00_00_00,
            discSize: 0x200,
            discHash: Array(0..<20).map { UInt8($0 &* 7) },
            isoFileSize: 0x1_0000_0000,
            wiaFileSize: 0x8000_0000,
            fileHeadHash: Array(0..<20).map { UInt8($0 &* 11) }
        )
        let bytes = original.binaryData
        let parsed = try WIAFileHeader(binary: bytes)
        XCTAssertEqual(parsed, original)
    }

    func testWIAFileHeader_rejectsBadMagic() {
        let bad = GoDData(byteOrder: .big)
        bad.append(UInt8(0x42)); bad.append(UInt8(0x41)); bad.append(UInt8(0x44)); bad.append(UInt8(0x01))
        for _ in 4..<WIAFileHeader.fixedSize { bad.append(UInt8(0)) }
        XCTAssertThrowsError(try WIAFileHeader(binary: bad))
    }

    func testWIAFileHeader_rejectsShortBuffer() {
        let short = GoDData(byteOrder: .big)
        for _ in 0..<0x20 { short.append(UInt8(0)) }  // < fixedSize
        XCTAssertThrowsError(try WIAFileHeader(binary: short))
    }

    func testWIAFileHeader_exactSize() {
        let h = WIAFileHeader()
        XCTAssertEqual(h.binaryData.length, WIAFileHeader.fixedSize)
    }

    // MARK: - WIADisc

    private func makeDisc(compression: WIADisc.Compression = .lzma, chunkSize: UInt32 = 0x20_0000) -> WIADisc {
        WIADisc(
            discType: .wii,
            compression: compression,
            compressionLevel: 5,
            chunkSize: chunkSize,
            discHeader: Array(0..<WIADisc.discHeaderSize).map { UInt8(truncatingIfNeeded: $0 &* 3) },
            partitionCount: 2,
            partitionStructSize: 0x30,
            partitionTableOffset: 0x100,
            partitionHash: Array(0..<20).map { UInt8($0) },
            rawDataCount: 3,
            rawDataOffset: 0x200,
            rawDataCompressedSize: 0x1000,
            groupCount: 100,
            groupTableOffset: 0x2000,
            groupTableCompressedSize: 0x4000,
            compressionData: [0x5D, 0x00, 0x40, 0x00, 0x00]  // LZMA props + 4 MB dict
        )
    }

    func testWIADisc_roundtrip() throws {
        let original = makeDisc()
        let bytes = original.binaryData
        let parsed = try WIADisc(binary: bytes)
        XCTAssertEqual(parsed, original)
    }

    func testWIADisc_exactSize() {
        XCTAssertEqual(makeDisc().binaryData.length, WIADisc.fixedFieldsSize)
    }

    func testWIADisc_lzmaPropertiesDecoded() {
        // 0x5D = 93. lc = 93 % 9 = 3. pb = (93/9)/5 = 10/5 = 2. lp = (93/9) % 5 = 10 % 5 = 0.
        let d = WIADisc(compression: .lzma, compressionData: [0x5D, 0, 0, 0x40, 0])
        let props = d.lzmaProperties
        XCTAssertNotNil(props)
        XCTAssertEqual(props?.lc, 3)
        XCTAssertEqual(props?.pb, 2)
        XCTAssertEqual(props?.lp, 0)
        // dict size: bytes 1..5 as LE UInt32. [0, 0, 0x40, 0] = 0x00400000 = 4 MiB.
        XCTAssertEqual(d.lzmaDictSize, 0x40_0000)
    }

    func testWIADisc_lzma2DictSize() {
        // prop = 40 → 0xFFFFFFFF (max).
        var d = WIADisc(compression: .lzma2, compressionData: [40])
        XCTAssertEqual(d.lzma2DictSize, 0xFFFF_FFFF)

        // prop = 0 → (2 | 0) << (0/2 + 11) = 2 << 11 = 0x1000.
        d = WIADisc(compression: .lzma2, compressionData: [0])
        XCTAssertEqual(d.lzma2DictSize, 0x1000)

        // prop = 1 → (2 | 1) << (1/2 + 11) = 3 << 11 = 0x1800.
        d = WIADisc(compression: .lzma2, compressionData: [1])
        XCTAssertEqual(d.lzma2DictSize, 0x1800)
    }

    func testWIADisc_compressorSpecificDataUnusedForNone() {
        let d = WIADisc(compression: .none, compressionData: [])
        XCTAssertNil(d.lzmaProperties)
        XCTAssertNil(d.lzma2DictSize)
    }

    // MARK: - RVZ discrimination

    func testWIADisc_zstdFlagsAsRVZ() {
        let d = WIADisc(compression: .zstd, chunkSize: 0x20_0000)
        XCTAssertTrue(d.isRVZ)
    }

    func testWIADisc_smallChunkFlagsAsRVZ() {
        let d = WIADisc(compression: .lzma, chunkSize: 0x8000)
        XCTAssertTrue(d.isRVZ)
    }

    func testWIADisc_lzmaAt2MiBIsWIA() {
        let d = WIADisc(compression: .lzma, chunkSize: 0x20_0000)
        XCTAssertFalse(d.isRVZ)
    }

    func testWIADisc_compressionWhitelists() {
        XCTAssertTrue(WIADisc.Compression.zstd.allowedInRVZ)
        XCTAssertFalse(WIADisc.Compression.zstd.allowedInWIA)
        XCTAssertFalse(WIADisc.Compression.purge.allowedInRVZ)
        XCTAssertTrue(WIADisc.Compression.purge.allowedInWIA)
    }

    // MARK: - Invalid inputs

    func testWIADisc_rejectsInvalidDiscType() {
        let d = makeDisc()
        let bytes = d.binaryData
        // Patch discType to an unknown value at offset 0.
        bytes.setByteOrder(.big)
        _ = bytes.write(UInt32(0xFF), atAddress: 0)
        XCTAssertThrowsError(try WIADisc(binary: bytes))
    }

    func testWIADisc_rejectsInvalidCompression() {
        let d = makeDisc()
        let bytes = d.binaryData
        bytes.setByteOrder(.big)
        _ = bytes.write(UInt32(0xFF), atAddress: 0x04)
        XCTAssertThrowsError(try WIADisc(binary: bytes))
    }
}
