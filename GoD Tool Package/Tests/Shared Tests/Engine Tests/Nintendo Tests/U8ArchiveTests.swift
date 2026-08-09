//
//  U8ArchiveTests.swift
//  NintendoTests
//
//  Synthetic coverage for U8. The real-corpus test proves the big-endian
//  reader and writer against actual game files; these cover the shapes a
//  real archive doesn't happen to contain — a little-endian one, an empty
//  directory, a deep tree — plus the errors a malformed file should raise.
//

import XCTest
import Foundation
import GoDFoundation
@testable import Nintendo

final class U8ArchiveTests: XCTestCase {

    private func engine() throws -> NintendoEngine { try .defaults() }

    private func payload(_ text: String) -> GoDData {
        GoDData(byteStream: Array(text.utf8), byteOrder: .big)
    }

    private func sampleNodes() -> [U8Archive.Node] {
        [
            .init(path: "arc", kind: .directory),
            .init(path: "arc/anim", kind: .directory),
            .init(path: "arc/anim/one.brlan", kind: .file(payload("first animation"))),
            .init(path: "arc/anim/two.brlan", kind: .file(payload("second animation, longer"))),
            .init(path: "arc/timg", kind: .directory),
            .init(path: "arc/timg/tex.tpl", kind: .file(payload("texture bytes"))),
            .init(path: "readme.txt", kind: .file(payload("top level"))),
        ]
    }

    private func assertRoundTrips(
        _ nodes: [U8Archive.Node],
        byteOrder: ByteOrder,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let engine = try engine()
        let original = U8Archive(byteOrder: byteOrder, nodes: nodes)
        let packed = try original.data(engine: engine)
        let reparsed = try U8Archive(data: packed, engine: engine)

        XCTAssertEqual(reparsed.byteOrder, byteOrder, "byte order lost", file: file, line: line)
        XCTAssertEqual(
            reparsed.nodes.map(\.path), nodes.map(\.path),
            "paths or their order changed", file: file, line: line
        )
        XCTAssertEqual(
            reparsed.nodes.map { $0.kind.isDirectory }, nodes.map { $0.kind.isDirectory },
            "a node changed between file and directory", file: file, line: line
        )
        for (rebuilt, source) in zip(reparsed.nodes, nodes) {
            guard case let .file(expected) = source.kind else { continue }
            guard case let .file(actual) = rebuilt.kind else {
                return XCTFail("\(source.path) came back as a directory", file: file, line: line)
            }
            XCTAssertEqual(actual.rawBytes, expected.rawBytes, "\(source.path) payload", file: file, line: line)
        }

        // Repacking what we parsed must reproduce the same bytes — the
        // property the real-corpus test asserts against game files.
        let again = try reparsed.data(engine: engine)
        XCTAssertEqual(again.rawBytes, packed.rawBytes, "repack is not stable", file: file, line: line)
    }

    // MARK: - Round trips

    func testRoundTripBigEndian() throws {
        try assertRoundTrips(sampleNodes(), byteOrder: .big)
    }

    func testRoundTripLittleEndian() throws {
        try assertRoundTrips(sampleNodes(), byteOrder: .little)
    }

    func testRoundTripFlatArchive() throws {
        try assertRoundTrips(
            [
                .init(path: "a.bin", kind: .file(payload("aaa"))),
                .init(path: "b.bin", kind: .file(payload("bbbb"))),
            ],
            byteOrder: .big
        )
    }

    /// An empty directory leaves no trace except its node, so it is the
    /// case a path-only model would silently drop.
    func testRoundTripPreservesEmptyDirectory() throws {
        try assertRoundTrips(
            [
                .init(path: "full", kind: .directory),
                .init(path: "full/file.bin", kind: .file(payload("x"))),
                .init(path: "empty", kind: .directory),
            ],
            byteOrder: .big
        )
    }

    func testRoundTripDeepNesting() throws {
        var nodes: [U8Archive.Node] = []
        var path = ""
        for level in 0 ..< 6 {
            path = path.isEmpty ? "d0" : path + "/d\(level)"
            nodes.append(.init(path: path, kind: .directory))
        }
        nodes.append(.init(path: path + "/deep.bin", kind: .file(payload("bottom"))))
        try assertRoundTrips(nodes, byteOrder: .big)
    }

    func testRoundTripEmptyArchive() throws {
        try assertRoundTrips([], byteOrder: .big)
    }

    func testRoundTripEmptyFilePayload() throws {
        try assertRoundTrips(
            [.init(path: "zero.bin", kind: .file(GoDData(byteStream: [UInt8](), byteOrder: .big)))],
            byteOrder: .big
        )
    }

    // MARK: - Layout

