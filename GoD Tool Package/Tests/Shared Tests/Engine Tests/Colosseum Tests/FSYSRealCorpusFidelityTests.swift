//
//  FSYSRealCorpusFidelityTests.swift
//  ColosseumTests
//
//  FSYS is a declared byte-identical target (see CLAUDE.md), so this guards
//  that claim against the real corpora rather than synthetic fixtures. It
//  skips cleanly when the unpacked projects aren't present, so it's safe to
//  keep in the suite on a machine without ROMs.
//
//  Two properties are checked:
//    1. Re-compressing a decompressed LZSS payload reproduces the game's own
//       stream byte-for-byte. This is *why* FSYS can be a 1:1 target — if the
//       encoder didn't match Genius Sonority's, nothing downstream could.
//    2. Parsing an archive and repacking it reproduces the original file.
//
//  Point the suite at other dumps with GODDESS_FSYS_CORPUS (colon-separated
//  `<game>=<folder>` pairs, game being `colo` or `xd`).
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import Structs
import GeniusSonority

final class FSYSRealCorpusFidelityTests: XCTestCase {

    private struct Corpus {
        let label: String
        let game: GSGame
        let root: String
    }

    /// How many archives each check reads. The corpora run to thousands of
    /// files and LZSS is slow in a debug build, so the default is a sample;
    /// raise it with GODDESS_FSYS_LIMIT for a full sweep.
    private var limit: Int {
        ProcessInfo.processInfo.environment["GODDESS_FSYS_LIMIT"].flatMap(Int.init) ?? 60
    }

    private var corpora: [Corpus] {
        if let raw = ProcessInfo.processInfo.environment["GODDESS_FSYS_CORPUS"] {
            return raw.split(separator: ":").compactMap { spec in
                let parts = spec.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                let game: GSGame? = parts[0] == "colo" ? .colosseum
                    : parts[0] == "xd" ? .galeOfDarkness
                    : parts[0] == "pbr" ? .battleRevolution : nil
                guard let game else { return nil }
                return Corpus(label: parts[0], game: game, root: parts[1])
            }
        }
        let base = "/Users/stars/Documents/Projects/GoD-Tool/scripts"
        return [
            Corpus(label: "Colosseum US", game: .colosseum, root: "\(base)/Colo US project/Build/Contents/files"),
            Corpus(label: "XD", game: .galeOfDarkness, root: "\(base)/XD project/Build/Contents/files"),
        ]
    }

    private func archives(in root: String, limit: Int) -> [URL] {
        guard let e = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil
        ) else { return [] }
        var found = [URL]()
        for case let url as URL in e where url.pathExtension == "fsys" {
            found.append(url)
            if found.count >= limit { break }
        }
        return found.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func availableCorpora() throws -> [Corpus] {
        let present = corpora.filter { FileManager.default.fileExists(atPath: $0.root) }
        try XCTSkipIf(present.isEmpty, "no unpacked FSYS corpus available")
        return present
    }

    // MARK: - LZSS

    /// Re-compressing what we decompressed must yield the original stream.
    func testLZSSReCompressionMatchesTheGameStreamsExactly() throws {
        for corpus in try availableCorpora() {
            let engine = GeniusSonorityEngine.defaultEngine(for: corpus.game)
            let headerStruct: StructDefinition = try engine.getStruct("FSYSHeader")
            let metaStruct: StructDefinition = try engine.getStruct("FSYSFileMetaData")
            let lzssStruct: StructDefinition = try engine.getStruct("LZSSHeader")
            let compressor = LZSSCompressor()

            var tested = 0
            var mismatches = [String]()

            for url in archives(in: corpus.root, limit: limit) {
                guard let raw = try? Data(contentsOf: url) else { continue }
                let data = GoDData(byteStream: [UInt8](raw), byteOrder: .big)
                guard let header = data.read(struct: headerStruct, atAddress: 0),
                      let entryCount: Int = header.entry_count,
                      let listAddress: Int = header.file_metadata_list,
                      let addresses: [Int32] = data.readValues(atAddress: listAddress, count: entryCount)
                else { continue }

                for address in addresses {
                    guard let meta = data.read(struct: metaStruct, atAddress: address.asInt),
                          let flags: Int = meta.flags, (flags & 0x80000000) != 0,
                          let dataAddress: Int = meta.data_address,
                          let fileSize: Int = meta.file_size,
                          let blob = data.read(atAddress: dataAddress, length: fileSize),
                          let lzss = blob.read(struct: lzssStruct, atAddress: 0),
                          let compressedSize: Int = lzss.compressed_size,
                          let uncompressedSize: Int = lzss.uncompressed_size,
                          let original = blob.read(atAddress: lzss.length, length: compressedSize - lzss.length)
                    else { continue }

                    let plain = try compressor.decompress(original, expectedSize: uncompressedSize)
                    let recompressed = compressor.compress(plain)
                    tested += 1
                    if recompressed.rawBytes != original.rawBytes {
                        mismatches.append("\(url.lastPathComponent) (\(original.length)B vs \(recompressed.length)B)")
                    }
                }
            }

            XCTAssertGreaterThan(tested, 0, "[\(corpus.label)] found no compressed entries to test")
            XCTAssertTrue(
                mismatches.isEmpty,
                "[\(corpus.label)] \(mismatches.count)/\(tested) LZSS streams did not round-trip: \(mismatches.prefix(5))"
            )
        }
    }

