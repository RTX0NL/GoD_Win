//
//  RVZImageTests.swift
//
//  Container-level tests for the WIA/RVZ reader, over images built by
//  `RVZFixtures` — a hand-rolled encoder that writes raw fields at canonical
//  offsets, so these check the reader against the format rather than against
//  a writer that shares its assumptions.
//
//  The Wii half of a restore is stubbed here by a recording
//  `WiiPartitionRestorer`: this target has no Wii dependency, and what it
//  needs to assert is that the right payload and the right exceptions reach
//  that boundary. `RVZWiiRestoreTests` covers what happens past it.
//

import XCTest
import GoDFoundation
import FixtureCatalog
@testable import Dolphin

final class RVZImageTests: XCTestCase {

    // MARK: - Helpers

    private func discHeader(gameID: String = "GTST01") -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 0x80)
        for (i, byte) in Array(gameID.utf8).enumerated() where i < 6 { header[i] = byte }
        header[0x1C] = 0xC2; header[0x1D] = 0x33; header[0x1E] = 0x9F; header[0x1F] = 0x3D
        return header
    }

    /// Deterministic filler that is not all one byte, so a group that is
    /// wrongly zero-filled or mis-offset is visible.
    private func pattern(_ count: Int, seed: UInt8 = 1) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(count)
        var state = UInt32(seed) &* 2654435761 &+ 1
        for _ in 0..<count {
            state = state &* 1664525 &+ 1013904223
            out.append(UInt8(truncatingIfNeeded: state >> 16))
        }
        return out
    }

    /// Stands in for the Wii layer with a pure function of its input.
    ///
    /// `RecordingRestorer` stamps its call index into the output, which makes
    /// it useless for comparing two code paths: the buffer restore and the
    /// lazy view ask for groups in different orders, so the same group would
    /// come back with different bytes. This one derives every byte from the
    /// payload, so only a real disagreement shows up.
    private final class DeterministicRestorer: WiiPartitionRestorer {
        func encryptGroup(
            decryptedUserData: [UInt8],
            titleKey: [UInt8],
            hashExceptions: [WIAExceptionList.Exception]
        ) throws -> [UInt8] {
            var out = [UInt8](repeating: 0, count: 64 * RVZFixtures.clusterSize)
            // Cluster c's output carries its own payload plus a byte derived
            // from the key and any exception, so a misplaced group, a wrong
            // key or a dropped exception all change the bytes.
            for cluster in 0..<64 {
                let source = cluster * RVZFixtures.userDataPerCluster
                let destination = cluster * RVZFixtures.clusterSize
                out[destination] = UInt8(truncatingIfNeeded: hashExceptions.count)
                out[destination + 1] = titleKey.first ?? 0
                for i in 0..<RVZFixtures.userDataPerCluster {
                    out[destination + 0x400 + i] = decryptedUserData[source + i]
                }
            }
            return out
        }
    }

    /// Records what the container hands the Wii layer, and returns a
    /// recognizable stand-in so the placement can be checked too.
    private final class RecordingRestorer: WiiPartitionRestorer {
        struct Call {
            var userData: [UInt8]
            var titleKey: [UInt8]
            var exceptions: [WIAExceptionList.Exception]
        }
        var calls: [Call] = []
        var marker: UInt8 = 0xAB

        func encryptGroup(
            decryptedUserData: [UInt8],
            titleKey: [UInt8],
            hashExceptions: [WIAExceptionList.Exception]
        ) throws -> [UInt8] {
            calls.append(Call(userData: decryptedUserData, titleKey: titleKey, exceptions: hashExceptions))
            var out = [UInt8](repeating: marker, count: 64 * RVZFixtures.clusterSize)
            // Stamp the call index so a misplaced group is identifiable.
            out[0] = UInt8(truncatingIfNeeded: calls.count - 1)
            return out
        }
    }

    // MARK: - GameCube images

    func testRestoresAnUncompressedGameCubeImage() throws {
        let head = discHeader()
        let body = pattern(0x18000)
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x8000
        spec.discType = .gamecube
        spec.discHeader = head
        spec.isoSize = UInt64(0x80 + body.count)
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: body)]

        let image = try RVZImage(binary: RVZFixtures.build(spec))
        XCTAssertTrue(image.isRVZ)
        XCTAssertEqual(image.disc.discType, .gamecube)
        XCTAssertTrue(image.partitions.isEmpty)

        let iso = try image.restoreISO()
        XCTAssertEqual(iso.length, 0x80 + body.count)
        XCTAssertEqual(iso.read(atAddress: 0, length: 0x80)?.rawBytes, head)
        XCTAssertEqual(iso.read(atAddress: 0x80, length: UInt(body.count))?.rawBytes, body)
    }

    /// The same image with every group's payload wrapped in a Zstandard
    /// frame, so the container's decompression step is exercised on bytes
    /// this test wrote rather than only on real files.
    func testRestoresAZstandardCompressedGameCubeImage() throws {
        let head = discHeader()
        let body = pattern(0x14000, seed: 9)
        var spec = RVZFixtures.Image()
        spec.compression = .zstd
        spec.encoding = .zstdRawFrame
        spec.chunkSize = 0x8000
        spec.discHeader = head
        spec.isoSize = UInt64(0x80 + body.count)
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: body)]

        let iso = try RVZImage(binary: RVZFixtures.build(spec)).restoreISO()
        XCTAssertEqual(iso.read(atAddress: 0x80, length: UInt(body.count))?.rawBytes, body)
    }

    /// A raw-data entry whose stored offset is not cluster-aligned covers
    /// more bytes than it declares: the offset rounds down and the size
    /// grows to match. Every real image's first entry is this shape — it
    /// claims 0x80..0x50000 and actually holds 0..0x50000.
    func testRoundsARawEntryDownToItsClusterBoundary() throws {
        let head = discHeader()
        let body = pattern(0x8000)
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x8000
        spec.discHeader = head
        spec.isoSize = UInt64(0x80 + body.count)
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: body)]

        let image = try RVZImage(binary: RVZFixtures.build(spec))
        // Two groups, because the rounding pushes the span past one chunk.
        XCTAssertEqual(image.rawData.count, 1)
        XCTAssertEqual(image.rawData[0].groupCount, 2)
        let iso = try image.restoreISO()
        XCTAssertEqual(iso.read(atAddress: 0x80, length: UInt(body.count))?.rawBytes, body)
    }

    /// A group with a stored size of 0 means "all zeroes" and is never read.
    func testAllZeroGroupsExpandWithoutReadingAnything() throws {
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x8000
        spec.discHeader = discHeader()
        spec.isoSize = 0x10080
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: [UInt8](repeating: 0, count: 0x10000))]

        let image = try RVZImage(binary: RVZFixtures.build(spec))
        XCTAssertTrue(image.groups.allSatisfy(\.isAllZeros), "every group should have been elided")
        let iso = try image.restoreISO()
        XCTAssertEqual(iso.length, 0x10080)
        XCTAssertEqual(iso.read(atAddress: 0x1000, length: 0x100)?.rawBytes, [UInt8](repeating: 0, count: 0x100))
    }

    // MARK: - Header validation

    func testRejectsAnImageWhoseFileHeadHashDoesNotMatch() throws {
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x8000
        spec.discHeader = discHeader()
        spec.isoSize = 0x8080
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: pattern(0x8000))]
        let file = RVZFixtures.build(spec)
        // Flip a byte inside the range the head hash covers.
        file.write(GoDData(byteStream: [0xFF], byteOrder: .big), atAddress: 0x04)

        XCTAssertThrowsError(try RVZImage(binary: file)) { error in
            guard case RVZError.headerHashMismatch(let field) = error else {
                return XCTFail("expected a header hash mismatch, got \(error)")
            }
            XCTAssertEqual(field, "file_head_hash")
        }
    }

    func testRejectsAnImageWhoseDiscHashDoesNotMatch() throws {
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x8000
        spec.discHeader = discHeader()
        spec.isoSize = 0x8080
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: pattern(0x8000))]
        let file = RVZFixtures.build(spec)
        // A byte inside the disc struct's `dhead` copy.
        file.write(GoDData(byteStream: [0xFF], byteOrder: .big), atAddress: UInt(WIAFileHeader.fixedSize + 0x20))

        XCTAssertThrowsError(try RVZImage(binary: file)) { error in
            guard case RVZError.headerHashMismatch(let field) = error else {
                return XCTFail("expected a header hash mismatch, got \(error)")
            }
            XCTAssertEqual(field, "disc_hash")
        }
    }

    func testRejectsBadMagic() throws {
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x8000
        spec.discHeader = discHeader()
        spec.isoSize = 0x8080
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: pattern(0x8000))]
        let file = RVZFixtures.build(spec)
        file.write(GoDData(byteStream: [0x4E, 0x4B, 0x49, 0x54], byteOrder: .big), atAddress: 0)
        XCTAssertThrowsError(try RVZImage(binary: file))
    }

    /// WIA and RVZ differ in the width of a group-table entry, and the magic
    /// is what says which. `WIADisc.isRVZ` guesses from the compression and
    /// chunk size instead, and a WIA with a 2 MiB chunk and no compression
    /// is exactly where that guess and the truth could part company.
    func testUsesTheMagicRatherThanAHeuristicToPickTheGroupStride() throws {
        let body = pattern(0x8000)
        var spec = RVZFixtures.Image()
        spec.isRVZ = false
        spec.chunkSize = 0x20_0000
        spec.discHeader = discHeader()
        spec.isoSize = UInt64(0x80 + body.count)
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: body)]

        let image = try RVZImage(binary: RVZFixtures.build(spec))
        XCTAssertFalse(image.isRVZ)
        XCTAssertFalse(image.disc.isRVZ, "the heuristic should agree here, or the test proves nothing")
        let iso = try image.restoreISO()
        XCTAssertEqual(iso.read(atAddress: 0x80, length: UInt(body.count))?.rawBytes, body)
    }

    func testRejectsCompressionItCannotDecode() throws {
        var spec = RVZFixtures.Image()
        spec.compression = .lzma
        spec.chunkSize = 0x8000
        spec.discHeader = discHeader()
        spec.isoSize = 0x8080
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: pattern(0x8000))]

        XCTAssertThrowsError(try RVZImage(binary: RVZFixtures.build(spec))) { error in
            guard case RVZError.unsupportedCompression(let name) = error else {
                return XCTFail("expected an unsupported-compression error, got \(error)")
            }
            XCTAssertTrue(name.contains("LZMA"), name)
        }
    }

    // MARK: - Wii partitions

    func testRefusesAWiiImageWithoutAPartitionRestorer() throws {
        let spec = wiiSpec(sectors: 64)
        let image = try RVZImage(binary: RVZFixtures.build(spec))
        XCTAssertThrowsError(try image.restoreISO(partitionRestorer: nil)) { error in
            guard case RVZError.missingPartitionRestorer = error else {
                return XCTFail("expected a missing-restorer error, got \(error)")
            }
        }
    }

    func testHandsEachPartitionGroupToTheRestorerIntact() throws {
        let spec = wiiSpec(sectors: 64)
        let expected = spec.partitions[0].decryptedData
        let restorer = RecordingRestorer()
        let iso = try RVZImage(binary: RVZFixtures.build(spec)).restoreISO(partitionRestorer: restorer)

        XCTAssertEqual(restorer.calls.count, 1)
        XCTAssertEqual(restorer.calls[0].userData, expected)
        XCTAssertEqual(restorer.calls[0].titleKey, spec.partitions[0].titleKey)
        // The stand-in's bytes must land at the partition's disc offset.
        let discOffset = UInt(spec.partitions[0].firstSector) * UInt(RVZFixtures.clusterSize)
        XCTAssertEqual(iso.read(atAddress: discOffset + 1, length: 1)?.rawBytes, [restorer.marker])
    }

    /// A partition that stops partway through a 64-cluster group still gets
    /// a full group of data to hash — the absent clusters count as zeroes,
    /// because their hashes appear in the hash blocks of the ones present.
    func testZeroPadsAShortFinalGroupButWritesOnlyItsRealSectors() throws {
        let sectors = 70  // one full group plus six clusters
        let spec = wiiSpec(sectors: sectors)
        let restorer = RecordingRestorer()
        let iso = try RVZImage(binary: RVZFixtures.build(spec)).restoreISO(partitionRestorer: restorer)

        XCTAssertEqual(restorer.calls.count, 2)
        XCTAssertEqual(restorer.calls[1].userData.count, 64 * RVZFixtures.userDataPerCluster)
        let realBytes = (sectors - 64) * RVZFixtures.userDataPerCluster
        XCTAssertEqual(
            Array(restorer.calls[1].userData.suffix(64 * RVZFixtures.userDataPerCluster - realBytes)),
            [UInt8](repeating: 0, count: 64 * RVZFixtures.userDataPerCluster - realBytes)
        )
        // Only the six real clusters are written; the disc ends there.
        let discOffset = Int(spec.partitions[0].firstSector) * RVZFixtures.clusterSize
        let end = discOffset + sectors * RVZFixtures.clusterSize
        XCTAssertEqual(iso.read(atAddress: UInt(end - 1), length: 1)?.rawBytes, [restorer.marker])
    }

    /// A chunk below 2 MiB carries one exception list whose offsets start at
    /// that chunk, so they shift by where the chunk sits inside its 2 MiB
    /// group. Getting the shift wrong patches the wrong cluster's hashes.
    ///
    /// Uses a 0x20000 chunk — four clusters of disc space, so 0x1F000 of
    /// data space — because at the 0x8000 minimum a chunk is one cluster and
    /// the shift would be indistinguishable from the chunk index.
    func testShiftsExceptionOffsetsByTheChunksPlaceInItsGroup() throws {
        var spec = wiiSpec(sectors: 64, chunkSize: 0x2_0000)
        // Chunk 3 starts at cluster 12 of the group, so its offsets shift by
        // 12 * 0x400 = 0x3000.
        let hash = [UInt8](repeating: 0x5E, count: 20)
        spec.partitions[0].exceptionsByChunk = [
            3: [WIAExceptionList.Exception(offset: 0x0040, hash: hash)],
        ]
        let restorer = RecordingRestorer()
        _ = try RVZImage(binary: RVZFixtures.build(spec)).restoreISO(partitionRestorer: restorer)

        XCTAssertEqual(restorer.calls.count, 1)
        XCTAssertEqual(restorer.calls[0].exceptions.count, 1)
        XCTAssertEqual(restorer.calls[0].exceptions.first?.offset, 0x3040)
        XCTAssertEqual(restorer.calls[0].exceptions.first?.hash, hash)
    }

    /// At the 0x8000 minimum a chunk is exactly one cluster, so chunk N's
    /// exceptions shift by N hash blocks.
    func testShiftsExceptionOffsetsAtTheSmallestChunkSize() throws {
        var spec = wiiSpec(sectors: 64)
        let hash = [UInt8](repeating: 0x77, count: 20)
        spec.partitions[0].exceptionsByChunk = [
            3: [WIAExceptionList.Exception(offset: 0x0040, hash: hash)],
        ]
        let restorer = RecordingRestorer()
        _ = try RVZImage(binary: RVZFixtures.build(spec)).restoreISO(partitionRestorer: restorer)
        XCTAssertEqual(restorer.calls[0].exceptions.first?.offset, 0x0C40)
    }

    func testCarriesExceptionsThroughACompressedPayload() throws {
        var spec = wiiSpec(sectors: 64)
        spec.compression = .zstd
        spec.encoding = .zstdRawFrame
        let hash = [UInt8](repeating: 0x11, count: 20)
        spec.partitions[0].exceptionsByChunk = [0: [WIAExceptionList.Exception(offset: 0x0000, hash: hash)]]
        let restorer = RecordingRestorer()
        _ = try RVZImage(binary: RVZFixtures.build(spec)).restoreISO(partitionRestorer: restorer)
        XCTAssertEqual(restorer.calls[0].exceptions.first?.hash, hash)
        XCTAssertEqual(restorer.calls[0].userData, spec.partitions[0].decryptedData)
    }

    private func wiiSpec(
        sectors: Int,
        chunkSize: UInt32 = 0x8000,
        firstSector: UInt32 = 0x1F04
    ) -> RVZFixtures.Image {
        var spec = RVZFixtures.Image()
        spec.chunkSize = chunkSize
        spec.discType = .wii
        spec.discHeader = discHeader(gameID: "RTSTE0")
        spec.elideZeroGroups = false
        spec.isoSize = UInt64(Int(firstSector) * RVZFixtures.clusterSize + sectors * RVZFixtures.clusterSize)
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: pattern(0x8000, seed: 3))]
        spec.partitions = [
            RVZFixtures.Partition(
                titleKey: (0..<16).map { UInt8($0 &* 7 &+ 1) },
                firstSector: firstSector,
                managementSectors: UInt32(sectors),
                dataSectors: 0,
                decryptedData: pattern(sectors * RVZFixtures.userDataPerCluster, seed: 5)
            ),
        ]
        return spec
    }
}

