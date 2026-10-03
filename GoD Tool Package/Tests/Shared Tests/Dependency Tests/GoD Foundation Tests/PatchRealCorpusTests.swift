//
//  PatchRealCorpusTests.swift
//
//  The patch codecs against patches other people's tools wrote.
//
//  Everything else about these formats is checked against the specs and against
//  independently transcribed readers; this is the only thing that checks them
//  against the ecosystem. Nothing here is synthesized: each file is a release
//  patch for a real game.
//
//  `GODDESS_PATCH_CORPUS` points at a folder, scanned recursively for `.ups`,
//  `.ips`, `.bps` and `.xdelta`; without it the dev machine's own locations are
//  tried, and the tests skip when none of them exist. `GODDESS_PATCH_CORPUS_ALL`
//  includes patches whose targets are disc-sized, which are skipped by default
//  because applying one costs a gigabyte of array.
//
//  Two gaps worth naming: there is no third-party **BPS** patch here (so that
//  format is held to its spec and its reference reader only), and the xdelta
//  sample's source ROM is not on hand, so that one is decoded structurally —
//  every window to its declared length — rather than compared byte for byte.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class PatchRealCorpusTests: XCTestCase {

    /// Target sizes above this are only visited with `GODDESS_PATCH_CORPUS_ALL`.
    private let heavyTargetSize = 16 << 20

    private var includesHeavy: Bool {
        ProcessInfo.processInfo.environment["GODDESS_PATCH_CORPUS_ALL"] != nil
    }

    private func corpus(_ extensions: Set<String>) throws -> [URL] {
        let manager = FileManager.default
        var roots = [String]()
        if let override = ProcessInfo.processInfo.environment["GODDESS_PATCH_CORPUS"] {
            roots = [override]
        } else {
            // This machine's layout; absent elsewhere, which is a skip.
            let home = manager.homeDirectoryForCurrentUser.path
            roots = [
                "\(home)/Documents/Emulation",
                "\(home)/Documents/dev/modding",
                "\(home)/Documents/Pokemon",
            ]
        }
        var found = [URL]()
        for root in roots {
            let url = URL(fileURLWithPath: root)
            guard manager.fileExists(atPath: url.path) else { continue }
            guard let walker = manager.enumerator(at: url, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in walker where extensions.contains(file.pathExtension.lowercased()) {
                found.append(file)
            }
        }
        if found.isEmpty {
            throw XCTSkip("no patch corpus — set GODDESS_PATCH_CORPUS to a folder of patch files")
        }
        return found.sorted { $0.path < $1.path }
    }

    /// Opened, not read: a release patch for a disc image runs to hundreds of
    /// megabytes, and every parser here works off windows.
    private func readable(_ url: URL) throws -> GoDReadable {
        try GoDStreamedData(file: File(nativePath: url.path), byteOrder: .big)
    }

    private func buffered(_ url: URL) throws -> GoDData {
        GoDData(data: try Data(contentsOf: url), byteOrder: .big)
    }

    /// Patch files this big are only visited with `GODDESS_PATCH_CORPUS_ALL`:
    /// parsing one means checksumming every byte of it.
    private let heavyPatchSize = 32 << 20

    private func isHeavy(_ url: URL) -> Bool {
        guard !includesHeavy else { return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > heavyPatchSize
    }

    // MARK: - UPS

    func testRealUPSPatchesParseAndCarryTheirOwnChecksum() throws {
        var checked = 0
        var skipped = 0
        for file in try corpus(["ups"]) {
            guard !isHeavy(file) else { skipped += 1; continue }
            let patch = try readable(file)
            // `parse` verifies the patch's own CRC-32 first, so this is an
            // integrity check on the real file as much as a parse.
            let ups = try UPSPatch.parse(patch)
            let name = file.lastPathComponent

            XCTAssertGreaterThan(ups.sourceSize, 0, name)
            XCTAssertGreaterThan(ups.targetSize, 0, name)
            XCTAssertFalse(ups.hunks.isEmpty, "\(name) should change something")
            XCTAssertTrue(
                ups.hunks.allSatisfy { $0.outputOffset + $0.length <= ups.coverage },
                "\(name): every hunk inside the covered space"
            )
            // Ordered and disjoint, which is what the applier's binary search
            // relies on.
            for (earlier, later) in zip(ups.hunks, ups.hunks.dropFirst()) {
                XCTAssertLessThanOrEqual(
                    earlier.outputOffset + earlier.length, later.outputOffset, "\(name): hunks out of order"
                )
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
        print("UPS corpus: \(checked) third-party patches parsed and passed their own checksum"
              + (skipped > 0 ? ", \(skipped) disc-sized ones skipped (GODDESS_PATCH_CORPUS_ALL)" : ""))
    }

    func testRealUPSPatchesAgreeWithTheReferenceApplier() throws {
        var checked = 0
        for file in try corpus(["ups"]) {
            guard !isHeavy(file) else { continue }
            let patch = try buffered(file)
            let ups = try UPSPatch.parse(patch)
            guard max(ups.sourceSize, ups.targetSize) <= heavyTargetSize || includesHeavy else { continue }

            // No base ROM is needed to compare two appliers: the same synthetic
            // input through both must give the same bytes, and that exercises
            // this patch's real hunk offsets and variable-width integers.
            let synthetic = GoDData(byteStream: [UInt8](repeating: 0x5A, count: ups.sourceSize), byteOrder: .big)
            let mine = try UPSPatchedView(input: synthetic, patch: patch, ups: ups, direction: .forward).allBytes()
            let theirs = ReferenceUPS.applyForward(patch.rawBytes, to: synthetic.rawBytes)
            XCTAssertEqual(mine.rawBytes.count, ups.targetSize, file.lastPathComponent)
            XCTAssertEqual(mine.rawBytes, theirs, file.lastPathComponent)
            checked += 1
        }
        guard checked > 0 else {
            throw XCTSkip("every UPS patch in the corpus is disc-sized; set GODDESS_PATCH_CORPUS_ALL to include them")
        }
        print("UPS corpus: \(checked) patches applied identically by both appliers")
    }

    // MARK: - IPS

    func testRealIPSPatchesParseAndApplyIdenticallyToTheReference() throws {
        var checked = 0
        var records = 0
        var runs = 0
        // Every patch is parsed; the applier comparison allocates a synthetic
        // base per patch, so it is sampled unless asked for in full.
        let applyLimit = includesHeavy ? Int.max : 30
        for file in try corpus(["ips"]) {
            guard !isHeavy(file) else { continue }
            let patch = try buffered(file)
            let ips = try IPSPatch.parse(patch)
            let name = file.lastPathComponent
            XCTAssertFalse(ips.records.isEmpty, name)
            records += ips.records.count
            runs += ips.records.filter {
                if case .run = $0.payload { return true } else { return false }
            }.count

            let size = max(ips.coverage, 1)
            guard checked < applyLimit, size <= heavyTargetSize || includesHeavy else { continue }
            let synthetic = [UInt8](repeating: 0xA5, count: size)
            let mine = try IPSPatchedView(
                input: GoDData(byteStream: synthetic, byteOrder: .big), patch: patch, ips: ips
            ).allBytes()
            let theirs = ReferenceIPS.apply(patch.rawBytes, to: synthetic)
            XCTAssertEqual(mine.rawBytes, theirs, name)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
        print("IPS corpus: \(records) records (\(runs) runs) parsed from third-party patches; "
              + "\(checked) applied identically by both appliers")
    }

    // MARK: - xdelta

    func testRealXdeltaPatchesDecodeEveryWindowToItsDeclaredLength() throws {
        var checked = 0
        for file in try corpus(["xdelta", "vcdiff"]) {
            guard !isHeavy(file) else { continue }
            let patch = try readable(file)
            let vcdiff = try VCDIFFPatch.parse(patch)
            let name = file.lastPathComponent
            XCTAssertFalse(vcdiff.windows.isEmpty, name)

            // The source ROM these were cut against isn't here, so the bytes
            // can't be checked — but the instruction stream can: every window
            // has to consume its sections exactly and produce the length it
            // declares, which is what a wrong code table or a missed
            // VCD_ADLER32 field breaks.
            let needed = vcdiff.windows.map { $0.sourceSegmentPosition + $0.sourceSegmentLength }.max() ?? 0
            let source = GeneratedReadable(length: needed, fill: 0x00)
            for window in vcdiff.windows {
                let decoded = try VCDIFFWindowDecoder.decode(
                    window: window, patch: patch, source: source, verifyChecksum: false
                )
                XCTAssertEqual(decoded.count, window.targetLength, "\(name) at \(window.targetStart)")
            }
            print("xdelta corpus: \(name) — \(vcdiff.windows.count) windows, "
                  + "\(vcdiff.targetSize) bytes of target, "
                  + "\(vcdiff.windows.allSatisfy { $0.adler32 != nil } ? "every window checksummed" : "no checksums")")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }
}
