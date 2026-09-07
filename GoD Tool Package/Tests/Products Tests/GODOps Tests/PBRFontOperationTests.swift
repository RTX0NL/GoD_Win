//
//  PBRFontOperationTests.swift
//  GODOpsTests
//
//  Operation-body coverage for the PBR font dump/build pair, single and batch.
//
//  Everything runs against synthetic fonts built in memory, so these need no
//  ROM. The formats themselves are pinned against the real corpora by
//  `PBRFontTests` and `PBRFont3DTests`; what's under test here is the
//  *operation* — which files it picks up, where artifacts land, and that one
//  bad file doesn't cost the batch.
//

import XCTest
import Foundation
import GoDFoundation
import PBR
@testable import GODOps

final class PBRFontOperationTests: XCTestCase {

    // MARK: - Fixtures

    /// A small but structurally complete bitmap font.
    private func bitmapFont() -> PBRFont {
        PBRFont(blocks: [
            .init(language: "J", nominalSize: 32, glyphs: [
                .init(code: 0x41, width: 4, firstRow: 0, lastRow: 1,
                      lineHeight: 26, bitmap: [0x12, 0x34, 0x56, 0x78]),
            ]),
        ])
    }

    /// A 3D font with one square glyph, so the SVG path has real content.
    private func vectorFont() -> PBRFont3D {
        PBRFont3D(glyphs: [
            .init(code: 0x42, contours: [[
                .init(x: -100, y: -100), .init(x: 100, y: -100),
                .init(x: 100, y: 100), .init(x: -100, y: 100),
                .init(x: -100, y: -100),
            ]]),
        ])
    }

    private func tree() -> InMemoryFST { InMemoryFST() }

    private func write(_ font: PBRFont, at path: File, in fst: InMemoryFST) throws {
        try fst.writeFile(font.data, at: path, overwrite: true)
    }

    // MARK: - Single dump