// MARK: - Lazy view

/// The lazy view and the buffer-building restore must produce the same bytes.
///
/// They share `RVZImage.block(containingDiscOffset:)`, so this is less about
/// the decode than about the addressing around it: where a block starts, what
/// happens on a region boundary, and the two places the buffer path used to
/// do something the view has to reproduce — zero-filling ranges no region
/// covers, and overwriting the first 0x80 bytes with the disc header.
extension RVZImageTests {

    private func viewBytes(_ view: RVZDiscImageView, window: Int) -> [UInt8] {
        var out = [UInt8]()
        var offset = 0
        while offset < view.length {
            let count = min(window, view.length - offset)
            guard let chunk = view.read(atAddress: offset, length: count) else {
                XCTFail("view returned nil at \(offset)+\(count)")
                return out
            }
            out.append(contentsOf: chunk.rawBytes)
            offset += count
        }
        return out
    }

    /// Read the same disc several ways: one whole-disc read, the 8 MB windows
    /// `FileHandleAccess.write` uses, and windows that are deliberately not a
    /// multiple of any block size.
    private func assertViewMatchesBuffer(
        _ spec: RVZFixtures.Image,
        restorer: WiiPartitionRestorer? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let image = try RVZImage(binary: RVZFixtures.build(spec))
        let expected = try image.restoreISO(partitionRestorer: restorer).rawBytes
        // 8 MB is the window `FileHandleAccess.write` uses; the rest are
        // deliberately not multiples of any block size. The small ones are
        // only worth running on a small image — over a multi-megabyte disc
        // they are millions of reads that say nothing the others don't.
        var windows = [expected.count, 8 << 20, 0x8000, 0x1F000]
        if expected.count <= 1 << 20 { windows += [1000, 7] }
        for window in windows {
            let view = try image.discImageView(partitionRestorer: restorer)
            let actual = viewBytes(view, window: window)
            // Reported as a first-difference offset rather than by handing two
            // multi-megabyte arrays to XCTAssertEqual, which prints both.
            XCTAssertEqual(
                actual.count, expected.count,
                "window \(window): length differs", file: file, line: line
            )
            if let offset = (0..<min(actual.count, expected.count)).first(where: { actual[$0] != expected[$0] }) {
                XCTFail(
                    String(
                        format: "window %d: first difference at 0x%X — view 0x%02X, buffer 0x%02X",
                        window, offset, actual[offset], expected[offset]
                    ),
                    file: file, line: line
                )
                return
            }
        }
    }

