//
//  PBRStringDirectoryNamingTests.swift
//  PBRTests
//
//  Pins the string directory's project filename to the naming the unpack
//  actually uses.
//
//  `PBREngine.Data.stringDirectoryFileName` spells out `common_091.bin` so
//  project setup can name the file without loading an archive registry. That
//  spelling is the Genius Sonority unpack's, not PBR's, so the two are
//  checked against each other here — if the unpack's convention moves, the
//  generated config would otherwise point at a file that no longer exists
//  and the strings dump would fail on a fresh project.
//

import XCTest
import GoDFoundation
import GeniusSonority
@testable import PBR

final class PBRStringDirectoryNamingTests: XCTestCase {

    private func unpackName(forMemberAt index: Int) -> String {
        let engine = GeniusSonorityEngine.defaultEngine(for: .battleRevolution)
        let placeholder = engine.data.fsys.scrubbedFilenamePlaceholderValue
        // Every PBR entry is nameless, so the unpack names it after the
        // archive it came from plus its index.
        return engine.projectFilename(
            forEntryNamed: placeholder,
            filename: placeholder + ".bin",
            index: index,
            archiveName: "common"
        )
    }

    func testDirectoryFileNameMatchesTheUnpacksNaming() {
        let data = PBREngine.Data()
        XCTAssertEqual(
            data.stringDirectoryFileName(japanese: false),
            unpackName(forMemberAt: data.stringDirectoryIndex)
        )
        XCTAssertEqual(
            data.stringDirectoryFileName(japanese: true),
            unpackName(forMemberAt: data.japaneseStringDirectoryIndex)
        )
    }

    func testDirectoryIndexesAreTheOnesTheDiscsUse() {
        let data = PBREngine.Data()
        // US/PAL and JP order `common.fsys` differently; these two indexes
        // are from the legacy tool's `PBRStringManager`, and the corpus test
        // checks whichever one is present actually parses.
        XCTAssertEqual(data.stringDirectoryIndex, 91)
        XCTAssertEqual(data.japaneseStringDirectoryIndex, 119)
        XCTAssertEqual(data.stringDirectoryFileName(japanese: false), "common_091.bin")
        XCTAssertEqual(data.stringDirectoryFileName(japanese: true), "common_119.bin")
    }
}
