//
//  GoDCompositeDataTests.swift
//
//  `GoDCompositeData` is the lazy form of "make a `GoDData(length: 0)` and
//  `write` each part at its offset", so what these tests pin is that it
//  produces the same bytes that pattern would — zeroes in the gaps, zeroes in
//  any declared tail, and each piece exactly where it was placed.
//
//  The reads are deliberately awkward: spanning two pieces, landing inside a
//  gap, straddling the start and end of the whole thing. A composite is read
//  in 8 MB windows by `FileHandleAccess.write` and in 2 MiB groups by the Wii
//  encrypt path, and neither lines up with where its pieces happen to begin.
//

import XCTest
import Foundation
@testable import GoDFoundation

final class GoDCompositeDataTests: XCTestCase {

    private func data(_ bytes: [UInt8]) -> GoDData {
        GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func pattern(_ count: Int, from start: UInt8) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: Int(start) + $0) }
    }

    /// Reading the whole thing a window at a time must equal reading it in
    /// one go, for any window size.
    private func assertConsistent(
        _ composite: GoDCompositeData,
        equals expected: [UInt8],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(composite.length, expected.count, "length", file: file, line: line)
        let whole = try XCTUnwrap(composite.read(atAddress: 0, length: composite.length), file: file, line: line)
        XCTAssertEqual(whole.rawBytes, expected, "single read", file: file, line: line)
        for window in [1, 2, 3, 7, 16, 100, 4096] where window < expected.count {
            var out = [UInt8]()
            var offset = 0
            while offset < composite.length {
                let count = min(window, composite.length - offset)
                guard let chunk = composite.read(atAddress: offset, length: count) else {
                    return XCTFail("nil read at \(offset)+\(count)", file: file, line: line)
                }
                out.append(contentsOf: chunk.rawBytes)
                offset += count
            }
            XCTAssertEqual(out, expected, "window \(window)", file: file, line: line)
        }
        XCTAssertEqual(try composite.materialized().rawBytes, expected, "materialized", file: file, line: line)
    }

    // MARK: - Layout

    func testPlacesPiecesAtTheirOffsetsAndZeroesTheGaps() throws {
        let first = pattern(4, from: 0x10)
        let second = pattern(3, from: 0xA0)
        let composite = try GoDCompositeData(pieces: [
            .init(offset: 2, source: data(first), name: "first"),
            .init(offset: 10, source: data(second), name: "second"),
        ])
        var expected = [UInt8](repeating: 0, count: 13)
        expected.replaceSubrange(2..<6, with: first)
        expected.replaceSubrange(10..<13, with: second)
        try assertConsistent(composite, equals: expected)
    }

    /// Length defaults to where the last piece ends.
    func testLengthDefaultsToTheEndOfTheLastPiece() throws {
        let composite = try GoDCompositeData(pieces: [
            .init(offset: 100, bytes: [1, 2, 3], name: "only"),
        ])
        XCTAssertEqual(composite.length, 103)
    }

    /// A declared length larger than the content leaves a zero tail, which is
    /// how a disc image reserves space past what it holds.
    func testADeclaredLengthLeavesAZeroFilledTail() throws {
        let body = pattern(5, from: 1)
        let composite = try GoDCompositeData(
            pieces: [.init(offset: 0, source: data(body), name: "body")],
            length: 12
        )
        try assertConsistent(composite, equals: body + [UInt8](repeating: 0, count: 7))
    }

    func testAnEmptyCompositeHasNoLength() throws {
        let composite = try GoDCompositeData(pieces: [])
        XCTAssertEqual(composite.length, 0)
        XCTAssertNil(composite.read(atAddress: 0, length: 1))
    }

    /// A zero-length piece contributes nothing and must not collide with
    /// whatever else sits at its offset — an empty file in a rebuilt
    /// filesystem is the real case.
    func testZeroLengthPiecesAreIgnored() throws {
        let body = pattern(4, from: 0x20)
        let composite = try GoDCompositeData(pieces: [
            .init(offset: 0, source: data(body), name: "body"),
            .init(offset: 0, bytes: [], name: "empty at the same offset"),
            .init(offset: 2, bytes: [], name: "empty inside the body"),
        ])
        try assertConsistent(composite, equals: body)
    }

    /// Pieces may be given in any order; the composite sorts them.
    func testAcceptsPiecesOutOfOrder() throws {
        let composite = try GoDCompositeData(pieces: [
            .init(offset: 8, bytes: [9, 9], name: "late"),
            .init(offset: 0, bytes: [1, 1], name: "early"),
            .init(offset: 4, bytes: [5, 5], name: "middle"),
        ])
        try assertConsistent(composite, equals: [1, 1, 0, 0, 5, 5, 0, 0, 9, 9])
    }

    // MARK: - Rejections

    func testRejectsOverlappingPieces() {
        XCTAssertThrowsError(try GoDCompositeData(pieces: [
            .init(offset: 0, bytes: [1, 2, 3, 4], name: "first"),
            .init(offset: 3, bytes: [5, 6], name: "second"),
        ])) { error in
            guard case let GoDCompositeData.CompositeError.overlappingPieces(a, b, offset) = error else {
                return XCTFail("expected an overlap error, got \(error)")
            }
            XCTAssertEqual(a, "first")
            XCTAssertEqual(b, "second")
            XCTAssertEqual(offset, 3)
        }
    }

    /// Adjacent is not overlapping: one piece ending exactly where the next
    /// begins is the normal case for a header followed by its body.
    func testAdjacentPiecesAreAllowed() throws {
        let composite = try GoDCompositeData(pieces: [
            .init(offset: 0, bytes: [1, 2], name: "header"),
            .init(offset: 2, bytes: [3, 4], name: "body"),
        ])
        try assertConsistent(composite, equals: [1, 2, 3, 4])
    }

    func testRejectsANegativeOffset() {
        XCTAssertThrowsError(try GoDCompositeData(pieces: [
            .init(offset: -1, bytes: [1], name: "before the start"),
        ])) { error in
            guard case GoDCompositeData.CompositeError.negativeOffset = error else {
                return XCTFail("expected a negative-offset error, got \(error)")
            }
        }
    }

    func testRejectsADeclaredLengthSmallerThanItsPieces() {
        XCTAssertThrowsError(try GoDCompositeData(
            pieces: [.init(offset: 0, bytes: [1, 2, 3, 4], name: "body")],
            length: 3
        )) { error in
            guard case GoDCompositeData.CompositeError.declaredLengthTooSmall = error else {
                return XCTFail("expected a declared-length error, got \(error)")
            }
        }
    }

    func testRejectsReadsOutsideItself() throws {
        let composite = try GoDCompositeData(pieces: [.init(offset: 0, bytes: [1, 2, 3, 4], name: "body")])
        XCTAssertNil(composite.read(atAddress: 4, length: 1))
        XCTAssertNil(composite.read(atAddress: 3, length: 2))
        XCTAssertNil(composite.read(atAddress: 0, length: 0))
    }

    // MARK: - Scale and nesting

    /// Many pieces, so the binary search that finds the first one actually
    /// has something to get wrong. Every read is checked against the
    /// imperative buffer the composite replaces.
    func testManyPiecesReadBackCorrectly() throws {
        let count = 500
        let stride = 37
        let pieceLength = 11
        var pieces = [GoDCompositeData.Piece]()
        var expected = [UInt8](repeating: 0, count: count * stride)
        for index in 0..<count {
            let bytes = pattern(pieceLength, from: UInt8(truncatingIfNeeded: index))
            pieces.append(.init(offset: index * stride, source: data(bytes), name: "piece \(index)"))
            expected.replaceSubrange((index * stride)..<(index * stride + pieceLength), with: bytes)
        }
        let composite = try GoDCompositeData(pieces: pieces, length: count * stride)
        XCTAssertEqual(try composite.materialized().rawBytes, expected)
        // Spot-check reads that begin and end in gaps, in pieces, and across
        // several of each.
        for start in [0, 11, 12, 36, 37, 1000, 4321] {
            for length in [1, 5, 26, 37, 74, 101] where start + length <= composite.length {
                let chunk = try XCTUnwrap(composite.read(atAddress: start, length: length))
                XCTAssertEqual(
                    chunk.rawBytes, Array(expected[start..<(start + length)]),
                    "read \(start)+\(length)"
                )
            }
        }
    }

    /// A composite of composites: what a rebuilt Wii disc is — partitions,
    /// each itself a ticket plus a TMD plus encrypted data.
    func testNestsInsideItself() throws {
        let inner = try GoDCompositeData(pieces: [
            .init(offset: 0, bytes: [0xAA, 0xBB], name: "inner head"),
            .init(offset: 4, bytes: [0xCC], name: "inner body"),
        ], length: 6)
        let outer = try GoDCompositeData(pieces: [
            .init(offset: 0, bytes: [0x01], name: "outer head"),
            .init(offset: 3, source: inner, name: "inner"),
        ], length: 10)
        try assertConsistent(outer, equals: [0x01, 0, 0, 0xAA, 0xBB, 0, 0, 0xCC, 0, 0])
    }

    /// A composite is a lazy source, so it leaves `allData` nil — asking for
    /// the whole thing is `materialized()`, where the cost is visible.
    func testDoesNotOfferAWholeBufferImplicitly() throws {
        let composite = try GoDCompositeData(pieces: [.init(offset: 0, bytes: [1, 2, 3], name: "body")])
        XCTAssertNil(composite.allData)
        XCTAssertEqual(try composite.materialized().rawBytes, [1, 2, 3])
    }

    /// A source shorter than its piece claims would silently pad; the read
    /// has to fail instead.
    func testReportsAPieceThatCannotServeItsRange() throws {
        final class ShortSource: GoDReadable {
            let byteOrder: ByteOrder = .big
            let length = 4
            func read(atAddress address: UInt, length: UInt) -> GoDData? { nil }
        }
        let composite = try GoDCompositeData(pieces: [.init(offset: 0, source: ShortSource(), name: "short")])
        XCTAssertNil(composite.read(atAddress: 0, length: 4))
    }
}