    func testViewMatchesTheBufferForAGameCubeImage() throws {
        let body = pattern(0x18000, seed: 4)
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x8000
        spec.discHeader = discHeader()
        spec.isoSize = UInt64(0x80 + body.count)
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: body)]
        try assertViewMatchesBuffer(spec)
    }

    func testViewMatchesTheBufferThroughZstandard() throws {
        let body = pattern(0x14000, seed: 11)
        var spec = RVZFixtures.Image()
        spec.compression = .zstd
        spec.encoding = .zstdRawFrame
        spec.chunkSize = 0x8000
        spec.discHeader = discHeader()
        spec.isoSize = UInt64(0x80 + body.count)
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: body)]
        try assertViewMatchesBuffer(spec)
    }

    /// A disc with a Wii partition, so the 2 MiB block unit and the
    /// raw/partition boundary are both crossed.
    func testViewMatchesTheBufferForAWiiImage() throws {
        // A partition close to the front, so the whole disc is a few MB: the
        // realistic 0x1F04 start would make a 262 MB image to compare.
        let spec = wiiSpec(sectors: 70, chunkSize: 0x2_0000, firstSector: 0x10)
        try assertViewMatchesBuffer(spec, restorer: DeterministicRestorer())
    }

    /// An image whose declared size runs past the last region: the tail is
    /// unclaimed and must read as zeroes, which the buffer path got for free
    /// by never writing there.
    func testViewZeroFillsRangesNoRegionCovers() throws {
        let body = pattern(0x8000, seed: 5)
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x8000
        spec.discHeader = discHeader()
        // 0x20000 bytes of disc for 0x8080 bytes of content.
        spec.isoSize = 0x2_0000
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: body)]

        let image = try RVZImage(binary: RVZFixtures.build(spec))
        let view = try image.discImageView()
        XCTAssertEqual(view.length, 0x2_0000)
        let tail = try XCTUnwrap(view.read(atAddress: 0x10000, length: 0x1000))
        XCTAssertEqual(tail.rawBytes, [UInt8](repeating: 0, count: 0x1000))
        try assertViewMatchesBuffer(spec)
    }

    /// The disc header overrides the region that nominally covers it, and has
    /// to survive being read in pieces.
    func testViewAppliesTheDiscHeaderOverride() throws {
        let head = discHeader()
        let body = pattern(0x8000, seed: 6)
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x8000
        spec.discHeader = head
        spec.isoSize = UInt64(0x80 + body.count)
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: body)]

        let view = try RVZImage(binary: RVZFixtures.build(spec)).discImageView()
        XCTAssertEqual(try XCTUnwrap(view.read(atAddress: 0, length: 0x80)).rawBytes, head)
        // Split across the boundary, and entirely inside it.
        XCTAssertEqual(try XCTUnwrap(view.read(atAddress: 0x40, length: 0x40)).rawBytes, Array(head[0x40..<0x80]))
        let straddling = try XCTUnwrap(view.read(atAddress: 0x70, length: 0x20)).rawBytes
        XCTAssertEqual(Array(straddling.prefix(0x10)), Array(head[0x70..<0x80]))
        XCTAssertEqual(Array(straddling.suffix(0x10)), Array(body[0..<0x10]))
    }

    func testViewRejectsReadsOutsideTheDisc() throws {
        let body = pattern(0x8000, seed: 7)
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x8000
        spec.discHeader = discHeader()
        spec.isoSize = UInt64(0x80 + body.count)
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: body)]

        let view = try RVZImage(binary: RVZFixtures.build(spec)).discImageView()
        XCTAssertNil(view.read(atAddress: UInt(view.length), length: 1))
        XCTAssertNil(view.read(atAddress: UInt(view.length - 1), length: 2))
        XCTAssertNil(view.read(atAddress: 0, length: 0))
    }

    /// `allData` stays nil on purpose: a caller that wants the whole disc in
    /// memory has to ask `restoreISO` for it, rather than a view handing over
    /// gigabytes because something reached for a convenience.
    func testViewDoesNotOfferAWholeBuffer() throws {
        let body = pattern(0x8000, seed: 8)
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x8000
        spec.discHeader = discHeader()
        spec.isoSize = UInt64(0x80 + body.count)
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: body)]
        let view = try RVZImage(binary: RVZFixtures.build(spec)).discImageView()
        XCTAssertNil(view.allData)
    }

    /// A Wii image still refuses without a restorer, and now does so when the
    /// view is made rather than partway through producing bytes.
    func testViewRefusesAWiiImageWithoutARestorer() throws {
        let image = try RVZImage(binary: RVZFixtures.build(wiiSpec(sectors: 64)))
        XCTAssertThrowsError(try image.discImageView()) { error in
            guard case RVZError.missingPartitionRestorer = error else {
                return XCTFail("expected a missing-restorer error, got \(error)")
            }
        }
    }

    /// Re-reading inside one block must not redo the work. A counting
    /// restorer is the cheapest way to see that, since a partition block is
    /// exactly one call.
    func testViewCachesABlockAcrossReads() throws {
        let spec = wiiSpec(sectors: 64, chunkSize: 0x2_0000)
        let restorer = RecordingRestorer()
        let view = try RVZImage(binary: RVZFixtures.build(spec))
            .discImageView(partitionRestorer: restorer)
        let partitionStart = UInt(spec.partitions[0].firstSector) * UInt(RVZFixtures.clusterSize)
        _ = view.read(atAddress: partitionStart, length: 0x1000)
        XCTAssertEqual(restorer.calls.count, 1)
        _ = view.read(atAddress: partitionStart + 0x1000, length: 0x1000)
        _ = view.read(atAddress: partitionStart + 0x100000, length: 0x1000)
        XCTAssertEqual(restorer.calls.count, 1, "reads inside one group should reuse it")
    }
}
