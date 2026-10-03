//
//  PBRDeckStructTests.swift
//  PBRTests
//
//  Pins the deck.fsys struct strides and checks they tile the real decks:
//  a deck file is a 0x10 header (entry count at +0x08) then an entry array
//  that must divide evenly by the bound struct's length.
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import Structs
import GeniusSonority
@testable import PBR

final class PBRDeckStructTests: XCTestCase {

    private let structForType = ["dckp": "PBRPokemonDeck", "dckt": "PBRTrainerDeck", "dcka": "PBRAIDeck"]

    func testDeckStructStrides() throws {
        let engine = try PBREngine.defaults()
        XCTAssertEqual(try engine.getStruct("PBRDeckHeader").length, 0x10)
        XCTAssertEqual(try engine.getStruct("PBRTrainerDeck").length, 0x98)
        XCTAssertEqual(try engine.getStruct("PBRPokemonDeck").length, 0x38)
        XCTAssertEqual(try engine.getStruct("PBRAIDeck").length, 0x24)
    }

    func testDeckStructsTileRealDeckFsys() throws {
        let filesPath = ProcessInfo.processInfo.environment["GODDESS_PBR_FILES"]
            ?? "/Users/stars/Documents/Projects/GoD-Tool/scripts/PBR PAL project/Build/Contents/DATA/files"
        guard FileManager.default.fileExists(atPath: filesPath) else {
            throw XCTSkip("No unpacked PBR project — set GODDESS_PBR_FILES to run.")
        }
        let gs = GeniusSonorityEngine.defaultEngine(for: .battleRevolution)
        let engine = try PBREngine.defaults()
        let bytes = try XCTUnwrap(FileManager.default.contents(atPath: filesPath + "/deck.fsys"))
        let archive = try FSYSArchive(data: GoDData(data: bytes, byteOrder: .big), engine: gs)

        var checked = 0
        for entry in archive.entries {
            guard let fileType = entry.metadata.fileType,
                  let structName = structForType[fileType] else { continue }
            let stride = try engine.getStruct(structName).length
            let data = entry.data
            data.setByteOrder(.big)
            let count = Int(data.readSafely(atAddress: 0x08) as UInt32)
            XCTAssertEqual(0x10 + count * stride, data.length,
                           "\(fileType) (\(structName), stride \(stride)) tiles \(count) entries")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "found deck entries to check")
    }
}
