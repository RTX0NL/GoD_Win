//
//  PPCFunctionSplitTests.swift
//
//  splitByFunction must tile the section exactly: overlapping map sizes
//  must not duplicate instructions, gaps must not drop them, and bytes
//  before the first symbol must still be emitted.
//

import XCTest
@testable import Dolphin
@testable import GoDFoundation

final class PPCFunctionSplitTests: XCTestCase {

    let decoder = PPCDecoder()
    let formatter = PPCFormatter()

    func testOverlappingSizesAndPreambleTileExactly() {
        // 8 × blr at 0x80003100..0x8000311C
        var bytes = [UInt8]()
        for _ in 0..<8 { bytes.append(contentsOf: [0x4E, 0x80, 0x00, 0x20]) }
        let instructions = decoder.decodeAll(bytes, baseAddress: 0x80003100)

        // First symbol starts 8 bytes in (preamble needed); A's declared
        // size (12) overlaps B's start; B has size 0.
        let symbols = [
            PPCSymbol(name: "funcA", address: 0x80003108, size: 12),
            PPCSymbol(name: "funcB", address: 0x80003110, size: 0),
        ]

        let functions = formatter.splitByFunction(instructions, symbols: symbols, sectionName: ".text0")
        XCTAssertEqual(functions.map(\.name), ["lbl_80003100", "funcA", "funcB"])

        let counts = functions.map { $0.text.components(separatedBy: "blr").count - 1 }
        XCTAssertEqual(counts, [2, 2, 4], "chunks must tile the section: no duplication, no drops")
    }

    func testDuplicateAddressSymbolsEmitOnce() {
        var bytes = [UInt8]()
        for _ in 0..<2 { bytes.append(contentsOf: [0x4E, 0x80, 0x00, 0x20]) }
        let instructions = decoder.decodeAll(bytes, baseAddress: 0x80003100)
        let symbols = [
            PPCSymbol(name: "first", address: 0x80003100, size: 8),
            PPCSymbol(name: "second", address: 0x80003100, size: 8),
        ]
        let functions = formatter.splitByFunction(instructions, symbols: symbols, sectionName: ".text0")
        XCTAssertEqual(functions.count, 1)
        XCTAssertEqual(functions[0].text.components(separatedBy: "blr").count - 1, 2)
    }
}
