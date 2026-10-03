//
//  ISFHeaderRealCorpusTests.swift
//  ColosseumTests
//
//  Every real ISH/ISD pair the corpus holds, through `ISFFile` and back,
//  asserting the 0x40-byte header is reproduced byte for byte.
//
//  The synthetic goldens cannot answer this on their own: they are built by
//  the same writer they check, and `isf_sample` carries the non-looping
//  defaults — which is how three defects survived. The writer treated the
//  loop words as byte offsets into the ISD rather than nibble addresses into
//  one channel's stream (so every control point came back a byte short), it
//  wrote zeros over 0x28 (live on 565 of 565 real headers), and it wrote the
//  block-padded ISD length at 0x10 instead of the stored stream size (which
//  differs on 464 of those 565).
//
//  Only the first 0x40 bytes are asserted. The coefficient table past it is
//  re-derived by LPC analysis of the decoded PCM, and the ADPCM body is a
//  lossy 4-bit codec — ISF is not a declared 1:1 target. The header is.
//
//  Skips without a corpus. `GODDESS_ISF_CORPUS` points at a folder to walk,
//  `GODDESS_ISF_LIMIT` raises the sample size (`all` for every pair) — the
//  encoder's per-frame coefficient search runs at about a megabyte a second
//  in a debug build and the corpus holds a few hundred megabytes of stream,
//  so the exhaustive run wants `-c release` (177 pairs in ~6 minutes there,
//  against ~13 seconds a pair in debug).
//
//  Audited exhaustively on both dumps on the dev machine: 128 pairs (80
//  looping) under the legacy tool's dump and 49 (8 looping) under a GODDESS
//  project dump, every header byte-identical through the binary and through
//  the manifest.
//  Pairs are found by magic rather than by extension, because the legacy
//  tool's dump names the stream `.ish` and the header `.isd` for every
//  unnamed entry.
//

import XCTest
import Foundation
import GoDFoundation
@testable import GeniusSonority

final class ISFHeaderRealCorpusTests: XCTestCase {

    private static let defaultCorpus = "/Users/stars/Documents/GoD Tool"

    /// Pairs to exercise. The header work is cheap; re-encoding the ADPCM to
    /// get there is not, so the default is a sample that still includes
    /// looping streams.
    private var limit: Int {
        guard let raw = ProcessInfo.processInfo.environment["GODDESS_ISF_LIMIT"] else { return 6 }
        return raw == "all" ? Int.max : (Int(raw) ?? 6)
    }

    private struct Pair {
        let name: String
        let ish: GoDData
        let isd: GoDData
    }

    /// An ISF pair is two files in one folder, one of which starts `I_SF`.
    /// Two layouts have to be read, because the naming is not consistent
    /// across dumps:
    ///
    /// - **Same stem** — `foo.ish` + `foo.isd`, which is what `dumpAudios`
    ///   itself looks for and what a correctly-named dump produces.
    /// - **One pair per folder** — the legacy tool wrote an unnamed entry as
    ///   `<archive> 0000.isd` + `<archive> 0001.ish`, with the extensions
    ///   swapped *and* the indices differing, so the stems don't match.
    ///
    /// A folder holding several unmatched files is skipped: in
    /// `stm_se_nakigoe_archive` the halves interleave rather than running in
    /// step, so pairing them by position would pair them confidently and
    /// wrongly.
    private func corpusPairs(limit: Int = .max) throws -> [Pair] {
        let path = ProcessInfo.processInfo.environment["GODDESS_ISF_CORPUS"] ?? Self.defaultCorpus
        let root = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("No ISF corpus at \(path) — set GODDESS_ISF_CORPUS to a folder of dumped streams.")
        }

        let all = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { ["ish", "isd"].contains($0.pathExtension.lowercased()) } ?? []

        var byFolder: [String: [URL]] = [:]
        for url in all {
            byFolder[url.deletingLastPathComponent().path, default: []].append(url)
        }

