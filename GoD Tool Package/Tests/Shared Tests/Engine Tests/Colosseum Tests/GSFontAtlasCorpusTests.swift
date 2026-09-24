//
//  GSFontAtlasCorpusTests.swift
//  ColosseumTests
//
//  Every font on a dumped disc through the atlas and back, byte for byte.
//
//  The synthetic tests in `GSFontAtlasTests` pin the rules one at a time; this
//  one answers the question those rules came from — whether a real disc's
//  fonts survive the artifact a user edits. Three things had to be true for
//  that: cells sized to the glyphs rather than to the size the block header
//  declares, the column past an odd advance carried through the atlas, and a
//  PNG that reads back as what was written. The first two cost Colosseum US 2
//  of its 136 fonts and Colosseum JP 133 of its 137; the third cost JP one
//  more, and used to stop the font build at that one, leaving 103 unbuilt.
//
//  Skips without a dump. `GODDESS_FONT_CORPUS` points at a fonts folder.
//

import XCTest
import Foundation
import GoDFoundation
import GeniusSonority

final class GSFontAtlasCorpusTests: XCTestCase {

    private static let defaultCorpus =
        "/Users/stars/Documents/Projects/GoD-Tool/scripts/XD project/Build/Unpacked/Data/Text/Fonts"

    private func corpusFonts() throws -> [URL] {
        let path = ProcessInfo.processInfo.environment["GODDESS_FONT_CORPUS"] ?? Self.defaultCorpus
        let root = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("No font corpus at \(path) — set GODDESS_FONT_CORPUS to a dumped fonts folder.")
        }
        let found = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "fnt" }
            .sorted { $0.path < $1.path } ?? []
        guard !found.isEmpty else {
            throw XCTSkip("No .fnt files under \(path).")
        }
        return found
    }

    /// `.fnt` → atlas PNG + metadata → `.fnt`, byte-identical, for every font
    /// the corpus holds.
    func testEveryFontInTheCorpusSurvivesTheAtlas() throws {
        let fonts = try corpusFonts()
        var changed = [String]()
        var failed = [String]()

        for url in fonts {
            let name = url.lastPathComponent
            do {
                let original = GoDData(byteStream: Array(try Data(contentsOf: url)), byteOrder: .big)
                let font = try GSFont(data: original)
                let (image, metadata) = try GSFontAtlas.exportAtlas(font: font, atlasPath: "\(name).png")
                let rebuilt = try GSFontAtlas.importAtlas(imageData: image, metadata: metadata).font
                if try rebuilt.data.rawBytes != original.rawBytes { changed.append(name) }
            } catch {
                failed.append("\(name): \(error)")
            }
        }

        XCTAssertEqual(failed.count, 0, "fonts that wouldn't round trip at all: \(failed.prefix(6))")
        XCTAssertEqual(changed.count, 0,
                       "\(changed.count) of \(fonts.count) fonts came back changed: \(changed.prefix(6))")
    }
}
