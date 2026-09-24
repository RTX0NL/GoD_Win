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
        XCTAssertEqual(try length("ShadowPokemonStatus"), 0x48)
        XCTAssertEqual(try length("XDMemoEntry"), 0xC)
        XCTAssertEqual(try length("XDBattleRule"), 0x90)
    }

    /// Section 7 is a run of 128 Shadow Pokémon status records — 128 ×
    /// 0x48 must equal the real on-card section size (0x2400) for the
    /// table dump to tile exactly.
    func testShadowStatusTableTilesSection7() throws {
        XCTAssertEqual(try length("ShadowPokemonStatus") * 128, 0x2400, "section 7 ShadowStatusTable")
    }

    /// Each bound section struct must equal its real on-card section
    /// size, or the dump falls back to raw `.bin`.
    func testSectionStructsTileRealSizes() throws {
        XCTAssertEqual(try length("XDSaveConfig"), 0x88, "section 0 Config")
        XCTAssertEqual(try length("XDSaveTrainer"), 0x978, "section 1 Trainer")
        XCTAssertEqual(try length("XDSavePCBox"), 0xBC50, "section 2 PCBox")
        XCTAssertEqual(try length("XDBox"), 0x170C, "one PC box")
        XCTAssertEqual(try length("XDSaveDaycare"), 0xCC, "section 4 Daycare")
        XCTAssertEqual(try length("XDSaveStrategyMemo"), 0x1774, "section 5 StrategyMemo")
        XCTAssertEqual(try length("XDSaveBattleMode"), 0x364, "section 6 BattleMode")
    }

    // MARK: - Sections identified from the savedata BIOS

    /// The four sections that used to dump as opaque `.bin`. Sizes are the
    /// capacities `_memcardStoreSaveData_multi` clamps each memcpy to, and
    /// the same values the slot header's size table carries on every real
    /// save of every region — so these are the tiling contract for them.
    func testBiosIdentifiedSectionStructsTileRealSizes() throws {
        XCTAssertEqual(try length("XDSaveMailbox"), 0x4A, "section 3 Mailbox")
        XCTAssertEqual(try length("XDSaveFlags"), 0x6B4, "section 8 Flags")
        XCTAssertEqual(try length("XDSaveExRibbon"), 0xB, "section 9 ExRibbon")
        XCTAssertEqual(try length("XDSaveRelive"), 0x2298, "section 14 Purify Chamber")
    }

    /// `getStage__11CReliveHallFl` strides sets by 0x3D8 and
    /// `getReliveGiveStageQuantity` walks exactly 9 of them, which has to
    /// come out at the section size to the byte.
    func testPurifyChamberGeometry() throws {
        let stage = try length("XDReliveStage")
        XCTAssertEqual(stage, 0x3D8, "one Purify Chamber set")
        XCTAssertEqual(stage * 9, 0x2298, "9 sets tile section 14")
        // 4 dancers + the centre Pokémon, all at the 0xC4 `XDPokemon`
        // stride `pokemonInitAry` uses — the visitor sits at +0x310.
        let mon = try length("XDPokemon")
        XCTAssertEqual(mon, 0xC4)
        XCTAssertEqual(mon * 4, 0x310, "visitor offset is 4 dancers in")
        XCTAssertEqual(stage - mon * 5, 4, "one signed dancer index plus 3 unknown bytes")
    }

    /// Section 8 is five separate banks written back to back, not one
    /// blob. The piece sizes come from the slot header (+0x80…+0x8A) and
    /// are 0x20/0x80/0x600/8/8 on every real save; the serializer writes
    /// 0x6B0 of the 0x6B4 the section reserves.
    func testFlagBankSizesSumToTheWrittenRegion() throws {
        let definition = try XDEngine.defaults().getStruct("XDSaveFlags") as StructDefinition
        func bank(_ name: String) throws -> Int {
            let property = try XCTUnwrap(definition.properties.first { $0.name == name },
                                         "XDSaveFlags is missing \(name)")
            return property.type.length
        }
        XCTAssertEqual(try bank("flagLevel0"), 0x20)
        XCTAssertEqual(try bank("flagLevel1"), 0x80)
        XCTAssertEqual(try bank("flagLevel2"), 0x600, "the bank is 0x600; the section's 0x630 is 0x600 flags + tail")
        XCTAssertEqual(try bank("battleDiskSellOut"), 8)
        XCTAssertEqual(try bank("bingo"), 8)
        let written = try bank("flagLevel0") + bank("flagLevel1") + bank("flagLevel2")
            + bank("battleDiskSellOut") + bank("bingo")
        XCTAssertEqual(written, 0x6B0, "what the serializer actually copies")
        XCTAssertEqual(written + (try bank("unknown1")), 0x6B4, "the section the header reserves")
    }

    // MARK: - Japanese build

    /// XD released in Japan first and the international builds widened four
    /// save sections. Sizes are the JP save's own TOC, from the save audit
    /// corpus; binding the international structs to a JP save costs those
    /// sections their editable JSON (PCBox above all), so these lengths are
    /// the JP tiling contract.
    func testJapaneseSectionStructsTileRealSizes() throws {
        XCTAssertEqual(try length("XDSaveConfigJP"), 0x80, "JP section 0 Config")
        XCTAssertEqual(try length("XDSavePCBoxJP"), 0xBC0C, "JP section 2 PCBox")
        XCTAssertEqual(try length("XDSaveBattleModeJP"), 0x2EC, "JP section 6 BattleMode")
        XCTAssertEqual(try length("XDBattleRuleJP"), 0x7C, "one JP battle rule")
        XCTAssertEqual(try length("ShadowPokemonStatusJP") * 128, 0x1E00, "JP section 7 ShadowStatusTable")
    }

    /// Only the four widened sections differ: the rest of the save is one
    /// layout on every build, so both engines must bind them to the same
    /// struct. (`Trainer` is the notable one — its 11-unit player names are
    /// international-width even on a JP save.)
    func testJapaneseEngineBindsOnlyTheDivergentSectionsToJPStructs() throws {
        let intl = try XDEngine.defaultEngine(forGameID: PokemonXD.gameIDUS).data.sectionStructTypes
        let jp = try XDEngine.defaultEngine(forGameID: PokemonXD.gameIDJP).data.sectionStructTypes
        XCTAssertEqual(intl, XDEngine.Data().sectionStructTypes, "a non-JP build keeps the default bindings")
        XCTAssertEqual(Set(intl.keys), Set(jp.keys), "both builds bind the same section indices")
        let differing = jp.filter { intl[$0.key] != $0.value }.keys.sorted()
        XCTAssertEqual(differing, [0, 2, 6, 7], "only Config, PCBox, BattleMode and ShadowStatusTable differ")
        for index in differing {
            XCTAssertTrue(jp[index]!.hasSuffix("JP"), "section \(index) must bind a JP struct")
        }
    }

    /// An unknown game ID must not silently get the JP layout.
    func testUnknownGameIDFallsBackToTheInternationalBindings() throws {
        let unknown = try XDEngine.defaultEngine(forGameID: "XXXX").data.sectionStructTypes
        XCTAssertEqual(unknown, XDEngine.Data().sectionStructTypes)
    }
}
