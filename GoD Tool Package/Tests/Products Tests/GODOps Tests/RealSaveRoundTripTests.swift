//
//  RealSaveRoundTripTests.swift
//  GODOpsTests
//
//  End-to-end losslessness check against real .gci saves in the user's
//  Downloads folder. Skips cleanly when the files aren't present, so
//  this is safe to keep in the suite. Splits the GCI envelope, runs the
//  real save dump + build ops through an InMemoryFST, decrypts the
//  rebuilt latest slot, and checks the non-latest slots pass through
//  unchanged.
//
//  Losslessness differs by game because of what the rebuild can derive:
//    - Colo: sections tile the whole slot, so the rebuilt slot is
//      byte-identical to the original decrypted slot.
//    - XD: the rebuild is from scratch and zeroes the non-sub-block
//      "gap"/tail bytes (non-semantic leftover the game carries forward
//      and re-randomises). So we assert functional losslessness — the
//      header region and every sub-block are byte-identical, and the
//      checksum validates — rather than full byte-identity.
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import GameCube
import GeniusSonority
import XD
import Colosseum
@testable import GODOps

final class RealSaveRoundTripTests: XCTestCase {

    private let downloads = "/Users/stars/Downloads"

    private func loadGCIBody(_ filename: String) throws -> GoDData? {
        let path = "\(downloads)/\(filename)"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        let gci = GoDData(byteStream: [UInt8](data), byteOrder: .big)
        let parsed = try GCIFile(data: gci, name: "save")
        return parsed.body
    }

    /// First offset where two byte arrays differ, or nil if identical.
    private func firstDivergence(_ a: [UInt8], _ b: [UInt8]) -> Int? {
        if a.count != b.count { return min(a.count, b.count) }
        for i in 0..<a.count where a[i] != b[i] { return i }
        return nil
    }

