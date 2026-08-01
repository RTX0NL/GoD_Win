//
//  GoDStreamedDataTests.swift
//
//  `GoDStreamedData` exists to be substitutable for `GoDData` in any reader
//  that takes a `GoDReadable`, so most of what matters here is that the two
//  agree byte for byte and, more importantly, agree on the *edges*: what
//  happens past the end, at zero length, and across the internal block
//  boundary. A reader that behaves differently at an edge would fail only on
//  large real files, which is exactly where it would be hardest to diagnose.
//

import XCTest
import Foundation
@testable import GoDFoundation

final class GoDStreamedDataTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GoDStreamedDataTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// Writes `bytes` to a file and returns both a streamed reader over it and
    /// the equivalent in-memory `GoDData`, so every assertion can compare the
    /// two implementations rather than a hand-written expectation.
    private func pair(_ bytes: [UInt8]) throws -> (GoDStreamedData, GoDData) {
        let url = scratch.appendingPathComponent("\(UUID().uuidString).bin")
        try Data(bytes).write(to: url)
        let streamed = try GoDStreamedData(file: File(nativePath: url.path))
        return (streamed, GoDData(byteStream: bytes, byteOrder: .big))
    }

    private func sequence(_ count: Int) -> [UInt8] {
        (0..<count).map { UInt8($0 % 251) }
    }

    // MARK: - Agreement with GoDData

    func testLengthMatchesTheFile() throws {
        let (streamed, memory) = try pair(sequence(1234))
        XCTAssertEqual(streamed.length, 1234)
        XCTAssertEqual(streamed.length, memory.length)
    }

    func testReadsAgreeWithGoDDataAcrossBlockBoundaries() throws {
        // Three blocks' worth, so reads land inside a block, across one
        // boundary, and across two.
        let bytes = sequence(0x10000 * 2 + 777)
        let (streamed, memory) = try pair(bytes)

        let probes: [(Int, Int)] = [
            (0, 1), (0, 16),
            (0xFFF0, 0x20),        // straddles the first block boundary
            (0xFFFF, 2),           // one byte either side of it
            (0x10000, 64),         // starts exactly on a boundary
            (0xFFF0, 0x10020),     // spans two boundaries
            (bytes.count - 1, 1),  // last byte
            (0, bytes.count),      // whole file
        ]
        for (address, length) in probes {
            let fromStream = streamed.read(atAddress: address, length: length)?.rawBytes
            let fromMemory = memory.read(atAddress: address, length: length)?.rawBytes
            XCTAssertEqual(fromStream, fromMemory, "read(\(address), \(length))")
            XCTAssertEqual(fromStream, Array(bytes[address..<(address + length)]), "read(\(address), \(length))")
        }
    }

    /// Reads larger than one block bypass the cache. They must still return
    /// the same bytes — this is the path a disc image's member files take.
    func testLargeReadsBypassingTheCacheStillMatch() throws {
        let bytes = sequence(0x10000 * 3)
        let (streamed, memory) = try pair(bytes)
        let big = 0x10000 + 1
        XCTAssertEqual(
            streamed.read(atAddress: 12, length: big)?.rawBytes,
            memory.read(atAddress: 12, length: big)?.rawBytes
        )
    }

    /// Repeated reads of the same region must be stable — a cache that handed
    /// back a mutated block would corrupt the second read only.
    func testRepeatedReadsAreStable() throws {
        let (streamed, _) = try pair(sequence(4096))
        let first = streamed.read(atAddress: 100, length: 200)?.rawBytes
        let data = try XCTUnwrap(streamed.read(atAddress: 100, length: 200))
        data.append(GoDData(byteStream: [0xFF], byteOrder: .big))   // mutate the returned copy
        XCTAssertEqual(streamed.read(atAddress: 100, length: 200)?.rawBytes, first)
    }

    // MARK: - Edges

    /// Out of range is nil, not a short read. `readString`/`readGSString` walk
    /// forward until a read fails, so a clamped read would make them run off
    /// the end of the file instead of stopping.
    func testReadsPastTheEndAreNilJustLikeGoDData() throws {
        let (streamed, memory) = try pair(sequence(64))
        for (address, length) in [(60, 8), (64, 1), (65, 0), (0, 65)] {
            XCTAssertNil(streamed.read(atAddress: address, length: length), "read(\(address), \(length))")
            XCTAssertNil(memory.read(atAddress: address, length: length), "GoDData disagrees at (\(address), \(length))")
        }
    }

    func testZeroLengthReadIsEmptyNotNil() throws {
        let (streamed, _) = try pair(sequence(64))
        XCTAssertEqual(streamed.read(atAddress: 8, length: 0)?.rawBytes, [])
    }

    func testEmptyFileReadsAsEmpty() throws {
        let (streamed, _) = try pair([])
        XCTAssertEqual(streamed.length, 0)
        XCTAssertEqual(streamed.read(atAddress: 0, length: 0)?.rawBytes, [])
        XCTAssertNil(streamed.read(atAddress: 0, length: 1))
    }

    func testOpeningAMissingFileThrows() {
        let missing = File(nativePath: scratch.appendingPathComponent("nope.bin").path)
        XCTAssertThrowsError(try GoDStreamedData(file: missing))
    }

    /// After `close` the reader is inert rather than trapping — callers that
    /// hold one past its useful life get nil, which every read site already
    /// handles.
    func testReadsAfterCloseReturnNil() throws {
        let (streamed, _) = try pair(sequence(64))
        XCTAssertNotNil(streamed.read(atAddress: 0, length: 8))
        streamed.close()
        XCTAssertNil(streamed.read(atAddress: 0, length: 8))
        streamed.close()   // idempotent
    }

    // MARK: - Substitutability

    /// The point of the type: a `GoDReadable` extension method reads the same
    /// through either implementation. `readValue` is the one every binary
    /// parser is built on.
    func testTypedReadsMatchGoDData() throws {
        let bytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0x02, 0x03]
        let (streamed, memory) = try pair(bytes)
        XCTAssertEqual(streamed.readValue(atAddress: 0) as UInt32?, memory.readValue(atAddress: 0) as UInt32?)
        XCTAssertEqual(streamed.readValue(atAddress: 0) as UInt32?, 0xDEAD_BEEF)
        XCTAssertEqual(streamed.readValue(atAddress: 6) as UInt16?, memory.readValue(atAddress: 6) as UInt16?)
    }

    func testStringReadsMatchGoDData() throws {
        var bytes = Array("GXXE01".utf8)
        bytes.append(0)
        let (streamed, memory) = try pair(bytes)
        XCTAssertEqual(
            streamed.readString(atAddress: 0, format: .utf8, maxCharacters: 6),
            memory.readString(atAddress: 0, format: .utf8, maxCharacters: 6)
        )
        XCTAssertEqual(streamed.readString(atAddress: 0, format: .utf8, maxCharacters: 6), "GXXE01")
    }

    // MARK: - The file system hands one out

    /// `FileSystem.reader(at:)` is what makes the whole thing reachable from an
    /// operation; if it fell back to the protocol default the streaming would
    /// silently never happen.
    func testFileSystemVendsAStreamedReader() throws {
        let url = scratch.appendingPathComponent("disc.bin")
        try Data(sequence(2048)).write(to: url)
        let reader = FileSystem.shared.reader(at: File(nativePath: url.path))
        XCTAssertTrue(reader is GoDStreamedData, "FileSystem should stream, not materialise")
        XCTAssertEqual(reader?.read(atAddress: 1000, length: 4)?.rawBytes, Array(sequence(2048)[1000..<1004]))
    }

    /// An in-memory tree has nothing to stream from, so it uses the default —
    /// still a working `GoDReadable`, just not a streamed one.
    func testInMemoryTreeFallsBackToWholeFileReader() throws {
        let fst = InMemoryFST()
        let file = File("/a.bin")
        try fst.writeFile(GoDData(byteStream: sequence(32), byteOrder: .big), at: file, overwrite: true)
        let reader = try XCTUnwrap(fst.reader(at: file))
        XCTAssertFalse(reader is GoDStreamedData)
        XCTAssertEqual(reader.read(atAddress: 8, length: 4)?.rawBytes, Array(sequence(32)[8..<12]))
    }
}
