//
//  ColoSaveStructTests.swift
//  ColosseumTests
//
//  Pins the byte lengths of the Colosseum save-section structs. Colo's
//  slot has no in-slot TOC — each section's offset/length is derived
//  purely from its struct binding, so these lengths ARE the on-card
//  section sizes. Real sizes are from a real Colosseum save.
//

import XCTest
import Structs
import GoDEngine
@testable import Colosseum

final class ColoSaveStructTests: XCTestCase {

    private func length(_ name: String) throws -> Int {
        try ColosseumEngine.defaults().getStruct(name).length
    }

    func testPokemonSubStructLengths() throws {
        XCTAssertEqual(try length("ColoWaza"), 0x4)
        XCTAssertEqual(try length("ColoPokemon"), 0x138, "CK3 stored Pokémon")
        XCTAssertEqual(try length("ColoMemoEntry"), 0xC)
    }

    /// Each section struct must equal its real on-card section size, or
    /// the derived offsets desync and the slot can't be reassembled.
    func testSectionStructsTileRealSizes() throws {
        XCTAssertEqual(try length("ColoSaveConfig"), 0x70, "section 0 Config")
        XCTAssertEqual(try length("ColoSaveTrainer"), 0xB18, "section 1 Trainer")
        XCTAssertEqual(try length("ColoBox"), 0x24A4, "one PC box")
        XCTAssertEqual(try length("ColoSavePCBox"), 0x6DEC, "section 2 PCBox")
        XCTAssertEqual(try length("ColoSaveBattleMode"), 0x7F4, "section 3 BattleMode")
        XCTAssertEqual(try length("ColoSaveDaycare"), 0x140, "section 4 Daycare")
        XCTAssertEqual(try length("ColoSaveStrategyMemo"), 0xB10, "section 5 StrategyMemo")
        XCTAssertEqual(try length("ColoSaveTail"), 0x15240, "section 6 Tail")
    }
}
