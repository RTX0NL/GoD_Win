//
//  XDSaveStructTests.swift
//  XDTests
//
//  Pins the byte lengths of the XD save-section structs. A section
//  dumps as editable JSON only when its struct *exactly tiles* the real
//  on-card section size — so these lengths are the tiling contract.
//  Real on-card sizes are from a real A-O save's TOC.
//

import XCTest
import Structs
import GoDEngine
@testable import XD

final class XDSaveStructTests: XCTestCase {

    private func length(_ name: String) throws -> Int {
        try XDEngine.defaults().getStruct(name).length
    }

    func testPokemonSubStructLengths() throws {
        XCTAssertEqual(try length("XDWaza"), 0x4)
        XCTAssertEqual(try length("XDItem"), 0x4)
        XCTAssertEqual(try length("XDPokemon"), 0xC4)
        XCTAssertEqual(try length("XDDarkPokemon"), 0x48)
    }

    /// Section 7 is a run of 128 DarkPokemon records — 128 × 0x48 must
    /// equal the real on-card section size (0x2400) for the table dump
    /// to tile exactly.
    func testDarkPokemonTableTilesSection7() throws {
        XCTAssertEqual(try length("XDDarkPokemon") * 128, 0x2400, "section 7 Darkpokemon table")
    }

    /// Each bound section struct must equal its real on-card section
    /// size, or the dump falls back to raw `.bin`.
    func testSectionStructsTileRealSizes() throws {
        XCTAssertEqual(try length("XDSaveConfig"), 0x88, "section 0 Config")
        XCTAssertEqual(try length("XDSaveDaycare"), 0xCC, "section 4 Daycare")
        XCTAssertEqual(try length("XDSaveTrainer1"), 0x978, "section 1 Hero")
        XCTAssertEqual(try length("XDPCBox"), 0xBC50, "section 2 PCBox")
        XCTAssertEqual(try length("XDBox"), 0x170C, "one PC box")
    }
}
