import XCTest
import Foundation
import GoDFoundation
import Dolphin

final class WIAPartitionTests: XCTestCase {

    // MARK: - Segment

    func testSegment_roundtrip() throws {
        let seg = WIAPartitionSegment(firstSector: 0x10, sectorCount: 0x2000,
                                      firstGroupIndex: 5, groupCount: 20)
        let buf = GoDData(byteOrder: .big)
        for _ in 0..<WIAPartitionSegment.byteSize { buf.append(UInt8(0)) }
        seg.write(into: buf, at: 0)
        let parsed = try WIAPartitionSegment(binary: buf, at: 0)
        XCTAssertEqual(parsed, seg)
    }

    // MARK: - WIAPartition

    func testPartition_roundtrip() throws {
        let key: [UInt8] = (0..<16).map { UInt8($0 * 17) }
        let p = WIAPartition(
            titleKey: key,
            managementSegment: WIAPartitionSegment(firstSector: 0, sectorCount: 4,
                                                   firstGroupIndex: 0, groupCount: 1),
            dataSegment: WIAPartitionSegment(firstSector: 4, sectorCount: 0x20000,
                                             firstGroupIndex: 1, groupCount: 100)
        )
        let buf = GoDData(byteOrder: .big)
        for _ in 0..<WIAPartition.byteSize { buf.append(UInt8(0)) }
        p.write(into: buf, at: 0)
        let parsed = try WIAPartition(binary: buf, at: 0)
        XCTAssertEqual(parsed, p)
    }

    func testPartition_sizeIs48() {
        XCTAssertEqual(WIAPartition.byteSize, 48)
    }

    // MARK: - WIARawData

    func testRawData_roundtrip() throws {
        let r = WIARawData(discOffset: 0x1_0000_0000, size: 0x0200_0000,
                           firstGroupIndex: 5, groupCount: 16)
        let buf = GoDData(byteOrder: .big)
        for _ in 0..<WIARawData.byteSize { buf.append(UInt8(0)) }
        r.write(into: buf, at: 0)
        let parsed = try WIARawData(binary: buf, at: 0)
        XCTAssertEqual(parsed, r)
    }

    // MARK: - WIAGroupEntry (WIA variant)

    func testGroup_wiaRoundtrip() throws {
        let g = WIAGroupEntry.wia(dataOffsetDiv4: 0x100, dataSize: 0x1234)
        let buf = GoDData(byteOrder: .big)
        for _ in 0..<WIAGroupEntry.wiaByteSize { buf.append(UInt8(0)) }
        g.write(into: buf, at: 0)
        let parsed = try WIAGroupEntry(wiaBinary: buf, at: 0)
        XCTAssertEqual(parsed, g)
        XCTAssertEqual(parsed.dataOffset, 0x400)
        XCTAssertEqual(parsed.dataSize, 0x1234)
    }

    func testGroup_wiaAllZerosFlag() throws {
        let g = WIAGroupEntry.wia(dataOffsetDiv4: 0, dataSize: 0)
        XCTAssertTrue(g.isAllZeros)
    }

    // MARK: - WIAGroupEntry (RVZ variant)

    func testGroup_rvzRoundtripCompressed() throws {
        let g = WIAGroupEntry.rvz(
            dataOffsetDiv4: 0x200, dataSize: 0x4000,
            isCompressed: true, rvzPackedSize: 0x2000
        )
        let buf = GoDData(byteOrder: .big)
        for _ in 0..<WIAGroupEntry.rvzByteSize { buf.append(UInt8(0)) }
        g.write(into: buf, at: 0)
        let parsed = try WIAGroupEntry(rvzBinary: buf, at: 0)
        XCTAssertEqual(parsed, g)
    }

    func testGroup_rvzRoundtripUncompressed() throws {
        let g = WIAGroupEntry.rvz(
            dataOffsetDiv4: 0x400, dataSize: 0x1000,
            isCompressed: false, rvzPackedSize: 0
        )
        let buf = GoDData(byteOrder: .big)
        for _ in 0..<WIAGroupEntry.rvzByteSize { buf.append(UInt8(0)) }
        g.write(into: buf, at: 0)
        let parsed = try WIAGroupEntry(rvzBinary: buf, at: 0)
        XCTAssertEqual(parsed, g)
    }

    func testGroup_rvzCompressedBitSemantics() {
        // Top bit of the size_flag word signals "data is compressed".
        let buf = GoDData(byteOrder: .big)
        for _ in 0..<WIAGroupEntry.rvzByteSize { buf.append(UInt8(0)) }
        // data_off4 = 0, size_flag = 0x80001000 (compressed, size 0x1000)
        _ = buf.write(UInt32(0), atAddress: 0)
        _ = buf.write(UInt32(0x8000_1000), atAddress: 4)
        _ = buf.write(UInt32(0), atAddress: 8)
        let g = try! WIAGroupEntry(rvzBinary: buf, at: 0)
        XCTAssertEqual(g.dataSize, 0x1000)
        guard case .rvz(_, _, let compressed, _) = g else { return XCTFail() }
        XCTAssertTrue(compressed)
    }

    // MARK: - Exception list

    func testExceptionList_emptyRoundtrip() throws {
        let list = WIAExceptionList(exceptions: [])
        let bytes = list.encode()
        XCTAssertEqual(bytes, [0, 0])
        let data = GoDData(byteStream: bytes, byteOrder: .big)
        let (parsed, consumed) = try WIAExceptionList.decode(from: data, at: 0)
        XCTAssertEqual(parsed, list)
        XCTAssertEqual(consumed, 2)
    }

    func testExceptionList_multipleEntries() throws {
        let exceptions: [WIAExceptionList.Exception] = [
            .init(offset: 0x0010, hash: Array(0..<20).map { UInt8($0) }),
            .init(offset: 0x00A0, hash: Array(0..<20).map { UInt8($0 &+ 100) }),
            .init(offset: 0xFFFF, hash: [UInt8](repeating: 0xAB, count: 20)),
        ]
        let list = WIAExceptionList(exceptions: exceptions)
        let bytes = list.encode()
        let data = GoDData(byteStream: bytes, byteOrder: .big)
        let (parsed, consumed) = try WIAExceptionList.decode(from: data, at: 0)
        XCTAssertEqual(parsed, list)
        XCTAssertEqual(consumed, bytes.count)
    }

    func testExceptionList_rejectsTruncated() {
        // Claims 2 exceptions but buffer only has room for 1 prefix + 1.5 exceptions.
        let bytes: [UInt8] = [0x00, 0x02] + Array(repeating: 0 as UInt8, count: 30)
        let data = GoDData(byteStream: bytes, byteOrder: .big)
        XCTAssertThrowsError(try WIAExceptionList.decode(from: data, at: 0))
    }
}