    func testMagicMatchesTheByteOrder() throws {
        let engine = try engine()
        let big = try U8Archive(byteOrder: .big, nodes: sampleNodes()).data(engine: engine)
        let little = try U8Archive(byteOrder: .little, nodes: sampleNodes()).data(engine: engine)
        XCTAssertEqual(Array(big.rawBytes.prefix(4)), [0x55, 0xAA, 0x38, 0x2D])
        XCTAssertEqual(Array(little.rawBytes.prefix(4)), [0x2D, 0x38, 0xAA, 0x55])
    }

    func testFileDataIsAligned() throws {
        let engine = try engine()
        let alignment = engine.data.u8.dataAlignment
        let packed = try U8Archive(byteOrder: .big, nodes: sampleNodes()).data(engine: engine)
        let reader = ArchiveReader(bytes: packed.rawBytes, byteOrder: .big, format: "U8")

        let rootOffset = Int(try reader.u32(4))
        let dataOffset = Int(try reader.u32(12))
        XCTAssertEqual(dataOffset % alignment, 0, "the data region is not aligned")

        let nodeCount = Int(try reader.u32(rootOffset + 8))
        for index in 1 ..< nodeCount {
            let node = rootOffset + index * 12
            guard try reader.u32(node) >> 24 == 0 else { continue }
            XCTAssertEqual(Int(try reader.u32(node + 4)) % alignment, 0, "file \(index) is not aligned")
        }
    }

    func testRootNodeDeclaresTheNodeCount() throws {
        let engine = try engine()
        let nodes = sampleNodes()
        let packed = try U8Archive(byteOrder: .big, nodes: nodes).data(engine: engine)
        let reader = ArchiveReader(bytes: packed.rawBytes, byteOrder: .big, format: "U8")
        let rootOffset = Int(try reader.u32(4))
        XCTAssertEqual(try reader.u32(rootOffset), 1 << 24, "the root must be an unnamed directory")
        XCTAssertEqual(Int(try reader.u32(rootOffset + 8)), nodes.count + 1)
    }

    func testFilesAccessorReturnsOnlyFiles() {
        let archive = U8Archive(byteOrder: .big, nodes: sampleNodes())
        XCTAssertEqual(archive.files.count, 4)
        XCTAssertTrue(archive.files.allSatisfy { !$0.kind.isDirectory })
    }

    func testNodeNameAndParentPath() {
        let node = U8Archive.Node(path: "arc/anim/one.brlan", kind: .directory)
        XCTAssertEqual(node.name, "one.brlan")
        XCTAssertEqual(node.parentPath, "arc/anim")
        XCTAssertEqual(U8Archive.Node(path: "top", kind: .directory).parentPath, "")
    }

    // MARK: - Errors

    func testParsingRejectsAForeignMagic() throws {
        let engine = try engine()
        let bytes = GoDData(byteStream: Array("NARC".utf8) + [UInt8](repeating: 0, count: 32), byteOrder: .big)
        XCTAssertThrowsError(try U8Archive(data: bytes, engine: engine)) { error in
            guard case let NintendoArchiveError.wrongFormat(expected, found) = error else {
                return XCTFail("expected wrongFormat, got \(error)")
            }
            XCTAssertEqual(expected, .u8)
            XCTAssertEqual(found, .narc)
        }
    }

    func testParsingRejectsAnUnknownMagic() throws {
        let engine = try engine()
        let bytes = GoDData(byteStream: [UInt8](repeating: 0x7F, count: 32), byteOrder: .big)
        XCTAssertThrowsError(try U8Archive(data: bytes, engine: engine)) { error in
            guard case NintendoArchiveError.unrecognizedMagic = error else {
                return XCTFail("expected unrecognizedMagic, got \(error)")
            }
        }
    }

    func testParsingRejectsATruncatedFile() throws {
        let engine = try engine()
        let bytes = GoDData(byteStream: [0x55, 0xAA, 0x38, 0x2D, 0x00, 0x00, 0x00, 0x20], byteOrder: .big)
        XCTAssertThrowsError(try U8Archive(data: bytes, engine: engine)) { error in
            guard case NintendoArchiveError.truncated = error else {
                return XCTFail("expected truncated, got \(error)")
            }
        }
    }

    /// A node whose parent directory isn't in the list can't be given a
    /// parent index, so building must fail rather than silently reparent it
    /// to the root.
    func testSerializingRejectsAnOrphanedNode() throws {
        let engine = try engine()
        let archive = U8Archive(
            byteOrder: .big,
            nodes: [.init(path: "missing/child.bin", kind: .file(payload("x")))]
        )
        XCTAssertThrowsError(try archive.data(engine: engine)) { error in
            guard case let NintendoArchiveError.malformed(_, reason) = error else {
                return XCTFail("expected malformed, got \(error)")
            }
            XCTAssertTrue(reason.contains("missing"), reason)
        }
    }
}