    // MARK: - Whole-archive repack

    func testArchivesRepackByteIdentically() throws {
        for corpus in try availableCorpora() {
            let engine = GeniusSonorityEngine.defaultEngine(for: corpus.game)
            let headerStruct: StructDefinition = try engine.getStruct("FSYSHeader")
            var tested = 0
            var mismatches = [String]()

            for url in archives(in: corpus.root, limit: limit) {
                guard let rawData = try? Data(contentsOf: url) else { continue }
                let raw = [UInt8](rawData)
                let data = GoDData(byteStream: raw, byteOrder: .big)

                // Zero-entry archives carry uninitialized packer memory that
                // can't be re-derived — they have their own test below.
                if let header = data.read(struct: headerStruct, atAddress: 0),
                   let entryCount: Int = header.entry_count, entryCount == 0 {
                    continue
                }

                let archive = try FSYSArchive(data: data, engine: engine)
                let rebuilt = try archive.data(groupID: archive.groupID, engine: engine).rawBytes
                tested += 1
                guard rebuilt != raw else { continue }

                if rebuilt.count != raw.count {
                    mismatches.append("\(url.lastPathComponent): length \(raw.count) vs \(rebuilt.count)")
                } else if let first = (0..<raw.count).first(where: { raw[$0] != rebuilt[$0] }) {
                    mismatches.append(String(
                        format: "%@: first diff @0x%X orig=%02X new=%02X",
                        url.lastPathComponent, first, raw[first], rebuilt[first]
                    ))
                }
            }

            XCTAssertGreaterThan(tested, 0, "[\(corpus.label)] found no archives to test")
            XCTAssertTrue(
                mismatches.isEmpty,
                "[\(corpus.label)] \(mismatches.count)/\(tested) archives did not repack byte-identically: \(mismatches.prefix(5))"
            )
        }
    }

    /// Zero-entry archives reserve one 0x10 unit for each of the empty offset
    /// and string tables — a shape the writer used to collapse away, which
    /// made the rebuilt file 32 bytes short.
    ///
    /// The reserved string-table window is *not* asserted byte-for-byte: in
    /// every real zero-entry archive it holds uninitialized packer memory
    /// (RAM addresses, fragments of unrelated filenames like `w_gorgeo` or
    /// `GSFSYS`), different in each file and derivable from nothing in the
    /// archive itself. Reproducing it would mean storing and replaying those
    /// bytes; everything the archive actually *describes* is reproduced.
    func testZeroEntryArchivesRepackWithTheCorrectLayout() throws {
        var checked = 0

        for corpus in try availableCorpora() {
            let engine = GeniusSonorityEngine.defaultEngine(for: corpus.game)
            let headerStruct: StructDefinition = try engine.getStruct("FSYSHeader")

            for url in archives(in: corpus.root, limit: 400) {
                guard let rawData = try? Data(contentsOf: url) else { continue }
                let raw = [UInt8](rawData)
                let data = GoDData(byteStream: raw, byteOrder: .big)
                guard let header = data.read(struct: headerStruct, atAddress: 0),
                      let entryCount: Int = header.entry_count, entryCount == 0,
                      let namesPointer: Int = header.file_names_pointer,
                      let dataPointer: Int = header.file_data_pointer
                else { continue }

                let archive = try FSYSArchive(data: data, engine: engine)
                let rebuilt = try archive.data(groupID: archive.groupID, engine: engine).rawBytes
                let name = "\(corpus.label)/\(url.lastPathComponent)"

                XCTAssertEqual(rebuilt.count, raw.count, "\(name): total size")

                let leftover = namesPointer..<dataPointer
                XCTAssertEqual(leftover.count, 0x10, "\(name): reserved string-table window")

                let differing = (0..<min(raw.count, rebuilt.count))
                    .filter { raw[$0] != rebuilt[$0] && !leftover.contains($0) }
                XCTAssertTrue(
                    differing.isEmpty,
                    "\(name): differs outside the uninitialized window at "
                        + differing.prefix(8).map { "0x" + String($0, radix: 16) }.joined(separator: ", ")
                )
                checked += 1
                break   // one per corpus is enough to pin the layout
            }
        }

        XCTAssertGreaterThan(checked, 0, "found no zero-entry archives to check")
    }
}
