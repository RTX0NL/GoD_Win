//
//  SymbolMapParserTests.swift
//
//  Symbol name sanitization: demangled C++ names must come out
//  assembly-safe or reassembly chokes on commas/brackets/spaces.
//

import XCTest
@testable import Dolphin

final class SymbolMapParserTests: XCTestCase {

    let parser = SymbolMapParser()

    func testDolphinFormatSanitizesTemplateNames() {
        let map = """
        .text section layout
        800e0238 0000002c 800e0238 0 Replayable<0,9SaveFrame,14RenderSnapshot>
        80005ce4 00000010 80005ce4 0 normal_name
        """
        let symbols = parser.parse(map)
        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols[0].name, "Replayable_0_9SaveFrame_14RenderSnapshot_")
        XCTAssertEqual(symbols[1].name, "normal_name")
    }

    func testSanitizeKeepsSafeCharactersAndGuardsLeadingDigit() {
        XCTAssertEqual(SymbolMapParser.sanitizeName("__start"), "__start")
        XCTAssertEqual(SymbolMapParser.sanitizeName("os.a$init"), "os.a$init")
        XCTAssertEqual(SymbolMapParser.sanitizeName("op<<(ostream&, int)"), "op___ostream___int_")
        XCTAssertEqual(SymbolMapParser.sanitizeName("4gpr_save"), "_4gpr_save")
    }

    func testDuplicateNamesAtDifferentAddressesAreUniquified() {
        // CodeWarrior local-literal names repeat across objects
        let map = """
        .sdata2 section layout
        804ebdc0 00000008 804ebdc0 0 @3097
        804ebe00 00000008 804ebe00 0 @3097
        804ebe40 00000004 804ebe40 0 @3097
        """
        let symbols = parser.parse(map)
        XCTAssertEqual(symbols.map(\.name), ["_3097", "_3097_804EBE00", "_3097_804EBE40"])
        // Case-only differences collide as filenames on macOS — uniquify too
        let caseDup = parser.parse("""
        .text section layout
        80050c90 00000038 80050c90 0 GetDarkPokemonID
        80050d6c 00000038 80050d6c 0 GetDarkpokemonID
        """)
        XCTAssertEqual(caseDup.map(\.name), ["GetDarkPokemonID", "GetDarkpokemonID_80050D6C"])
        // Same name at the SAME address stays as-is (harmless repeat)
        let dup = parser.parse("""
        .text section layout
        80003100 00000004 80003100 0 fn
        80003100 00000004 80003100 0 fn
        """)
        XCTAssertEqual(dup.map(\.name), ["fn", "fn"])
    }

    func testDtkFormatSanitizes() {
        let map = """
        vec<3,f32>::len = .text:0x80003100; // type:function size:0x20
        """
        let symbols = parser.parse(map)
        XCTAssertEqual(symbols.first?.name, "vec_3_f32___len")
        XCTAssertEqual(symbols.first?.address, 0x80003100)
    }
}