    private func hexDump(_ bytes: [UInt8], around offset: Int, span: Int = 16) -> String {
        let lo = max(0, offset - span / 2)
        let hi = min(bytes.count, lo + span)
        return bytes[lo..<hi].map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    // MARK: - XD

    func testXDSavesRoundTripLosslessly() throws {
        let files = [
            "01-GXXE-PokemonXD_A-O.gci",
            "01-GXXE-PokemonXD_A-O_Shinnies.gci",
            "01-GXXE-PokemonXD_P-Z_Shinnies.gci",
            "01-GXXE-PokemonXD_P-Z+UniqueShinnies.gci",
        ]
        var ran = 0
        for filename in files {
            guard let body = try loadGCIBody(filename) else { continue }
            ran += 1
            try roundTripXD(body: body, label: filename)
        }
        try XCTSkipIf(ran == 0, "No XD GCIs found in \(downloads)")
    }

    private func roundTripXD(body: GoDData, label: String) throws {
        let card = try GSSaveCardFile(body: body)
        let origA = card.slotA, origB = card.slotB

        // Original decrypted plaintexts + latest detection.
        let plainA = GoDData(byteStream: origA.rawBytes, byteOrder: .big)
        let plainB = GoDData(byteStream: origB.rawBytes, byteOrder: .big)
        _ = try XDSaveCipher.decrypt(slot: plainA)
        _ = try XDSaveCipher.decrypt(slot: plainB)
        let slotA = try XDSaveSlot(raw: plainA)
        let slotB = try XDSaveSlot(raw: plainB)
        let latestIsA = slotA.header.counter >= slotB.header.counter

        // Project + unpacked slots.
        let fst = InMemoryFST()
        let engineFolder = installEngine(try XDEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        let unpacked = Folder("/project/Unpacked")
        try fst.writeFile(origA, at: unpacked.file("slot-a.bin"), overwrite: true)
        try fst.writeFile(origB, at: unpacked.file("slot-b.bin"), overwrite: true)

        // Dump then build (no edits).
        let out = Folder("/project/Save")
        try XDSaveOps.dump(config: .init(operations: [.init(operation: .dumpXDSave(
            unpackedFolder: unpacked, outputFolder: out, overwrite: true, decrypted: false, xdEngine: engineFolder), enabled: .yes)]),
            settings: .default, fileSystem: fst, logger: SilentLogger())
        try XDSaveOps.build(config: .init(operations: [.init(operation: .buildXDSave(
            inputFolder: out, unpackedFolder: unpacked, overwrite: true, decrypted: false, xdEngine: engineFolder), enabled: .yes)]),
            settings: .default, fileSystem: fst, logger: SilentLogger())

        // Non-latest slot: encrypted bytes must be untouched.
        let nonLatestName = latestIsA ? "slot-b.bin" : "slot-a.bin"
        let nonLatestOrig = latestIsA ? origB : origA
        let nonLatest = try XCTUnwrap(fst.readFile(at: unpacked.file(nonLatestName)))
        XCTAssertEqual(nonLatest.rawBytes, nonLatestOrig.rawBytes, "\(label): non-latest slot must pass through unchanged")

        // Latest slot: rebuilt from scratch. It won't be byte-identical
        // to the original — the inter-sub-block gaps + unused tail are
        // deliberately zeroed (non-semantic leftover the game itself
        // carries forward and re-randomises). Assert functional
        // losslessness instead: the checksum validates, the header region
        // matches, and every sub-block is byte-identical.
        let latestName = latestIsA ? "slot-a.bin" : "slot-b.bin"
        let origSlot = latestIsA ? slotA : slotB
        let origPlain = origSlot.raw.rawBytes
        let rebuilt = try XCTUnwrap(fst.readFile(at: unpacked.file(latestName)))
        let rebuiltData = GoDData(byteStream: rebuilt.rawBytes, byteOrder: .big)
        XCTAssertTrue(try XDSaveCipher.decrypt(slot: rebuiltData), "\(label): rebuilt checksum must validate")
        let rebuiltPlain = rebuiltData.rawBytes

        // Header region 0x00..0xA8 (magic, counter, seed, TOC, sizes) identical.
        XCTAssertEqual(
            Array(rebuiltPlain[0..<XDSaveSlot.subBlockBaseOffset]),
            Array(origPlain[0..<XDSaveSlot.subBlockBaseOffset]),
            "\(label): header region must match"
        )

        // Every sub-block byte-identical (all meaningful save data).
        for t in origSlot.sectionsInPlacementOrder() {
            let range = t.offset..<(t.offset + t.size)
            XCTAssertEqual(
                Array(rebuiltPlain[range]), Array(origPlain[range]),
                "\(label): sub-block \(t.index) @0x\(String(t.offset, radix: 16)) (size 0x\(String(t.size, radix: 16))) must match"
            )
        }
    }

    // MARK: - Colo

    func testColoSaveRoundTripsLosslessly() throws {
        guard let body = try loadGCIBody("01-GC6E-pokemon_colosseum_02.gci") else {
            throw XCTSkip("Colo GCI not found in \(downloads)")
        }
        let card = try ColoSaveCardFile(body: body)
        let encSlots = card.slots

        // Original decrypted plaintexts + latest detection.
        var plains: [[UInt8]] = []
        var counters: [UInt32] = []
        for enc in encSlots {
            let p = GoDData(byteStream: enc.rawBytes, byteOrder: .big)
            _ = try ColoSaveCipher.decrypt(slot: p)
            plains.append(p.rawBytes)
            counters.append(try ColosseumSaveSlot(raw: p).header.counter)
        }
        let latestIndex = counters.enumerated().max { $0.element < $1.element }?.offset ?? 0

        let fst = InMemoryFST()
        let engineFolder = installEngine(try ColosseumEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        let unpacked = Folder("/project/Unpacked")
        for (i, enc) in encSlots.enumerated() {
            try fst.writeFile(enc, at: unpacked.file("slot-\(i + 1).bin"), overwrite: true)
        }

        let out = Folder("/project/Save")
        try ColoSaveOps.dump(config: .init(operations: [.init(operation: .dumpColosseumSave(
            unpackedFolder: unpacked, outputFolder: out, overwrite: true, decrypted: false, colosseumEngine: engineFolder), enabled: .yes)]),
            settings: .default, fileSystem: fst, logger: SilentLogger())
        try ColoSaveOps.build(config: .init(operations: [.init(operation: .buildColosseumSave(
            inputFolder: out, unpackedFolder: unpacked, overwrite: true, decrypted: false, colosseumEngine: engineFolder), enabled: .yes)]),
            settings: .default, fileSystem: fst, logger: SilentLogger())

        for i in 0..<ColoSaveCardFile.slotCount where i != latestIndex {
            let passthrough = try XCTUnwrap(fst.readFile(at: unpacked.file("slot-\(i + 1).bin")))
            XCTAssertEqual(passthrough.rawBytes, encSlots[i].rawBytes, "non-latest slot \(i + 1) must pass through unchanged")
        }

        let rebuilt = try XCTUnwrap(fst.readFile(at: unpacked.file("slot-\(latestIndex + 1).bin")))
        let rebuiltPlain = GoDData(byteStream: rebuilt.rawBytes, byteOrder: .big)
        let result = try ColoSaveCipher.decrypt(slot: rebuiltPlain)
        XCTAssertTrue(result.headerValid && result.bodyValid, "rebuilt Colo checksums must validate")

        if let diff = firstDivergence(plains[latestIndex], rebuiltPlain.rawBytes) {
            XCTFail("""
                Colo latest slot NOT byte-identical after round-trip.
                first diff at 0x\(String(diff, radix: 16))
                  orig:    \(hexDump(plains[latestIndex], around: diff))
                  rebuilt: \(hexDump(rebuiltPlain.rawBytes, around: diff))
                """)
        }
    }
}
