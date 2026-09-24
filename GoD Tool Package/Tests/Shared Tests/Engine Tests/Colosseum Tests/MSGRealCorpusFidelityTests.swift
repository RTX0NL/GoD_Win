//
//  MSGRealCorpusFidelityTests.swift
//
//  MSG is a declared byte-identical target: a real `.msg` must survive
//  binary → MSGFile → binary unchanged, and the editable JSON must carry
//  everything that takes.
//
//  Three things make that work, and each was a defect the corpus caught:
//  the pool is not written in entry-table order (1339 of the 2312 entries
//  on the six GameCube discs order it differently); a string ends where the
//  next one starts, not where the character codec thinks it does; and a
//  reading that doesn't re-encode to its own bytes is not to be trusted.
//
//  Skips without a corpus. `GODDESS_MSG_CORPUS` points at a folder to walk
//  for `.msg` files (recursively); the default is a legacy GoD tool dump.
//  The fullest corpus is every MSG entry of all six discs, extracted from
//  the ISOs — 2312 of them, all byte-identical both ways.
//

import XCTest
import Foundation
import GoDFoundation
import GeniusSonority

final class MSGRealCorpusFidelityTests: XCTestCase {

    private static var corpusRoot: String {
        ProcessInfo.processInfo.environment["GODDESS_MSG_CORPUS"]
            ?? NSHomeDirectory() + "/Documents/GoD Tool"
    }

    /// Every `.msg` under the corpus root, with the variant its path implies.
    private func corpusFiles() throws -> [(url: URL, variant: MSGFile.Variant)] {
        let root = Self.corpusRoot
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw XCTSkip("No MSG corpus at \(root) — set GODDESS_MSG_CORPUS to a folder of .msg files.")
        }
        guard let walk = FileManager.default.enumerator(atPath: root) else {
            throw XCTSkip("Could not read \(root).")
        }
        var found: [(URL, MSGFile.Variant)] = []
        for case let relative as String in walk where relative.hasSuffix(".msg") {
            let url = URL(fileURLWithPath: root).appendingPathComponent(relative)
            found.append((url, relative.contains("Colo") ? .colo : .xd))
        }
        if found.isEmpty {
            throw XCTSkip("No .msg files under \(root).")
        }
        return found.sorted { $0.0.path < $1.0.path }
    }

    private func load(_ url: URL) throws -> GoDData {
        GoDData(byteStream: [UInt8](try Data(contentsOf: url)), byteOrder: .big)
    }

    /// binary → MSGFile → binary, byte-for-byte, on every file in the corpus.
    func testEveryMessageFileRepacksByteIdentically() throws {
        var checked = 0, skippedPBR = 0
        var failures: [String] = []

        for (url, variant) in try corpusFiles() {
            let original = try load(url)
            guard original.readString(atAddress: 0x00, format: .utf8, maxCharacters: 4) != "MESG" else {
                // A Battle Revolution table, which this parser must refuse
                // rather than read as an empty file.
                XCTAssertThrowsError(try MSGFile(binary: original, variant: variant),
                                     "\(url.lastPathComponent) is a MESG and should be refused")
                skippedPBR += 1
                continue
            }
            let parsed: MSGFile
            do {
                parsed = try MSGFile(binary: original, variant: variant)
            } catch {
                failures.append("\(url.lastPathComponent): parse failed — \(error)")
                continue
            }
            let repacked = try parsed.binaries.first?.data.rawBytes ?? []
            if repacked != original.rawBytes {
                let firstDifference = zip(repacked, original.rawBytes).enumerated()
                    .first { $0.element.0 != $0.element.1 }?.offset
                failures.append(
                    "\(url.lastPathComponent): \(original.length) bytes in, \(repacked.count) out"
                    + (firstDifference.map { ", first difference at 0x\(String($0, radix: 16))" } ?? "")
                )
            }
            checked += 1
        }

        XCTAssertTrue(
            failures.isEmpty,
            "\(failures.count) of \(checked) files did not repack byte-identically:\n"
            + failures.prefix(20).joined(separator: "\n")
        )
        XCTAssertGreaterThan(checked, 0, "corpus held no Colosseum/XD message files")
        print("MSG corpus: \(checked) files repacked byte-identically (\(skippedPBR) MESG refused)")
    }

    /// binary → JSON artifacts → binary. The editable form has to carry the
    /// layout too, or an untouched project would rewrite every message file.
    func testEveryMessageFileSurvivesTheJSONArtifact() throws {
        var checked = 0
        var failures: [String] = []

        for (url, variant) in try corpusFiles() {
            let original = try load(url)
            guard original.readString(atAddress: 0x00, format: .utf8, maxCharacters: 4) != "MESG",
                  let parsed = try? MSGFile(binary: original, variant: variant) else { continue }

            do {
                let artifacts = try parsed.outputs
                let reloaded = try MSGFile(outputs: artifacts)
                let repacked = try reloaded.binaries.first?.data.rawBytes ?? []
                if repacked != original.rawBytes {
                    failures.append("\(url.lastPathComponent): \(original.length) in, \(repacked.count) out")
                }
            } catch {
                failures.append("\(url.lastPathComponent): \(error)")
            }
            checked += 1
        }

        XCTAssertTrue(
            failures.isEmpty,
            "\(failures.count) of \(checked) files did not survive the JSON artifact:\n"
            + failures.prefix(20).joined(separator: "\n")
        )
        print("MSG corpus: \(checked) files survived the JSON round trip")
    }
}
