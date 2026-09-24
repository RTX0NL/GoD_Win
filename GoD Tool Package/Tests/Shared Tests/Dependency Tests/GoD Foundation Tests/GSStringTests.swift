//
//  GSStringTests.swift
//  
//
//  Created by Stars Momodu on 30/05/2022.
//

import Foundation

import XCTest
@testable import GoDFoundation

class GSStringTests: XCTestCase {
 
    func testLiteral() {
        let sut: GSString = "Test String 1"
        XCTAssertEqual(sut.string(format: .utf8), "Test String 1")
    }
    
    func testSpecial() {
        let sut: GSString = "Test\nline"
        XCTAssertEqual(sut.count, 9)
        let sut2: GSString = "Test{00 00 00 00 00 00}line"
        XCTAssertEqual(sut2.count, 9)
        let sut3: GSString = GSString(string: "Test{Battle Player}line", format: .gsColo)
        XCTAssertEqual(sut3.count, 9)
    }
    
    func testNewLine() {
        let sut: GSString = GSString(string: "\n", format: .gsColo)
        let sut2: GSString = GSString(string: "\n", format: .gsXD)
        let sut3: GSString = GSString(string: "\n", format: .gsPBR)
        let sut4: GSString = GSString(string: "\n", format: .gs)
//        XCTAssertEqual(sut.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x00])
//        XCTAssertEqual(sut2.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x00])
//        XCTAssertEqual(sut3.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0xFF, 0xFE])
        XCTAssertEqual(sut4.rawData(byteOrder: .big).rawBytes, [0x00, 0x0A])
        XCTAssertEqual(sut.string(format: .gsColo), "\n")
        XCTAssertEqual(sut2.string(format: .gsXD), "\n")
        XCTAssertEqual(sut3.string(format: .gsPBR), "\n")
        XCTAssertEqual(sut4.string(format: .gs), "\n")
        
        let sut5 = GSString(characters: [.special([0x00])])
        let sut6 = GSString(characters: [.special([0xFF, 0xFE])])
        XCTAssertEqual(sut5.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x00])
        XCTAssertEqual(sut6.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0xFF, 0xFE])
        XCTAssertEqual(sut5.string(format: .gsColo), "\n")
        XCTAssertEqual(sut5.string(format: .gsXD), "\n")
        XCTAssertEqual(sut6.string(format: .gsPBR), "\n")
        XCTAssertEqual(sut5.string(format: .gs), "{00}")
    }
    
    func testClear() {
        let sut: GSString = GSString(string: "{Clear}", format: .gsColo)
        let sut2: GSString = GSString(string: "{Clear}", format: .gsXD)
        let sut3: GSString = GSString(string: "{Clear}", format: .gs)
        XCTAssertEqual(sut.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x03])
        XCTAssertEqual(sut2.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x03])
        XCTAssertEqual(sut.string(format: .gsColo), "{Clear}")
        XCTAssertEqual(sut2.string(format: .gsXD), "{Clear}")
        XCTAssertEqual(sut3.string(format: .gs), "")
        
        let sut4 = GSString(characters: [.special([0x03])])
        XCTAssertEqual(sut4.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x03])
        XCTAssertEqual(sut4.string(format: .gsColo), "{Clear}")
        XCTAssertEqual(sut4.string(format: .gsXD), "{Clear}")
        XCTAssertEqual(sut4.string(format: .gs), "{03}")
    }
    
    func testFontBold() {
        let sut: GSString = GSString(string: "{Font Bold}", format: .gsColo)
        let sut2: GSString = GSString(string: "{Font Bold}", format: .gsXD)
        let sut3: GSString = GSString(string: "{Font Bold}", format: .gs)
        XCTAssertEqual(sut.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x07, 0x01])
        XCTAssertEqual(sut2.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x07, 0x01])
        XCTAssertEqual(sut.string(format: .gsColo), "{Font Bold}")
        XCTAssertEqual(sut2.string(format: .gsXD), "{Font Bold}")
        XCTAssertEqual(sut3.string(format: .gs), "")
        
        let sut4 = GSString(characters: [.special([0x07, 0x01])])
        XCTAssertEqual(sut4.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x07, 0x01])
        XCTAssertEqual(sut4.string(format: .gsColo), "{Font Bold}")
        XCTAssertEqual(sut4.string(format: .gsXD), "{Font Bold}")
        XCTAssertEqual(sut4.string(format: .gs), "{07 01}")
    }
    
    func testFontRegular() {
        let sut: GSString = GSString(string: "{Font Regular}", format: .gsColo)
        let sut2: GSString = GSString(string: "{Font Regular}", format: .gsXD)
        let sut3: GSString = GSString(string: "{Font Regular}", format: .gs)
        XCTAssertEqual(sut.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x07, 0x03])
        XCTAssertEqual(sut2.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x07, 0x03])
        XCTAssertEqual(sut.string(format: .gsColo), "{Font Regular}")
        XCTAssertEqual(sut2.string(format: .gsXD), "{Font Regular}")
        XCTAssertEqual(sut3.string(format: .gs), "")
        
        let sut4 = GSString(characters: [.special([0x07, 0x03])])
        XCTAssertEqual(sut4.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x07, 0x03])
        XCTAssertEqual(sut4.string(format: .gsColo), "{Font Regular}")
        XCTAssertEqual(sut4.string(format: .gsXD), "{Font Regular}")
        XCTAssertEqual(sut4.string(format: .gs), "{07 03}")
    }
    
    func testFontSuperscript1() {
        let sut: GSString = GSString(string: "{Font Super 1}", format: .gsColo)
        let sut2: GSString = GSString(string: "{Font Super 1}", format: .gsXD)
        let sut3: GSString = GSString(string: "{Font Super 1}", format: .gs)
        XCTAssertEqual(sut.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x07, 0x02])
        XCTAssertEqual(sut2.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x07, 0x02])
        XCTAssertEqual(sut.string(format: .gsColo), "{Font Super 1}")
        XCTAssertEqual(sut2.string(format: .gsXD), "{Font Super 1}")
        XCTAssertEqual(sut3.string(format: .gs), "")
        
        let sut4 = GSString(characters: [.special([0x07, 0x02])])
        XCTAssertEqual(sut4.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x07, 0x02])
        XCTAssertEqual(sut4.string(format: .gsColo), "{Font Super 1}")
        XCTAssertEqual(sut4.string(format: .gsXD), "{Font Super 1}")
        XCTAssertEqual(sut4.string(format: .gs), "{07 02}")
    }
    
    func testFontSuperscript2() {
        let sut: GSString = GSString(string: "{Font Super 2}", format: .gsColo)
        let sut2: GSString = GSString(string: "{Font Super 2}", format: .gsXD)
        let sut3: GSString = GSString(string: "{Font Super 2}", format: .gs)
        XCTAssertEqual(sut.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x07, 0x04])
        XCTAssertEqual(sut2.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x07, 0x04])
        XCTAssertEqual(sut.string(format: .gsColo), "{Font Super 2}")
        XCTAssertEqual(sut2.string(format: .gsXD), "{Font Super 2}")
        XCTAssertEqual(sut3.string(format: .gs), "")
        
        let sut4 = GSString(characters: [.special([0x07, 0x04])])
        XCTAssertEqual(sut4.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x07, 0x04])
        XCTAssertEqual(sut4.string(format: .gsColo), "{Font Super 2}")
        XCTAssertEqual(sut4.string(format: .gsXD), "{Font Super 2}")
        XCTAssertEqual(sut4.string(format: .gs), "{07 04}")
    }
    
    func testColor() {
        let sut: GSString = GSString(string: "{Color: #A0CFB8}", format: .gsColo)
        let sut2: GSString = GSString(string: "{Color: #A0CFB8}", format: .gsXD)
        let sut3: GSString = GSString(string: "{Color: #A0CFB8}", format: .gs)
        XCTAssertEqual(sut.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x08, 0xA0, 0xCF, 0xB8, 0xFF])
        XCTAssertEqual(sut2.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x08, 0xA0, 0xCF, 0xB8, 0xFF])
        XCTAssertEqual(sut.string(format: .gsColo), "{Color: #A0CFB8}")
        XCTAssertEqual(sut2.string(format: .gsXD), "{Color: #A0CFB8}")
        XCTAssertEqual(sut3.string(format: .gs), "")
        
        let sut4 = GSString(characters: [.special([0x08, 0xA0, 0xCF, 0xB8, 0xFF])])
        XCTAssertEqual(sut4.rawData(byteOrder: .big).rawBytes, [0xFF, 0xFF, 0x08, 0xA0, 0xCF, 0xB8, 0xFF])
        XCTAssertEqual(sut4.string(format: .gsColo), "{Color: #A0CFB8}")
        XCTAssertEqual(sut4.string(format: .gsXD), "{Color: #A0CFB8}")
        XCTAssertEqual(sut4.string(format: .gs), "{08 A0 CF B8 FF}")
    }

    // MARK: - PBR furigana

    /// A furigana marker carries two counts — kana first, kanji second — and
    /// the characters follow in that order. Reading them the other way round
    /// takes the wrong number of trailing characters whenever the two counts
    /// differ, which is every real annotation of more than one kanji.
    private static let furiganaBytes: [UInt8] = [
        0xFF, 0xFF, 0x00, 0x01,     // furigana marker
        0x02,                       // 2 kana
        0x03,                       // 3 kanji
        0x30, 0x51, 0x30, 0x93,     // けん
        0x52, 0x63, 0x5C, 0x71, 0x5D, 0xDD  // 剣山川
    ]

    func testPBRFuriganaReadsKanaThenKanji() {
        let data = GoDData(byteStream: Self.furiganaBytes + [0xFF, 0xFF, 0xFF, 0xFF], byteOrder: .big)
        let read = data.readGSString(atAddress: 0, format: .gsPBR)
        XCTAssertEqual(read?.string(format: .gsPBR), "{Furigana:けん:剣山川}")
        XCTAssertEqual(read?.rawData(byteOrder: .big).rawBytes, Self.furiganaBytes)
    }

    func testPBRFuriganaWritesKanaThenKanji() {
        let sut = GSString(string: "{Furigana:けん:剣山川}", format: .gsPBR)
        XCTAssertEqual(sut.rawData(byteOrder: .big).rawBytes, Self.furiganaBytes)
        XCTAssertEqual(sut.string(format: .gsPBR), "{Furigana:けん:剣山川}")
    }

    /// A marker's characters can be spaces — 58 of the JP disc's are — so the
    /// separator has to be something they never contain. None of the 6,441
    /// markers on the disc holds a colon; one that did would fall back to raw
    /// bytes rather than round-trip wrongly.
    func testPBRFuriganaSurvivesSpacesAsItsCharacters() {
        let bytes: [UInt8] = [
            0xFF, 0xFF, 0x00, 0x01, 0x01, 0x01,
            0x00, 0x20,             // kana: an ASCII space
            0x30, 0x00,             // kanji: an ideographic space
        ]
        let data = GoDData(byteStream: bytes + [0xFF, 0xFF, 0xFF, 0xFF], byteOrder: .big)
        let read = try? XCTUnwrap(data.readGSString(atAddress: 0, format: .gsPBR))
        XCTAssertEqual(read?.string(format: .gsPBR), "{Furigana: :\u{3000}}")
        XCTAssertEqual(read?.rawData(byteOrder: .big).rawBytes, bytes)
        XCTAssertEqual(
            GSString(string: "{Furigana: :\u{3000}}", format: .gsPBR)
                .rawData(byteOrder: .big).rawBytes,
            bytes
        )
    }

    func testPBRFuriganaSurvivesSurroundingText() {
        let bytes: [UInt8] = [0x00, 0x41] + Self.furiganaBytes + [0x00, 0x42, 0xFF, 0xFF, 0xFF, 0xFF]
        let data = GoDData(byteStream: bytes, byteOrder: .big)
        let read = data.readGSString(atAddress: 0, format: .gsPBR)
        XCTAssertEqual(read?.string(format: .gsPBR), "A{Furigana:けん:剣山川}B")
        XCTAssertEqual(read?.rawData(byteOrder: .big).rawBytes, Array(bytes.dropLast(4)))
    }
}
