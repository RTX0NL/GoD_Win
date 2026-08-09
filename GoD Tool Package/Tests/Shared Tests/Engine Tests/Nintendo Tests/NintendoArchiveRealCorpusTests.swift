//
//  NintendoArchiveRealCorpusTests.swift
//  NintendoTests
//
//  U8 and NARC are byte-identical targets: their geometry is fully derivable
//  from the entry list plus the engine's alignment, so a repack that differs
//  from the original is a bug, not an accepted re-derivation. This guards
//  that against real files rather than synthetic ones.
//
//  It skips cleanly when no dump is present, so it is safe to keep in the
//  suite on a machine without ROMs. Point it elsewhere with
//  GODDESS_NINTENDO_ARCHIVES (colon-separated folders, searched recursively).
//

import XCTest
import Foundation
import GoDFoundation
import Nintendo

final class NintendoArchiveRealCorpusTests: XCTestCase {

    private var searchRoots: [String] {
        if let raw = ProcessInfo.processInfo.environment["GODDESS_NINTENDO_ARCHIVES"] {
            return raw.split(separator: ":").map(String.init)
        }
        return [
            "/Users/stars/Documents/Projects/GoD-Tool/scripts/PBR PAL project/Build/Unpacked/Assets/Archives",
            "/Users/stars/Documents/Projects/GoD-Tool/scripts/PBR PAL project/Build/Contents/DATA/files",
        ]
    }

    private func archives(withExtension ext: String) -> [URL] {
        var found: [URL] = []
        for root in searchRoots {
            let url = URL(fileURLWithPath: root)
            guard let walker = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: nil
            ) else { continue }
            for case let file as URL in walker where file.pathExtension.lowercased() == ext {
                found.append(file)
            }
        }
        // Stable order so a failure names the same file on every run.
        return found.sorted { $0.path < $1.path }
    }

    private func engine() throws -> NintendoEngine {
        try NintendoEngine.defaults()
    }

    // MARK: - U8

    func testU8ArchivesRepackByteIdentically() throws {
        let files = archives(withExtension: "arc")
        try XCTSkipIf(files.isEmpty, "no .arc files found — set GODDESS_NINTENDO_ARCHIVES")

        let engine = try engine()
        var checked = 0
        for file in files {
            let original = GoDData(data: try Data(contentsOf: file), byteOrder: .big)
            let archive = try U8Archive(data: original, engine: engine)
            let repacked = try archive.data(engine: engine)
            XCTAssertEqual(
                repacked.rawBytes, original.rawBytes,
                "\(file.lastPathComponent) did not repack byte-identically"
            )
            XCTAssertFalse(archive.nodes.isEmpty, "\(file.lastPathComponent) parsed as empty")
            checked += 1
        }
        print("U8: \(checked) archives repacked byte-identically")
    }

    /// Every extracted file has to land somewhere real: a path with no empty
    /// components, and bytes that add up to less than the archive itself.
    func testU8ArchivesExtractCoherentPaths() throws {
        let files = archives(withExtension: "arc")
        try XCTSkipIf(files.isEmpty, "no .arc files found")

        let engine = try engine()
        for file in files {
            let original = GoDData(data: try Data(contentsOf: file), byteOrder: .big)
            let archive = try U8Archive(data: original, engine: engine)
            for node in archive.nodes {
                XCTAssertFalse(node.path.isEmpty, "\(file.lastPathComponent) has an unnamed node")
                XCTAssertFalse(
                    node.path.split(separator: "/").contains(where: \.isEmpty),
                    "\(file.lastPathComponent) has an empty path component in \(node.path)"
                )
            }
            let payload = archive.files.reduce(0) { total, node in
                guard case let .file(data) = node.kind else { return total }
                return total + data.length
            }
            XCTAssertLessThanOrEqual(payload, original.length)
        }
    }

    // MARK: - NARC

    func testNARCArchivesRepackByteIdentically() throws {
        let files = archives(withExtension: "narc")
        try XCTSkipIf(files.isEmpty, "no .narc files found — set GODDESS_NINTENDO_ARCHIVES")

        let engine = try engine()
        var checked = 0
        for file in files {
            let original = GoDData(data: try Data(contentsOf: file), byteOrder: .big)
            let archive = try NARCArchive(data: original, engine: engine)
            let repacked = try archive.data(engine: engine)
            XCTAssertEqual(
                repacked.rawBytes, original.rawBytes,
                "\(file.lastPathComponent) did not repack byte-identically"
            )
            checked += 1
        }
        print("NARC: \(checked) archives repacked byte-identically")
    }

    /// PBR's NARCs are the big-endian port, so they must be detected as such
    /// from their reversed magic — reading them as little-endian would give
    /// nonsense sizes rather than failing outright.
    func testNARCArchivesAreDetectedAsBigEndian() throws {
        let files = archives(withExtension: "narc")
        try XCTSkipIf(files.isEmpty, "no .narc files found")

        for file in files {
            let data = GoDData(data: try Data(contentsOf: file), byteOrder: .big)
            let signature = NintendoArchiveSignature.detect(data)
            XCTAssertEqual(signature?.format, .narc, "\(file.lastPathComponent)")
            XCTAssertEqual(signature?.byteOrder, .big, "\(file.lastPathComponent)")
        }
    }

    func testU8ArchivesAreDetectedAsBigEndian() throws {
        let files = archives(withExtension: "arc")
        try XCTSkipIf(files.isEmpty, "no .arc files found")

        for file in files {
            let data = GoDData(data: try Data(contentsOf: file), byteOrder: .big)
            let signature = NintendoArchiveSignature.detect(data)
            XCTAssertEqual(signature?.format, .u8, "\(file.lastPathComponent)")
            XCTAssertEqual(signature?.byteOrder, .big, "\(file.lastPathComponent)")
        }
    }
}
