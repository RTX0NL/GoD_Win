//
//  FSYSLZSSHeaderCrossCheckTests.swift
//
//  `FSYSArchive` writes its own 16-byte `LZSS` header in front of each
//  compressed entry, and `LZSSHeaderedCompressor` writes the same header for
//  standalone streams. Neither is routed through the other — FSYS is a
//  verified 1:1 target and stays as it is — so this pins the two together:
//  the bytes the archive stores for a compressed entry are exactly what the
//  standalone codec produces, and the standalone codec reads them back.
//

import XCTest
import GoDFoundation
import GeniusSonority
import FixtureCatalog
import TestSupport

final class FSYSLZSSHeaderCrossCheckTests: XCTestCase {

    /// The compressed-entry payloads as they sit in the fixture archive,
    /// found by their magic. The golden test already asserts there is
    /// exactly one `LZSS` per compressed entry in this fixture.
    private func storedPayloads() throws -> [[UInt8]] {
        let blob = try FSYSFixtures.model()
            .data(groupID: FSYSFixtures.groupID, engine: FSYSFixtures.engine())
            .rawBytes
        let magic = LZSSHeaderedCompressor.magic
        var payloads: [[UInt8]] = []
        var offset = 0
        while offset + magic.count <= blob.count {
            if Array(blob[offset ..< offset + magic.count]) == magic {
                let size = Int(blob[offset + 8]) << 24 | Int(blob[offset + 9]) << 16
                    | Int(blob[offset + 10]) << 8 | Int(blob[offset + 11])
                payloads.append(Array(blob[offset ..< offset + size]))
                offset += size
            } else {
                offset += 1
            }
        }
        return payloads
    }

    private func compressedEntries() -> [FSYSArchive.Entry] {
        FSYSFixtures.entries().filter { $0.metadata.compress }
    }

    func testStandaloneCodecReproducesTheArchivesEntryBytes() throws {
        let stored = try storedPayloads()
        let entries = compressedEntries()
        XCTAssertEqual(stored.count, entries.count, "one LZSS payload per compressed entry")

        let codec = LZSSHeaderedCompressor()
        for entry in entries {
            let standalone = codec.compress(entry.data).rawBytes
            XCTAssertTrue(
                stored.contains(standalone),
                "\(entry.filename): the archive's payload and the standalone codec's output differ"
            )
        }
    }

    func testStandaloneCodecDecodesTheArchivesEntryBytes() throws {
        let expected = compressedEntries().map(\.data.rawBytes)
        for payload in try storedPayloads() {
            let data = GoDData(byteStream: payload, byteOrder: .big)
            XCTAssertEqual(CompressionFormat.detect(data), .lzss)

            let header = try LZSSHeaderedCompressor.header(of: data)
            XCTAssertEqual(header.compressedSize, payload.count, "compressed size counts the header")
            XCTAssertEqual(try CompressionFormat.lzss.uncompressedSize(of: data), header.uncompressedSize)

            let decoded = try LZSSHeaderedCompressor().decompress(data).rawBytes
            XCTAssertEqual(decoded.count, header.uncompressedSize)
            XCTAssertTrue(expected.contains(decoded), "payload did not decode to any compressed entry")
        }
    }
}
