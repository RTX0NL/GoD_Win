//
//  GCIRealCorpusTests.swift
//  GODOpsTests
//
//  Dump → build over every real GameCube save on the machine, asserting
//  byte identity.
//
//  The save is deleted between the dump and the build, so a match proves
//  the rebuild derived every byte rather than copying any forward.
//
//  The bar is every save, not most of them. Each step the pipeline takes
//  is claimed to be exactly invertible: RGB5A3 widens by factors the
//  encoder divides back out, paletted images keep their indices and
//  palette order through indexed PNGs, comments re-encode in the
//  character set the gamecode implies, the one checksum a game keeps over
//  its metadata is recomputed rather than replayed, and everything else
//  in the metadata region is the region's fill byte. A save that comes
//  back different means one of those claims is wrong.
//
//  Skips cleanly when no saves are present, so it is safe on a machine
//  without them. Point it elsewhere with GODDESS_GCI_CORPUS
//  (colon-separated folders, searched recursively).
//

import XCTest
import Foundation
import GoDFoundation
import GameCube
import GeniusSonority
@testable import GODOps

final class GCIRealCorpusTests: XCTestCase {

    private var searchRoots: [String] {
        if let raw = ProcessInfo.processInfo.environment["GODDESS_GCI_CORPUS"] {
            return raw.split(separator: ":").map(String.init)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Documents/Pokemon",
            "\(home)/Library/Application Support/Dolphin/GC",
            "/Users/stars/Documents/Projects/GoD-Tool/scripts",
        ]
    }

    private func corpusSaves() -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()
        for root in searchRoots {
            let url = URL(fileURLWithPath: root)
            guard let walker = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: nil
            ) else { continue }
            for case let file as URL in walker
            where file.pathExtension.lowercased() == "gci" {
                // The same save often sits in several places; comparing
                // content keeps the run honest about how many distinct
                // ones were actually covered.
                guard let data = try? Data(contentsOf: file) else { continue }
                let fingerprint = "\(data.count):\(data.prefix(0x40).map { String(format: "%02x", $0) }.joined())"
                guard seen.insert(fingerprint).inserted else { continue }
                found.append(file)
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// Dump, then delete the input, then build. Deleting it is the point:
    /// a rebuild that still matches cannot have copied anything from the
    /// save it came from, so the artifacts really are the whole source.
    private func roundTrip(_ url: URL) throws -> (original: [UInt8], rebuilt: [UInt8]) {
        let bytes = [UInt8](try Data(contentsOf: url))
        let fst = InMemoryFST()
        let input = File("/corpus/save.gci")
        try fst.writeFile(
            GoDData(byteStream: bytes, byteOrder: .big), at: input, overwrite: true
        )

        let out = Folder("/corpus/Dump")
        try GCIOps.dump(
            config: .init(operations: [
                OperationConfig(
                    operation: .dumpGCI(
                        gciFile: input, outputFolder: out, overwrite: true, saveEngine: nil
                    ),
                    enabled: .yes
                )
            ]),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        try fst.deleteFile(at: input)

        let rebuiltPath = File("/corpus/rebuilt.gci")
        try GCIOps.build(
            config: .init(operations: [
                OperationConfig(
                    operation: .buildGCI(
                        inputFolder: out, gciFile: rebuiltPath, overwrite: true
                    ),
                    enabled: .yes
                )
            ]),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        guard let rebuilt = fst.readFile(at: rebuiltPath)?.allData else {
            throw CorpusError.noRebuild(url.lastPathComponent)
        }
        return (bytes, rebuilt.rawBytes)
    }

    private enum CorpusError: Error { case noRebuild(String) }

    func testEveryRealSaveRoundTripsByteIdentically() throws {
        let saves = corpusSaves()
        try XCTSkipIf(saves.isEmpty, """
            No .gci saves found. Set GODDESS_GCI_CORPUS to a \
            colon-separated list of folders to point this elsewhere.
            """)

        var failures: [String] = []
        var gamecodes: [String: Int] = [:]

        for save in saves {
            let name = save.lastPathComponent
            do {
                let (original, rebuilt) = try roundTrip(save)
                let code = String(
                    bytes: original.prefix(4).prefix(while: { $0 != 0 }), encoding: .ascii
                ) ?? "????"
                gamecodes[code, default: 0] += 1

                guard original.count == rebuilt.count else {
                    failures.append("\(name): \(rebuilt.count) bytes, expected \(original.count)")
                    continue
                }
                if let index = (0..<original.count).first(where: { original[$0] != rebuilt[$0] }) {
                    failures.append(
                        "\(name): first difference at \(String(format: "%#x", index)) — "
                        + "\(String(format: "%02X", rebuilt[index])) vs "
                        + "\(String(format: "%02X", original[index]))"
                    )
                }
            } catch {
                failures.append("\(name): \(error)")
            }
        }

        let summary = gamecodes.sorted { $0.key < $1.key }
            .map { "\($0.key)×\($0.value)" }
            .joined(separator: ", ")
        print("GCI corpus: \(saves.count) distinct saves — \(summary)")

        XCTAssertTrue(
            failures.isEmpty,
            "\(failures.count) of \(saves.count) saves did not round-trip:\n"
            + failures.joined(separator: "\n")
        )
    }

    /// Every Genius Sonority save in the corpus should already satisfy
    /// the metadata checksum the engine declares. If one doesn't, either
    /// the rule is wrong or that save is damaged — and the round-trip
    /// test above would quietly "fix" it either way.
    func testGeniusSonorityChecksumHoldsOnEveryRealSave() throws {
        let saves = corpusSaves()
        try XCTSkipIf(saves.isEmpty, "No .gci saves found.")

        let rule = GeniusSonorityEngine.Data.geniusSonorityMetadataChecksum
        var checked = 0
        var failures: [String] = []

        for save in saves {
            let bytes = [UInt8](try Data(contentsOf: save))
            guard bytes.count > GCIFile.headerSize else { continue }
            let gamecode = String(
                bytes: bytes.prefix(4).prefix(while: { $0 != 0 }), encoding: .ascii
            ) ?? ""
            guard ["GXX", "GC6"].contains(String(gamecode.prefix(3))) else { continue }

            let body = GoDData(
                byteStream: Array(bytes[GCIFile.headerSize...]), byteOrder: .big
            )
            checked += 1
            if !rule.holds(in: body) {
                failures.append(save.lastPathComponent)
            }
        }

        try XCTSkipIf(checked == 0, "No Genius Sonority saves in the corpus.")
        print("Genius Sonority metadata checksum: \(checked - failures.count)/\(checked) hold")
        XCTAssertTrue(
            failures.isEmpty,
            "\(failures.count) of \(checked) saves fail the declared metadata checksum: "
            + failures.joined(separator: ", ")
        )
    }
}
