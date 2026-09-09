//
//  FileHandleAccessTests.swift
//
//  `fileSize` picks its implementation with `#if canImport(Darwin)`, so on any
//  one host only half of it compiles into the shipped call. These tests call
//  both directly, the same way `PathConventionTests` passes `convention:`
//  explicitly — otherwise the branch this build doesn't take is code nobody
//  has ever run, and it would be discovered by a Linux user rather than here.
//

import XCTest
import Foundation
@testable import GoDFoundation

final class FileHandleAccessTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FileHandleAccessTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func write(_ byteCount: Int) throws -> URL {
        let url = scratch.appendingPathComponent("\(UUID().uuidString).bin")
        try Data((0..<byteCount).map { UInt8($0 % 251) }).write(to: url)
        return url
    }

    // MARK: - The two implementations have to agree

    /// Sizes chosen to cover the boundaries a boxing bug or an off-by-one
    /// would hide behind: nothing, one byte, an odd count, and something past
    /// a single read.
    func testBothImplementationsReportTheSameSize() throws {
        for byteCount in [0, 1, 7, 4096, 1 << 20 + 3] {
            let url = try write(byteCount)
            XCTAssertEqual(FileHandleAccess.attributeFileSize(at: url), byteCount, "attribute, \(byteCount) bytes")
            XCTAssertEqual(FileHandleAccess.seekFileSize(at: url), byteCount, "seek, \(byteCount) bytes")
            XCTAssertEqual(
                FileHandleAccess.attributeFileSize(at: url),
                FileHandleAccess.seekFileSize(at: url),
                "implementations disagree at \(byteCount) bytes"
            )
        }
    }

    /// Whichever one this build selected has to give the same answer as both.
    func testSelectedImplementationMatches() throws {
        let url = try write(1234)
        XCTAssertEqual(FileHandleAccess.fileSize(at: url), 1234)
    }

    // MARK: - Failures agree too

    /// The nil cases matter as much as the sizes: callers read nil as "no
    /// file", so an implementation that returns nil for a file that exists is
    /// worse than one that throws.
    func testBothReportNilForAMissingFile() {
        let missing = scratch.appendingPathComponent("nope.bin")
        XCTAssertNil(FileHandleAccess.attributeFileSize(at: missing))
        XCTAssertNil(FileHandleAccess.seekFileSize(at: missing))
        XCTAssertNil(FileHandleAccess.fileSize(at: missing))
    }

    /// A directory has a size on disk but isn't a file anyone can read, so
    /// `fileSize` rejects it before either implementation runs.
    /// A symlink measures as its target. `attributesOfItem` alone reports
    /// the link — the length of the path it holds — which is how a linked
    /// disc image once set up a project around a few dozen bytes.
    func testSymlinkMeasuresAsItsTarget() throws {
        let target = try write(1234)
        let link = scratch.appendingPathComponent("link.bin")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(FileHandleAccess.fileSize(at: link), 1234)
        XCTAssertEqual(try GoDStreamedData(file: File(nativePath: link.path)).length, 1234)
    }

    func testDirectoryIsNotAFileSize() throws {
        let folder = scratch.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertFalse(FileHandleAccess.isRegularFile(folder))
        XCTAssertNil(FileHandleAccess.fileSize(at: folder))
    }

    // MARK: - The reader agrees with the sizer

    /// `GoDStreamedData` takes its `length` from `fileSize`, and its bounds
    /// checks are built on it — a size that disagreed with the file would make
    /// the last byte unreadable, or reads run past the end.
    func testStreamedDataLengthMatchesBothImplementations() throws {
        let url = try write(9999)
        let streamed = try GoDStreamedData(file: File(nativePath: url.path))
        XCTAssertEqual(streamed.length, FileHandleAccess.attributeFileSize(at: url))
        XCTAssertEqual(streamed.length, FileHandleAccess.seekFileSize(at: url))
        XCTAssertNotNil(streamed.read(atAddress: 9998, length: 1), "last byte must be readable")
        XCTAssertNil(streamed.read(atAddress: 9999, length: 1), "one past the end must not be")
    }

    // MARK: - Writing

    /// The chunked copy is the other half of the streaming path; it writes in
    /// 8 MB hops, so a source that spans more than one hop is the case worth
    /// pinning.
    func testChunkedWriteReproducesTheSourceAcrossChunks() throws {
        let source = GoDData(byteStream: (0..<(9 << 20)).map { UInt8($0 % 251) }, byteOrder: .big)
        let url = scratch.appendingPathComponent("copy.bin")
        try FileHandleAccess.write(source, to: url)

        XCTAssertEqual(FileHandleAccess.fileSize(at: url), source.length)
        let readBack = try Data(contentsOf: url)
        XCTAssertEqual([UInt8](readBack), source.rawBytes)
    }

    /// Writing over a longer file must not leave the old tail behind — the
    /// handle is truncated first.
    func testChunkedWriteTruncatesAnExistingLongerFile() throws {
        let url = scratch.appendingPathComponent("shrink.bin")
        try Data(repeating: 0xAA, count: 4096).write(to: url)
        try FileHandleAccess.write(GoDData(byteStream: [1, 2, 3], byteOrder: .big), to: url)
        XCTAssertEqual(FileHandleAccess.fileSize(at: url), 3)
        XCTAssertEqual([UInt8](try Data(contentsOf: url)), [1, 2, 3])
    }
}
