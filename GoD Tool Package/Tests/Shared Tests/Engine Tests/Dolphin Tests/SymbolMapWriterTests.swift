import XCTest
import Foundation
import GoDFoundation
import Dolphin

/// A rebuilt DOL moves symbols, so the assembly has to write the map back
/// out. Anything the writer drops, the next disassembly loses: the size
/// and object-file columns decide how text is split into per-object
/// folders, and the section headers are what a reader navigates by.
final class SymbolMapWriterTests: XCTestCase {

    private let sample = """
    .text section layout
    80003100 000000e4 80003100 0 __start\tos.a __start.o
    800031e4 00000050 800031e4 0 __init_registers\tos.a __start.o
    80003234 0000002c 80003234 0 memcpy\truntime.a mem.o

    .data section layout
    80004000 00000020 80004000 0 lbl_80004000
    80004020 00000010 80004020 0 someTable\tfight.a fightPokemon.o
    """

    func testAMapSurvivesParseAndRewrite() {
        let parsed = SymbolMapParser().parse(sample)
        XCTAssertEqual(parsed.count, 5)

        let order = parsed.reduce(into: [String]()) { order, symbol in
            if let section = symbol.section, !order.contains(section) { order.append(section) }
        }
        let rewritten = SymbolMapWriter().write(parsed, sectionOrder: order)
        let reparsed = SymbolMapParser().parse(rewritten)

        XCTAssertEqual(reparsed.map(\.name), parsed.map(\.name))
        XCTAssertEqual(reparsed.map(\.address), parsed.map(\.address))
        XCTAssertEqual(reparsed.map(\.size), parsed.map(\.size))
        XCTAssertEqual(reparsed.map(\.section), parsed.map(\.section))
        XCTAssertEqual(reparsed.map(\.sourceFile), parsed.map(\.sourceFile))
    }

    func testTheObjectFileColumnSurvives() {
        let rewritten = SymbolMapWriter().write(SymbolMapParser().parse(sample), sectionOrder: [".text", ".data"])
        let reparsed = SymbolMapParser().parse(rewritten)
        // It's what puts a function in `text1/fightPokemon/` rather than
        // loose in the section folder.
        XCTAssertEqual(reparsed.first(where: { $0.name == "someTable" })?.objectFileName, "fightPokemon")
    }

    func testSectionHeadersFollowTheOrderGiven() {
        let rewritten = SymbolMapWriter().write(
            SymbolMapParser().parse(sample), sectionOrder: [".data", ".text"]
        )
        let dataHeader = try? XCTUnwrap(rewritten.range(of: ".data section layout"))
        let textHeader = try? XCTUnwrap(rewritten.range(of: ".text section layout"))
        XCTAssertNotNil(dataHeader)
        XCTAssertNotNil(textHeader)
        if let d = dataHeader, let t = textHeader {
            XCTAssertTrue(d.lowerBound < t.lowerBound, "the caller's order decides, not the addresses")
        }
    }

    func testSymbolsWithNoSectionComeFirstAndNeedNoHeader() {
        let symbols = [
            PPCSymbol(name: "loose", address: 0x8000_0000, size: 4),
            PPCSymbol(name: "inText", address: 0x8000_3100, size: 4, section: ".text"),
        ]
        let rewritten = SymbolMapWriter().write(symbols, sectionOrder: [".text"])
        let lines = rewritten.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.first?.contains("loose") == true, "got:\n\(rewritten)")
        XCTAssertEqual(SymbolMapParser().parse(rewritten).map(\.name), ["loose", "inText"])
    }

    func testSymbolsAreWrittenInAddressOrderWithinASection() {
        let symbols = [
            PPCSymbol(name: "third", address: 0x8000_0300, size: 4, section: ".text"),
            PPCSymbol(name: "first", address: 0x8000_0100, size: 4, section: ".text"),
            PPCSymbol(name: "second", address: 0x8000_0200, size: 4, section: ".text"),
        ]
        let rewritten = SymbolMapWriter().write(symbols, sectionOrder: [".text"])
        XCTAssertEqual(SymbolMapParser().parse(rewritten).map(\.name), ["first", "second", "third"])
    }
}
