import XCTest
import Foundation
import GoDFoundation
import Dolphin

/// WBFS is a block map over a fixed-size Wii image. The synthetic container
/// here uses the real-world geometry (512-byte hd sectors, 2 MiB blocks) and
/// allocates two disc blocks out of order, so the tests exercise the map
/// rather than an identity mapping. The real-file test at the end skips
/// cleanly without a sample.
final class WBFSFileTests: XCTestCase {

    private static let blockShift = 21
    private static let blockSize = 1 << blockShift
    private static let hdSectorSize = 512

    /// A container holding one disc. `placements` sends disc block → WBFS
    /// block; each stored block is filled with a byte derived from its disc
    /// block index so a read can tell blocks apart.
    private func makeContainer(
        gameID: String = "SOME01",
        placements: [Int: Int] = [0: 1, 3: 2],
        discTableEntry: UInt8 = 1
    ) -> GoDData {
        let blocksPerDisc = WBFSFile.wiiSectorCount >> (Self.blockShift - WBFSFile.wiiSectorSizeShift)
        let containerBlocks = (placements.values.max() ?? 0) + 1
        let size = containerBlocks * Self.blockSize
        let data = GoDData(length: size, byteOrder: .big)

        data.write(GoDData(byteStream: WBFSFile.magic, byteOrder: .big), atAddress: 0)
        data.write(UInt32(size / Self.hdSectorSize).rawData(byteOrder: .big), atAddress: 4)
        _ = data.write(UInt8(9), atAddress: 8)                   // hd sector 512
        _ = data.write(UInt8(Self.blockShift), atAddress: 9)     // 2 MiB blocks
        _ = data.write(discTableEntry, atAddress: WBFSFile.headerSize)

        // Disc 0's record: header copy, then the block map.
        let info = Self.hdSectorSize
        data.write(gameID.data(format: .utf8), atAddress: info)
        data.write(UInt32(0x5D1C9EA3).rawData(byteOrder: .big), atAddress: info + 0x18)
        for (discBlock, wbfsBlock) in placements {
            data.write(UInt16(wbfsBlock).rawData(byteOrder: .big), atAddress: info + 0x100 + discBlock * 2)
            let fill = UInt8(0x10 + discBlock)
            let body = GoDData(byteStream: [UInt8](repeating: fill, count: Self.blockSize), byteOrder: .big)
            data.write(body, atAddress: wbfsBlock * Self.blockSize)
        }
        // The stored disc block 0 carries the disc header itself — that's
        // where the image's own first bytes live. Mirror the record's copy.
        if let block0 = placements[0], let record = data.read(atAddress: info, length: 0x100) {
            data.write(record, atAddress: block0 * Self.blockSize)
        }
        _ = blocksPerDisc
        return data
    }

    // MARK: - Header

    func testParsesGeometryAndDiscTable() throws {
        let wbfs = try WBFSFile(binary: makeContainer())
        XCTAssertEqual(wbfs.hdSectorSize, 512)
        XCTAssertEqual(wbfs.blockSize, 0x20_0000)
        XCTAssertEqual(wbfs.blockCount, 3)
        XCTAssertEqual(wbfs.discSlots, [0])
        XCTAssertEqual(wbfs.blocksPerDisc, 2241, "143432 Wii sectors in 2 MiB blocks, floored")
        XCTAssertEqual(wbfs.discInfoSize, 5120, "0x100 header + 2241 × 2 bytes, rounded up to a 512-byte sector")
    }

    func testRejectsBadMagic() {
        let data = makeContainer()
        _ = data.write(UInt8(0x58), atAddress: 0)
        XCTAssertThrowsError(try WBFSFile(binary: data)) { error in
            guard case WBFSFile.Error.notAWBFS = error else { return XCTFail("got \(error)") }
        }
    }

    func testRejectsImpossibleGeometry() {
        let data = makeContainer()
        _ = data.write(UInt8(5), atAddress: 9)  // 32-byte blocks: not a WBFS
        XCTAssertThrowsError(try WBFSFile(binary: data)) { error in
            guard case WBFSFile.Error.unsupportedGeometry = error else { return XCTFail("got \(error)") }
        }
    }

    func testRejectsAContainerWithNoDiscs() {
        XCTAssertThrowsError(try WBFSFile(binary: makeContainer(discTableEntry: 0))) { error in
            guard case WBFSFile.Error.noDiscs = error else { return XCTFail("got \(error)") }
        }
    }