    func testSingleDumpWritesArtifactsIntoAFolderNamedAfterTheFont() throws {
        let fst = tree()
        try write(bitmapFont(), at: File("/in/common_0033.FNT"), in: fst)

        try PBRFontDump.dump(
            config: .init(fontPath: File("/in/common_0033.FNT"),
                          outputFolder: Folder("/out"), overwrite: true),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        // A font produces several artifacts, so each gets its own subfolder —
        // otherwise two fonts dumped side by side would interleave.
        XCTAssertNotNil(fst.readFile(at: File("/out/common_0033/common_0033.fnt.json")))
        XCTAssertNotNil(fst.readFile(at: File("/out/common_0033/common_0033.fnt.png")))
    }

    /// `.f3d` goes through the same operation — the registry picks the codec
    /// from the extension, which is why one pair of ops covers both formats.
    func testSingleDumpHandlesTheVectorFontToo() throws {
        let fst = tree()
        try fst.writeFile(vectorFont().data, at: File("/in/fnt3dall.f3d"), overwrite: true)

        try PBRFontDump.dump(
            config: .init(fontPath: File("/in/fnt3dall.f3d"),
                          outputFolder: Folder("/out"), overwrite: true),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        XCTAssertNotNil(fst.readFile(at: File("/out/fnt3dall/fnt3dall.f3d.json")))
        XCTAssertNotNil(fst.readFile(at: File("/out/fnt3dall/fnt3dall.f3d.svg")))
    }

    func testSingleDumpThrowsWhenTheFontIsMissing() {
        XCTAssertThrowsError(
            try PBRFontDump.dump(
                config: .init(fontPath: File("/in/nope.FNT"),
                              outputFolder: Folder("/out"), overwrite: true),
                settings: .default, fileSystem: tree(), logger: SilentLogger()
            )
        )
    }

    // MARK: - Batch dump

    func testBatchDumpPicksUpBothFontFormatsAndMirrorsTheLayout() throws {
        let fst = tree()
        try write(bitmapFont(), at: File("/in/menu/a.FNT"), in: fst)
        try write(bitmapFont(), at: File("/in/b.fnt"), in: fst)
        try fst.writeFile(vectorFont().data, at: File("/in/c.f3d"), overwrite: true)
        // Not a font — must be ignored rather than attempted.
        try fst.writeFile(GoDData(byteStream: [UInt8](repeating: 0, count: 8), byteOrder: .big),
                          at: File("/in/notes.txt"), overwrite: true)

        let logger = RecordingLogger()
        try PBRFontDump.dump(
            config: .init(fontsFolder: Folder("/in"),
                          outputFolder: Folder("/out"), overwrite: true),
            settings: .default, fileSystem: fst, logger: logger
        )

        // Source layout is mirrored, so `menu/` survives into the artifacts.
        XCTAssertNotNil(fst.readFile(at: File("/out/menu/a/a.fnt.json")))
        XCTAssertNotNil(fst.readFile(at: File("/out/b/b.fnt.json")))
        XCTAssertNotNil(fst.readFile(at: File("/out/c/c.f3d.svg")))
        XCTAssertNil(fst.readFile(at: File("/out/notes/notes.txt.json")))
        XCTAssertTrue(logger.warnings.isEmpty, "got \(logger.warnings)")
    }

    /// The two `.fnt` formats reject each other by design, so a Genius
    /// Sonority font sitting in a PBR folder is a realistic input. It must
    /// cost that one file and nothing else.
    func testBatchDumpKeepsGoingPastAFileThatIsNotAPBRFont() throws {
        let fst = tree()
        try write(bitmapFont(), at: File("/in/good.FNT"), in: fst)
        // A GSFont block header, which `PBRFont` refuses.
        try fst.writeFile(
            GoDData(byteStream: [0x00, 0x00, 0x16, 0x16, 0x00, 0x00, 0x02, 0x70], byteOrder: .big),
            at: File("/in/genius.fnt"), overwrite: true
        )

        let logger = RecordingLogger()
        XCTAssertNoThrow(try PBRFontDump.dump(
            config: .init(fontsFolder: Folder("/in"),
                          outputFolder: Folder("/out"), overwrite: true),
            settings: .default, fileSystem: fst, logger: logger
        ))

        XCTAssertNotNil(fst.readFile(at: File("/out/good/good.fnt.json")),
                        "the healthy font must still be dumped")
        XCTAssertTrue(logger.warnings.contains { $0.contains("genius.fnt") },
                      "the bad file should be named; got \(logger.warnings)")
    }

    func testBatchDumpOnAMissingFolderWarnsAndReturns() {
        let logger = RecordingLogger()
        XCTAssertNoThrow(try PBRFontDump.dump(
            config: .init(fontsFolder: Folder("/nope"),
                          outputFolder: Folder("/out"), overwrite: true),
            settings: .default, fileSystem: tree(), logger: logger
        ))
        XCTAssertEqual(logger.warnings.count, 1)
        XCTAssertTrue(logger.warnings[0].contains("not found"))
    }

    // MARK: - Build

    /// The round trip that matters for the operation pair: dump then build
    /// must reproduce the original binary.
    func testSingleBuildReproducesTheFontBinary() throws {
        let fst = tree()
        let original = bitmapFont().data
        try fst.writeFile(original, at: File("/in/f.FNT"), overwrite: true)

        try PBRFontDump.dump(
            config: .init(fontPath: File("/in/f.FNT"),
                          outputFolder: Folder("/out"), overwrite: true),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        try PBRFontBuild.build(
            config: .init(fontFolder: Folder("/out/f"),
                          outputFolder: Folder("/rebuilt"), overwrite: true),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        let rebuilt = fst.readFile(at: File("/rebuilt/f.fnt"))?.allData
        XCTAssertEqual(rebuilt?.rawBytes, original.rawBytes)
    }

    func testBatchBuildWalksEveryBundle() throws {
        let fst = tree()
        try write(bitmapFont(), at: File("/in/one.FNT"), in: fst)
        try write(bitmapFont(), at: File("/in/two.FNT"), in: fst)
        try PBRFontDump.dump(
            config: .init(fontsFolder: Folder("/in"),
                          outputFolder: Folder("/out"), overwrite: true),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        try PBRFontBuild.build(
            config: .init(fontsFolder: Folder("/out"),
                          outputFolder: Folder("/rebuilt"), overwrite: true),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        XCTAssertNotNil(fst.readFile(at: File("/rebuilt/one.fnt")))
        XCTAssertNotNil(fst.readFile(at: File("/rebuilt/two.fnt")))
    }

    /// A folder with no manifest isn't a bundle. It should be named, not
    /// silently skipped and not fatal to the batch.
    func testBuildReportsAFolderThatIsNotABundle() throws {
        let fst = tree()
        try fst.writeFile(GoDData(byteStream: [UInt8](repeating: 0, count: 4), byteOrder: .big),
                          at: File("/out/stray/readme.txt"), overwrite: true)
        let logger = RecordingLogger()
        XCTAssertNoThrow(try PBRFontBuild.build(
            config: .init(fontsFolder: Folder("/out"),
                          outputFolder: Folder("/rebuilt"), overwrite: true),
            settings: .default, fileSystem: fst, logger: logger
        ))
        XCTAssertTrue(logger.warnings.contains { $0.contains("stray") },
                      "got \(logger.warnings)")
    }

    func testSingleBuildThrowsWhenTheBundleHasNoManifest() {
        XCTAssertThrowsError(
            try PBRFontBuild.build(
                config: .init(fontFolder: Folder("/nothing"),
                              outputFolder: Folder("/rebuilt"), overwrite: true),
                settings: .default, fileSystem: tree(), logger: SilentLogger()
            )
        ) { error in
            guard case PBRFontErrors.noFontManifest = error else {
                return XCTFail("Expected noFontManifest, got \(error)")
            }
        }
    }
}
