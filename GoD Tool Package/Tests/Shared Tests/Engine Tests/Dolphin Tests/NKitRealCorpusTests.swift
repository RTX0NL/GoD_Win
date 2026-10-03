//
//  NKitRealCorpusTests.swift
//  DolphinTests
//
//  The gate that matters for NKit: a real `.nkit.iso` produced by
//  NKit v1, restored against the real ISO it was made from. Synthetic
//  coverage can't reach this — the shape of a real image (files packed
//  together, FST rewritten, junk runs replaced by gap markers) is
//  exactly what an earlier version of this codec got wrong while
//  reporting success.
//
//  Skips cleanly when the files aren't present. Point it elsewhere with
//  `GODDESS_NKIT_SAMPLE` (a `.nkit.iso`) and `GODDESS_NKIT_REFERENCE`
//  (the raw ISO it was made from).
//
//  These move 1.4 GB per direction and are correspondingly slow in a
//  debug build.
//

import XCTest
import Foundation
import GoDFoundation
@testable import Dolphin

final class NKitRealCorpusTests: XCTestCase {

    private static let defaultSample =
        NSString(string: "~/Documents/Emulation/GC/ROMs/XD (US).nkit.iso").expandingTildeInPath
    private static let defaultReference =
        NSString(string: "~/Documents/Emulation/GC/ROMs/XD US.iso").expandingTildeInPath

    private func paths() throws -> (sample: String, reference: String) {
        let environment = ProcessInfo.processInfo.environment
        let sample = environment["GODDESS_NKIT_SAMPLE"] ?? Self.defaultSample
        let reference = environment["GODDESS_NKIT_REFERENCE"] ?? Self.defaultReference
        guard FileManager.default.fileExists(atPath: sample) else {
            throw XCTSkip("No NKit sample at \(sample) — set GODDESS_NKIT_SAMPLE")
        }
        guard FileManager.default.fileExists(atPath: reference) else {
            throw XCTSkip("No reference ISO at \(reference) — set GODDESS_NKIT_REFERENCE")
        }
        return (sample, reference)
    }

    private func load(_ path: String) throws -> GoDData {
        GoDData(data: try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
                byteOrder: .big)
    }

    /// Report the first difference rather than dumping 1.4 GB into the
    /// failure message.
    private func assertIdentical(_ produced: GoDData, _ expected: GoDData, _ what: String) {
        XCTAssertEqual(produced.length, expected.length, "\(what): length")
        guard produced.length == expected.length else { return }
        let chunkSize = 0x40_0000
        var offset = 0
        while offset < produced.length {
            let take = min(chunkSize, produced.length - offset)
            let a = produced.read(atAddress: offset, length: take)?.rawBytes
            let b = expected.read(atAddress: offset, length: take)?.rawBytes
            if a != b {
                let first = zip(a ?? [], b ?? []).enumerated().first { $0.element.0 != $0.element.1 }
                let at = offset + (first?.offset ?? 0)
                return XCTFail("\(what): first difference at \(String(format: "0x%X", at))")
            }
            offset += take
        }
    }

    func testRestoresARealNKitImageToItsReferenceISO() throws {
        let (sample, reference) = try paths()
        let nkit = try load(sample)
        let expected = try load(reference)

        // The CRC the sample records has to be the reference's, or the
        // two files aren't a matched pair and the test proves nothing.
        let header = try NKitHeader(binary: nkit, platform: .gamecube)
        XCTAssertEqual(header.originalCRC, CRC32.compute(expected.rawBytes),
                       "sample and reference are not the same disc")

        let restored = try NKitGCConverter.dump(nkit: nkit)
        assertIdentical(restored, expected, "restore of \(URL(fileURLWithPath: sample).lastPathComponent)")
    }

    func testShrinksARealISOAndRestoresItByteForByte() throws {
        let (_, reference) = try paths()
        let iso = try load(reference)

        let nkit = try NKitGCConverter.build(iso: iso)
        XCTAssertLessThan(nkit.length, iso.length, "the image should actually shrink")
        // The shrunk file carries the original disc's CRC as its own.
        XCTAssertEqual(CRC32.compute(nkit.rawBytes), CRC32.compute(iso.rawBytes))

        let restored = try NKitGCConverter.dump(nkit: nkit)
        assertIdentical(restored, iso, "round trip of \(URL(fileURLWithPath: reference).lastPathComponent)")
    }
}