    func testRejectsABlockPastTheEndOfTheContainer() throws {
        // Disc block 3 claims WBFS block 2, but the file is cut after block 1.
        let full = makeContainer()
        let truncated = try XCTUnwrap(full.read(atAddress: 0, length: 2 * Self.blockSize))
        _ = truncated.write(UInt32(UInt32(truncated.length / Self.hdSectorSize)), atAddress: 4)
        XCTAssertThrowsError(try WBFSFile(binary: truncated).firstDiscImage()) { error in
            guard case WBFSFile.Error.blockOutsideContainer(let block, let discBlock) = error else {
                return XCTFail("got \(error)")
            }
            XCTAssertEqual(block, 2)
            XCTAssertEqual(discBlock, 3)
        }
    }

    // MARK: - Disc image view

    func testDiscImageReadsThroughTheBlockMap() throws {
        let image = try WBFSFile(binary: makeContainer()).firstDiscImage()

        XCTAssertEqual(image.length, WBFSFile.wiiDiscSize, "a WBFS disc is always a full single-layer image")
        XCTAssertEqual(image.allocatedBlockCount, 2)
        XCTAssertEqual(image.readString(atAddress: 0, format: .utf8, maxCharacters: 6), "SOME01")
        let wiiMagic: UInt32 = image.readSafely(atAddress: 0x18)
        XCTAssertEqual(wiiMagic, 0x5D1C9EA3)
        XCTAssertEqual(image.header.rawBytes.prefix(0xEC), image.read(atAddress: 0, length: 0xEC)?.rawBytes[...],
                       "the container's header copy is the image's disc header")

        // Inside disc block 0 (stored at WBFS block 1), past the header.
        XCTAssertEqual(image.read(atAddress: 0x1000, length: 4)?.rawBytes, [0x10, 0x10, 0x10, 0x10])
        // Disc block 3 lives at WBFS block 2 — a non-identity mapping.
        XCTAssertEqual(image.read(atAddress: 3 * Self.blockSize + 0x40, length: 2)?.rawBytes, [0x13, 0x13])
        // Disc blocks 1 and 2 were never allocated: zero.
        XCTAssertEqual(image.read(atAddress: 1 * Self.blockSize + 0x10, length: 4)?.rawBytes, [0, 0, 0, 0])
        // A read spanning the end of block 0 into unallocated block 1.
        let straddle = try XCTUnwrap(image.read(atAddress: Self.blockSize - 2, length: 4)?.rawBytes)
        XCTAssertEqual(straddle, [0x10, 0x10, 0x00, 0x00])
        // The unstored tail past the last whole block is zero, and the
        // image ends exactly at the disc size.
        XCTAssertEqual(image.read(atAddress: image.length - 4, length: 4)?.rawBytes, [0, 0, 0, 0])
        XCTAssertNil(image.read(atAddress: image.length - 2, length: 4), "reads past the disc return nil, like GoDData")
        XCTAssertNil(image.allData, "the view never volunteers a 4.7 GB buffer")
    }

    func testEmptySlotIsAnError() throws {
        XCTAssertThrowsError(try WBFSFile(binary: makeContainer()).discImage(slot: 7)) { error in
            guard case WBFSFile.Error.emptySlot(7) = error else { return XCTFail("got \(error)") }
        }
    }

    // MARK: - Against a real container (if present)

    /// `GODDESS_WBFS_SAMPLE` points at any single-disc `.wbfs`; the default is
    /// the one on this machine.
    func testRealContainerExposesItsDisc() throws {
        let path = ProcessInfo.processInfo.environment["GODDESS_WBFS_SAMPLE"]
            ?? "/Users/stars/Documents/Emulation/Wii/ROMs/Rhythm Heaven Fever [SOME01].wbfs"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("no WBFS sample at \(path)")
        }
        let file = try GoDStreamedData(file: File(nativePath: path))
        XCTAssertEqual(DiscImageFormat.detect(in: file), .wbfs)

        let wbfs = try WBFSFile(binary: file)
        let image = try wbfs.firstDiscImage()
        let gameID = try XCTUnwrap(image.readString(atAddress: 0, format: .utf8, maxCharacters: 6))
        XCTAssertEqual(gameID.count, 6)
        let wiiMagic: UInt32 = image.readSafely(atAddress: 0x18)
        XCTAssertEqual(wiiMagic, 0x5D1C9EA3, "the block map must lead to a Wii disc header")
        // The partition table at 0x40000 names at least one partition.
        let partitionCount: UInt32 = image.readSafely(atAddress: 0x40000)
        XCTAssertGreaterThan(partitionCount, 0)
        XCTAssertGreaterThan(image.allocatedBlockCount, 0)
        // wit stamps an `MD5#` tag over 0xEC–0xFF of the record, so only the
        // disc header proper is expected to match the image.
        XCTAssertEqual(image.header.rawBytes.prefix(0xEC), image.read(atAddress: 0, length: 0xEC)?.rawBytes[...])
    }
}
