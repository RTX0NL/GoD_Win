//
//  RVZOperationTests.swift
//
//  Body tests for `rvzDump`: the operation run against an `InMemoryFST`
//  with an image built by `RVZFixtures`, asserting the restored bytes rather
//  than just that it didn't throw.
//
//  Kept to GameCube images with a small partition-free layout, because what
//  this layer owns is reading the input, calling the restore and writing the
//  output. `RVZImageTests` covers the container and `RVZWiiRestoreTests` the
//  Wii crypto.
//

import XCTest
import GoDFoundation
import Dolphin
import FixtureCatalog
@testable import GODOps

final class RVZOperationTests: XCTestCase {

    private func discHeader() -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 0x80)
        for (i, byte) in Array("GTST01".utf8).enumerated() { header[i] = byte }
        header[0x1C] = 0xC2; header[0x1D] = 0x33; header[0x1E] = 0x9F; header[0x1F] = 0x3D
        return header
    }

    private func pattern(_ count: Int) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(count)
        var state: UInt32 = 0x1234_5678
        for _ in 0..<count {
            state = state &* 1664525 &+ 1013904223
            out.append(UInt8(truncatingIfNeeded: state >> 16))
        }
        return out
    }

    private func gameCubeImage(compressed: Bool) -> (file: GoDData, iso: [UInt8]) {
        let head = discHeader()
        let body = pattern(0x18000)
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x8000
        spec.discHeader = head
        spec.isoSize = UInt64(0x80 + body.count)
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: body)]
        if compressed {
            spec.compression = .zstd
            spec.encoding = .zstdRawFrame
        }
        return (RVZFixtures.build(spec), head + body)
    }

    func testDumpsAnRVZToItsISO() throws {
        let fst = InMemoryFST()
        let (file, expected) = gameCubeImage(compressed: true)
        try fst.writeFile(file, at: File("/in/game.rvz"), overwrite: true)

        try RVZDump.dump(
            config: .init(rvzPath: File("/in/game.rvz"), isoPath: File("/out/game.iso")),
            settings: GoddessSettings(),
            fileSystem: fst
        )

        let written = try XCTUnwrap(fst.readFile(at: File("/out/game.iso"))?.allData)
        XCTAssertEqual(written.length, expected.count)
        XCTAssertEqual(written.rawBytes, expected)
    }

    func testDumpsAnUncompressedWIAToItsISO() throws {
        let fst = InMemoryFST()
        let (file, expected) = gameCubeImage(compressed: false)
        try fst.writeFile(file, at: File("/in/game.wia"), overwrite: true)

        try RVZDump.dump(
            config: .init(rvzPath: File("/in/game.wia"), isoPath: File("/out/game.iso")),
            settings: GoddessSettings(),
            fileSystem: fst
        )
        XCTAssertEqual(try XCTUnwrap(fst.readFile(at: File("/out/game.iso"))?.allData).rawBytes, expected)
    }

    func testReportsAMissingInputByPath() throws {
        let fst = InMemoryFST()
        XCTAssertThrowsError(try RVZDump.dump(
            config: .init(rvzPath: File("/in/absent.rvz"), isoPath: File("/out/game.iso")),
            settings: GoddessSettings(),
            fileSystem: fst
        )) { error in
            XCTAssertTrue("\(error)".contains("absent.rvz"), "\(error)")
        }
    }

    /// `overwrite: false` must not quietly replace an existing ISO.
    func testHonoursTheOverwriteFlag() throws {
        let fst = InMemoryFST()
        let (file, _) = gameCubeImage(compressed: false)
        try fst.writeFile(file, at: File("/in/game.rvz"), overwrite: true)
        let existing = GoDData(byteStream: [0xDE, 0xAD], byteOrder: .big)
        try fst.writeFile(existing, at: File("/out/game.iso"), overwrite: true)

        XCTAssertThrowsError(try RVZDump.dump(
            config: .init(rvzPath: File("/in/game.rvz"), isoPath: File("/out/game.iso"), overwrite: false),
            settings: GoddessSettings(),
            fileSystem: fst
        ))
        XCTAssertEqual(try XCTUnwrap(fst.readFile(at: File("/out/game.iso"))?.allData).rawBytes, [0xDE, 0xAD])
    }

    /// A Wii image reaches the real `WiiRVZPartitionRestorer` through the
    /// operation, so the wiring that supplies it is covered too.
    func testDumpsAWiiImageThroughTheOperation() throws {
        let fst = InMemoryFST()
        let sectors = 64
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x2_0000
        spec.discType = .wii
        spec.elideZeroGroups = false
        var header = [UInt8](repeating: 0, count: 0x80)
        for (i, b) in Array("RTSTE0".utf8).enumerated() { header[i] = b }
        header[0x18] = 0x5D; header[0x19] = 0x1C; header[0x1A] = 0x9E; header[0x1B] = 0xA3
        spec.discHeader = header
        let firstSector: UInt32 = 0x100
        spec.isoSize = UInt64((Int(firstSector) + sectors) * 0x8000)
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: pattern(0x8000))]
        spec.partitions = [
            RVZFixtures.Partition(
                titleKey: (0..<16).map { UInt8($0) },
                firstSector: firstSector,
                managementSectors: UInt32(sectors),
                dataSectors: 0,
                decryptedData: pattern(sectors * 0x7C00)
            ),
        ]
        try fst.writeFile(RVZFixtures.build(spec), at: File("/in/game.rvz"), overwrite: true)

        try RVZDump.dump(
            config: .init(rvzPath: File("/in/game.rvz"), isoPath: File("/out/game.iso")),
            settings: GoddessSettings(),
            fileSystem: fst
        )
        let written = try XCTUnwrap(fst.readFile(at: File("/out/game.iso"))?.allData)
        XCTAssertEqual(written.length, Int(spec.isoSize))
        // The partition's clusters are encrypted, so the one thing that must
        // be plainly true is that they are not the payload verbatim.
        let partitionStart = UInt(firstSector) * 0x8000
        let firstCluster = try XCTUnwrap(written.read(atAddress: partitionStart, length: 0x20))
        XCTAssertNotEqual(firstCluster.rawBytes, Array(spec.partitions[0].decryptedData[0..<0x20]))
        XCTAssertFalse(firstCluster.rawBytes.allSatisfy { $0 == 0 }, "the partition should not be blank")
    }
}