        var pairs: [Pair] = []
        for (_, urls) in byFolder {
            var byStem: [String: [URL]] = [:]
            for url in urls {
                byStem[url.deletingPathExtension().lastPathComponent, default: []].append(url)
            }
            var leftovers: [URL] = []
            for (_, group) in byStem {
                if group.count == 2 {
                    if let pair = makePair(group) { pairs.append(pair) }
                } else {
                    leftovers.append(contentsOf: group)
                }
            }
            if leftovers.count == 2, let pair = makePair(leftovers) {
                pairs.append(pair)
            }
        }

        guard !pairs.isEmpty else {
            throw XCTSkip("No ISH/ISD pairs under \(path).")
        }
        let sorted = pairs.sorted { $0.name < $1.name }
        guard limit < sorted.count else { return sorted }

        // A sample has to cover both shapes — only a looping stream
        // exercises 0x20 and 0x24, and only a non-looping one pins the
        // `0x20 == 2`, `0x24 == 0x28` convention — so take half of each,
        // smallest first. Smallest matters: the looping streams are the
        // music and run to several megabytes apiece, and re-encoding one
        // is the whole cost of the test.
        func smallestFirst(_ ps: [Pair]) -> [Pair] {
            ps.sorted { ($0.isd.length, $0.name) < ($1.isd.length, $1.name) }
        }
        let looping = smallestFirst(sorted.filter { $0.ish.readSafely(atAddress: 0x1C) as UInt32 != 0 })
        let plain = smallestFirst(sorted.filter { $0.ish.readSafely(atAddress: 0x1C) as UInt32 == 0 })
        let half = limit / 2
        let picked = looping.prefix(half) + plain.prefix(limit - min(half, looping.count))
        return Array(picked.prefix(limit)).sorted { $0.name < $1.name }
    }

    /// Reads two files and tells the header from the stream by magic rather
    /// than by extension.
    private func makePair(_ urls: [URL]) -> Pair? {
        var header: (URL, [UInt8])?
        var stream: [UInt8]?
        for url in urls.sorted(by: { $0.path < $1.path }) {
            guard let bytes = try? Data(contentsOf: url) else { continue }
            let raw = [UInt8](bytes)
            if raw.count >= 0x40, Array(raw.prefix(4)) == Array("I_SF".utf8) {
                header = (url, raw)
            } else {
                stream = raw
            }
        }
        guard let header, let stream else { return nil }
        return Pair(
            name: header.0.deletingPathExtension().lastPathComponent,
            ish: GoDData(byteStream: header.1, byteOrder: .big),
            isd: GoDData(byteStream: stream, byteOrder: .big)
        )
    }

    /// The header, minus the content length at `0x10`.
    ///
    /// `0x10` is re-derived from the ADPCM this build encodes rather than
    /// carried, so it describes our stream rather than the games' — their
    /// packer stopped mid-frame where ours emits whole frames, which makes
    /// their value 0-13 bytes smaller on 464 of 565 real headers. Carrying
    /// theirs would be replaying original bytes for round-trip fidelity,
    /// which is exactly what the project's philosophy rules out. It is
    /// checked separately below.
    private func headerBytes(_ data: GoDData) -> [UInt8]? {
        guard let raw = data.read(atAddress: 0, length: 0x40)?.rawBytes else { return nil }
        var masked = raw
        for i in 0x10..<0x14 { masked[i] = 0 }
        return masked
    }

    private func contentLength(_ data: GoDData) -> UInt32 {
        data.readSafely(atAddress: 0x10)
    }

    /// Binary → `ISFFile` → binary reproduces the header exactly.
    func testEveryPairRebuildsItsHeaderByteIdentically() throws {
        let pairs = try corpusPairs(limit: limit)
        var differed: [String] = []
        var failed: [String] = []
        var contentLengthOff: [String] = []
        var looping = 0

        for pair in pairs {
            do {
                let parsed = try ISFFile(ish: pair.ish, isd: pair.isd, name: pair.name)
                if parsed.loop.enabled { looping += 1 }
                let (rebuilt, _) = try parsed.ishISDBytes()
                if headerBytes(rebuilt) != headerBytes(pair.ish) {
                    differed.append(pair.name)
                }
                // The derived content length may only ever exceed the
                // games' own, and by less than one frame per channel.
                let ours = contentLength(rebuilt), theirs = contentLength(pair.ish)
                let slack = Int(ISFFile.bytesPerFrame) * Int(parsed.channelCount)
                if ours < theirs || Int(ours) - Int(theirs) >= slack {
                    contentLengthOff.append("\(pair.name): \(ours) vs \(theirs)")
                }
            } catch {
                failed.append("\(pair.name): \(error)")
            }
        }

        XCTAssertTrue(failed.isEmpty, "\(failed.count) of \(pairs.count) pairs failed to parse:\n"
                      + failed.prefix(10).joined(separator: "\n"))
        XCTAssertTrue(differed.isEmpty, "\(differed.count) of \(pairs.count) headers changed:\n"
                      + differed.prefix(10).joined(separator: "\n"))
        XCTAssertTrue(contentLengthOff.isEmpty,
                      "\(contentLengthOff.count) content lengths are not within one frame:\n"
                      + contentLengthOff.prefix(10).joined(separator: "\n"))
        XCTAssertGreaterThan(looping, 0, "a corpus with no looping stream cannot exercise 0x20/0x24")
        print("ISF header corpus: \(pairs.count) pairs, \(looping) looping, "
              + "every header byte-identical apart from the derived content length at 0x10")
    }

    /// The same, through the editable artifacts a user actually edits —
    /// binary → JSON + WAV → binary. This is the path the seconds
    /// representation has to survive.
    func testEveryPairRebuildsItsHeaderThroughTheManifest() throws {
        let pairs = try corpusPairs(limit: limit)
        var differed: [String] = []
        var failed: [String] = []

        for pair in pairs {
            do {
                let parsed = try ISFFile(ish: pair.ish, isd: pair.isd, name: pair.name)
                let rebuilt = try ISFFile(outputs: try parsed.outputs)
                let (ish, _) = try rebuilt.ishISDBytes()
                if headerBytes(ish) != headerBytes(pair.ish) {
                    differed.append(pair.name)
                }
            } catch {
                failed.append("\(pair.name): \(error)")
            }
        }

        XCTAssertTrue(failed.isEmpty, "\(failed.count) of \(pairs.count) pairs failed:\n"
                      + failed.prefix(10).joined(separator: "\n"))
        XCTAssertTrue(differed.isEmpty, "\(differed.count) of \(pairs.count) headers changed via the manifest:\n"
                      + differed.prefix(10).joined(separator: "\n"))
    }

    /// Facts the format's decisions rest on, asserted against the discs so
    /// they can't quietly stop being true: every control word names a sample
    /// (so seconds is a faithful unit), and 0x2C..0x3F is reserved.
    func testCorpusControlWordInvariants() throws {
        let pairs = try corpusPairs()
        var notSampleAligned: [String] = []
        var reservedDirty: [String] = []
        var liveStreamEnd = 0

        for pair in pairs {
            let words: [UInt32] = [0x20, 0x24, 0x28].map { pair.ish.readSafely(atAddress: $0) }
            for word in words where word % 16 < 2 {
                notSampleAligned.append("\(pair.name): nibble \(word)")
            }
            if words[2] != 0 { liveStreamEnd += 1 }
            if pair.ish.read(atAddress: 0x2C, length: 0x14)?.rawBytes.contains(where: { $0 != 0 }) == true {
                reservedDirty.append(pair.name)
            }
        }

        XCTAssertTrue(notSampleAligned.isEmpty,
                      "control words that name no sample cannot be written as seconds:\n"
                      + notSampleAligned.prefix(10).joined(separator: "\n"))
        XCTAssertTrue(reservedDirty.isEmpty,
                      "0x2C..0x3F is written as zero, so it must be zero on disc:\n"
                      + reservedDirty.prefix(10).joined(separator: "\n"))
        XCTAssertEqual(liveStreamEnd, pairs.count,
                       "0x28 is a live field on every real header; zeroing it is the bug this guards")
    }
}
