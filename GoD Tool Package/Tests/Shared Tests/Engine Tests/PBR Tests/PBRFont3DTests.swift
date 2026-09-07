//
//  PBRFont3DTests.swift
//  PBRTests
//
//  Two layers, following the project's encode/decode split:
//
//  1. Synthetic outlines built in memory, so the geometry rules are asserted
//     against a stated expectation rather than against the parser's own
//     output. These always run.
//  2. The two real `.f3d` files, which skip cleanly without a PBR dump.
//
//  The corpus layer walks the raw bytes with a reader written from the format
//  description rather than by calling `PBRFont3D` — the same trick
//  `ReferenceLZ77Decoders` uses on the compressors. A round trip through the
//  production parser alone would pass happily if the reader and the writer
//  were wrong in matching ways, and the claims being checked here (the payload
//  is consumed exactly, the bounding box is derived, the UVs are a projection)
//  are precisely the ones that justify throwing that data away.
//

import XCTest
import Foundation
import GoDFoundation
@testable import PBR

final class PBRFont3DTests: XCTestCase {

    // MARK: - Fixtures

    private func point(_ x: Int16, _ y: Int16) -> PBRFont3D.Point {
        PBRFont3D.Point(x: x, y: y)
    }

    /// A closed loop: first vertex repeated as last, which is how every real
    /// contour is stored.
    private func loop(_ points: [(Int16, Int16)]) -> PBRFont3D.Contour {
        let contour = points.map { point($0.0, $0.1) }
        return contour + [contour[0]]
    }

    /// A square outline with a square counter — the shape that exercises hole
    /// classification, bridging and the even-odd rule at once.
    private func ringGlyph(code: UInt16 = 0x4F) -> PBRFont3D.Glyph {
        PBRFont3D.Glyph(code: code, contours: [
            loop([(0, 0), (1000, 0), (1000, 1000), (0, 1000)]),
            loop([(250, 250), (750, 250), (750, 750), (250, 750)]),
        ])
    }

    private func sampleFont() -> PBRFont3D {
        PBRFont3D(glyphs: [
            // Blank, as space is in both real files.
            PBRFont3D.Glyph(code: 0x20, contours: []),
            // A concave outline, so ear clipping has to skip reflex corners.
            PBRFont3D.Glyph(code: 0x4C, contours: [
                loop([(0, 0), (400, 0), (400, 1600), (1200, 1600), (1200, 2000), (0, 2000)]),
            ]),
            ringGlyph(),
            // Negative coordinates, which the corpus has on both axes.
            PBRFont3D.Glyph(code: 0xFF5E, contours: [
                loop([(-800, -600), (800, -600), (0, 900)]),
            ]),
        ], name: "sample")
    }

    // MARK: - An independent reader

    private struct RawStripVertex {
        let x: Int16
        let y: Int16
        let u: UInt8
        let v: UInt8
    }

    private struct RawGlyph {
        let code: UInt16
        let payloadLength: Int
        let box: PBRFont3D.BoundingBox?
        let strips: [[RawStripVertex]]
        let contours: [[PBRFont3D.Point]]
        /// Bytes left between the terminator and the end of the payload. Must
        /// be zero everywhere: the format has no slack.
        let unreadBytes: Int
        let terminator: UInt16?
    }

    /// Walks a `.f3d` straight from the byte stream, per the format
    /// description and nothing else.
    private func readIndependently(_ bytes: [UInt8]) throws -> [RawGlyph] {
        func u16(_ at: Int) throws -> UInt16 {
            guard at + 2 <= bytes.count else { throw ReaderError.short }
            return UInt16(bytes[at]) << 8 | UInt16(bytes[at + 1])
        }
        func s16(_ at: Int) throws -> Int16 { Int16(bitPattern: try u16(at)) }
        func u32(_ at: Int) throws -> Int {
            guard at + 4 <= bytes.count else { throw ReaderError.short }
            return Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16
                | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3])
        }

        guard bytes.count >= 4, bytes[0] == 0x46, bytes[1] == 0x33 else { throw ReaderError.magic }
        let count = Int(try u16(2))
        var glyphs = [RawGlyph]()
        for index in 0 ..< count {
            let entry = try u32(4 + index * 4)
            let code = try u16(entry)
            let payloadLength = try u32(entry + 2)
            let payloadEnd = entry + 6 + payloadLength
            guard payloadEnd <= bytes.count else { throw ReaderError.short }
            guard payloadLength > 0 else {
                glyphs.append(RawGlyph(
                    code: code, payloadLength: 0, box: nil, strips: [], contours: [],
                    unreadBytes: 0, terminator: nil
                ))
                continue
            }
            var cursor = entry + 6
            let box = PBRFont3D.BoundingBox(
                xMin: try s16(cursor), xMax: try s16(cursor + 2),
                yMin: try s16(cursor + 4), yMax: try s16(cursor + 6)
            )
            cursor += 8
            var strips = [[RawStripVertex]]()
            let stripCount = Int(try u16(cursor)); cursor += 2
            for _ in 0 ..< stripCount {
                let vertexCount = Int(try u16(cursor)); cursor += 2
                var strip = [RawStripVertex]()
                for _ in 0 ..< vertexCount {
                    strip.append(RawStripVertex(
                        x: try s16(cursor), y: try s16(cursor + 2),
                        u: bytes[cursor + 4], v: bytes[cursor + 5]
                    ))
                    cursor += 6
                }
                strips.append(strip)
            }
            var contours = [[PBRFont3D.Point]]()
            let contourCount = Int(try u16(cursor)); cursor += 2
            for _ in 0 ..< contourCount {
                let vertexCount = Int(try u16(cursor)); cursor += 2
                var contour = [PBRFont3D.Point]()
                for _ in 0 ..< vertexCount {
                    contour.append(PBRFont3D.Point(x: try s16(cursor), y: try s16(cursor + 2)))
                    cursor += 4
                }
                contours.append(contour)
            }
            let terminator = try u16(cursor); cursor += 2
            glyphs.append(RawGlyph(
                code: code, payloadLength: payloadLength, box: box, strips: strips,
                contours: contours, unreadBytes: payloadEnd - cursor, terminator: terminator
            ))
        }
        return glyphs
    }

    private enum ReaderError: Error { case magic, short }

    // MARK: - Geometry

    /// The bounding box is derived rather than stored, so the derivation gets
    /// asserted directly against a shape whose extents are stated here.
    func testBoundingBoxEqualsTheContourExtents() {
        let glyph = PBRFont3D.Glyph(code: 0x41, contours: [
            loop([(-300, 40), (900, -120), (120, 640)]),
        ])
        let box = try? XCTUnwrap(glyph.boundingBox)
        XCTAssertEqual(box?.xMin, -300)
        XCTAssertEqual(box?.xMax, 900)
        XCTAssertEqual(box?.yMin, -120)
        XCTAssertEqual(box?.yMax, 640)
        XCTAssertNil(PBRFont3D.Glyph(code: 0x20, contours: []).boundingBox)
    }

    /// The planar projection that stands in for the stored UVs. Asserted on
    /// hand-computed values so a changed constant can't hide behind the
    /// corpus's ±1 tolerance.
    func testProjectionIsTheMeasuredPlanarMapping() {
        XCTAssertEqual(PBRFont3D.Projection.uv(for: point(0, 0)).u, 32, "0/200 + 31.5, rounded up")
        XCTAssertEqual(PBRFont3D.Projection.uv(for: point(0, 0)).v, 20, "0/200 + 19.5, rounded up")
        XCTAssertEqual(PBRFont3D.Projection.uv(for: point(200, 400)).u, 33)
        XCTAssertEqual(PBRFont3D.Projection.uv(for: point(200, 400)).v, 22)
        XCTAssertEqual(PBRFont3D.Projection.uv(for: point(-2000, -2000)).u, 22)
        XCTAssertEqual(PBRFont3D.Projection.uv(for: point(-2000, -2000)).v, 10)
    }

    /// Ear clipping has to reproduce the even-odd area exactly, or the front
    /// face doesn't match the outline the user edited. A ring is the smallest
    /// shape where a hole either gets cut out or doesn't.
    func testTessellationOfARingCoversTheEvenOddArea() {
        let triangles = PBRFont3DTessellator.triangulate(contours: ringGlyph().contours)
        XCTAssertFalse(triangles.isEmpty)
        let covered = triangles.reduce(0) { $0 + $1.doubleArea }
        XCTAssertEqual(covered, 2 * (1000 * 1000 - 500 * 500), "outer area minus the counter")
    }

    /// Nested counters — a hole inside a hole — must attach to their immediate
    /// parent, not to the outermost boundary; getting that wrong fills the
    /// innermost island as though it were a hole.
    func testTessellationHandlesANestedCounter() {
        let contours = [
            loop([(0, 0), (900, 0), (900, 900), (0, 900)]),
            loop([(100, 100), (800, 100), (800, 800), (100, 800)]),
            loop([(300, 300), (600, 300), (600, 600), (300, 600)]),
        ]
        let covered = PBRFont3DTessellator.triangulate(contours: contours)
            .reduce(0) { $0 + $1.doubleArea }
        XCTAssertEqual(covered, 2 * (900 * 900 - 700 * 700 + 300 * 300))
    }

    /// A contour that visits the same vertex twice is tracing two lobes, not
    /// one loop — `U+2603` walks the snowman's body, up through a shared seam
    /// into the head, and back down it. Its signed area is *body minus head*,
    /// so anything reading the loop whole fills the wrong region.
    func testTessellationSplitsASelfTouchingContourIntoItsLobes() {
        // Two 400×400 squares meeting at (400, 400), walked as one loop.
        let figureEight = [
            point(0, 0), point(400, 0), point(400, 400), point(800, 400),
            point(800, 800), point(400, 800), point(400, 400), point(0, 400),
            point(0, 0),
        ]
        let covered = PBRFont3DTessellator.triangulate(contours: [figureEight])
            .reduce(0) { $0 + $1.doubleArea }
        XCTAssertEqual(covered, 2 * (400 * 400 + 400 * 400), "both lobes are filled")
        XCTAssertEqual(
            evenOddDoubleArea(of: [figureEight]), Double(covered),
            "and the sweep agrees, which the signed area would not"
        )
    }

    /// Every vertex the tessellator emits has to be one it was given: `.f3d`
    /// vertices are 16-bit integers, so an invented intersection point would
    /// have to be rounded onto the grid and would pull the face off the
    /// outline.
    func testTessellationInventsNoVertices() {
        let contours = ringGlyph().contours
        let allowed = Set(contours.flatMap { $0 })
        for triangle in PBRFont3DTessellator.triangulate(contours: contours) {
            for vertex in [triangle.a, triangle.b, triangle.c] {
                XCTAssertTrue(allowed.contains(vertex), "\(vertex) is not an outline vertex")
            }
        }
    }

    // MARK: - Binary round trip

    func testRoundTripPreservesEveryContour() throws {
        let original = sampleFont()
        let decoded = try PBRFont3D(data: try original.data, name: original.name)
        XCTAssertEqual(decoded.glyphs, original.glyphs)
    }

    /// The written file has to satisfy the same structural claims the corpus
    /// does, checked by the independent reader rather than by re-parsing.
    func testWrittenPayloadsAreConsumedExactlyAndTerminated() throws {
        let raw = try readIndependently(try sampleFont().data.rawBytes)
        XCTAssertEqual(raw.count, 4)
        for glyph in raw where glyph.payloadLength > 0 {
            XCTAssertEqual(glyph.terminator, 0xFFFF, "U+\(String(format: "%04X", glyph.code))")
            XCTAssertEqual(glyph.unreadBytes, 0, "U+\(String(format: "%04X", glyph.code))")
        }
    }

    /// A glyph with no outline is written as a zero-length payload — with no
    /// bounding box, no strip count and no terminator — because that is what
    /// the corpus does for space and 30 others.
    func testBlankGlyphWritesAZeroLengthPayload() throws {
        let font = PBRFont3D(glyphs: [PBRFont3D.Glyph(code: 0x20, contours: [])])
        let raw = try readIndependently(try font.data.rawBytes)
        XCTAssertEqual(raw.count, 1)
        XCTAssertEqual(raw[0].payloadLength, 0)
        XCTAssertNil(raw[0].terminator)
        XCTAssertEqual(try PBRFont3D(data: try font.data).glyphs, font.glyphs)
    }

    /// Entry offsets are absolute and the table is fixed-width, so a writer
    /// that miscounts leaves every glyph after the mistake unreadable.
    func testEntryOffsetsAreAbsoluteAndStartAfterTheTable() throws {
        let bytes = try sampleFont().data
        bytes.setByteOrder(.big)
        let count = Int(bytes.readSafely(atAddress: 2) as UInt16)
        XCTAssertEqual(count, 4)
        var previousEnd = 4 + count * 4
        for index in 0 ..< count {
            let offset = Int(bytes.readSafely(atAddress: 4 + index * 4) as UInt32)
            XCTAssertEqual(offset, previousEnd, "entries are written contiguously")
            previousEnd = offset + 6 + Int(bytes.readSafely(atAddress: offset + 2) as UInt32)
        }
        XCTAssertEqual(previousEnd, bytes.length, "the last entry ends the file")
    }

    // MARK: - Rejection

    func testRejectsDataThatIsNotA3DFont() {
        let notAFont = GoDData(byteStream: [0x46, 0x4F, 0x4E, 0x54, 0x00, 0x02], byteOrder: .big)
        XCTAssertThrowsError(try PBRFont3D(data: notAFont)) { error in
            guard case PBRFont3D.Error.notA3DFontContainer = error else {
                return XCTFail("expected notA3DFontContainer, got \(error)")
            }
        }
    }

    /// The terminator is the only thing separating a well-formed payload from
    /// one whose counts happen to add up, so a missing one has to be an error
    /// rather than a shrug.
    func testRejectsAPayloadWhoseTerminatorIsMissing() throws {
        var raw = try sampleFont().data.rawBytes
        // The ring glyph is third; blank glyphs have no terminator to break.
        let entry = Int(raw[4 + 8]) << 24 | Int(raw[4 + 9]) << 16
            | Int(raw[4 + 10]) << 8 | Int(raw[4 + 11])
        let payloadLength = Int(raw[entry + 2]) << 24 | Int(raw[entry + 3]) << 16
            | Int(raw[entry + 4]) << 8 | Int(raw[entry + 5])
        raw[entry + 6 + payloadLength - 2] = 0x00
        raw[entry + 6 + payloadLength - 1] = 0x00
        XCTAssertThrowsError(try PBRFont3D(data: GoDData(byteStream: raw, byteOrder: .big))) { error in
            guard case PBRFont3D.Error.missingTerminator = error else {
                return XCTFail("expected missingTerminator, got \(error)")
            }
        }
    }

    /// A count that walks past the payload must be caught inside the glyph
    /// that declared it, not read on into the next one, where it would
    /// produce plausible-looking geometry.
    func testRejectsAContourCountThatOverrunsItsPayload() throws {
        var raw = try sampleFont().data.rawBytes
        let entry = Int(raw[4 + 4]) << 24 | Int(raw[4 + 5]) << 16
            | Int(raw[4 + 6]) << 8 | Int(raw[4 + 7])
        // Strip count sits at payload +8; a huge one overruns immediately.
        raw[entry + 6 + 8] = 0xFF
        raw[entry + 6 + 9] = 0xFF
        XCTAssertThrowsError(try PBRFont3D(data: GoDData(byteStream: raw, byteOrder: .big))) { error in
            guard case PBRFont3D.Error.payloadOverrun = error else {
                return XCTFail("expected payloadOverrun, got \(error)")
            }
        }
    }

    // MARK: - SVG artifacts

    func testSVGRoundTripPreservesEveryContour() throws {
        let original = sampleFont()
        let bundle = try original.outputs
        XCTAssertEqual(bundle.count, 2, "manifest + sheet")
        XCTAssertTrue(bundle[0].file.path.hasSuffix(".f3d.json"))
        XCTAssertTrue(bundle[1].file.path.hasSuffix(".f3d.svg"))

        let rebuilt = try PBRFont3D(outputs: bundle)
        XCTAssertEqual(rebuilt.glyphs, original.glyphs)
        XCTAssertEqual(rebuilt.name, original.name)
    }

    /// The sheet's shape is a contract with whatever edits it, so the pieces
    /// the importer depends on are asserted rather than assumed.
    func testSVGSheetHasOneEvenOddPathPerNonBlankGlyph() throws {
        let font = sampleFont()
        let (svg, manifest) = PBRFont3DSVG.export(font: font, svgPath: "sample.f3d.svg")
        let text = try XCTUnwrap(String(data: svg.data, encoding: .utf8))
        XCTAssertEqual(
            text.components(separatedBy: "<g id=").count - 1, font.glyphs.count,
            "one group per glyph, blanks included, so order stays aligned"
        )
        XCTAssertEqual(
            text.components(separatedBy: "fill-rule=\"evenodd\"").count - 1,
            font.glyphs.filter { !$0.isBlank }.count
        )
        XCTAssertTrue(text.contains("<g id=\"U+0020\" transform=\"translate("), "blank glyph kept")
        XCTAssertEqual(manifest.glyphs.map(\.code), font.glyphs.map { Int($0.code) })
        XCTAssertEqual(manifest.grid.columns, PBRFont3DSVG.columns)
        XCTAssertEqual(manifest.derivation.unitsPerTexel, 200)
        XCTAssertEqual(manifest.derivation.uvOriginU, 31.5)
        XCTAssertEqual(manifest.derivation.uvOriginV, 19.5)
    }

    /// The grid is the manifest's job. Cells have to be derived from the
    /// recorded em box, or a glyph lands in the wrong place on re-export.
    func testSVGGridGeometryComesFromTheManifest() throws {
        let font = sampleFont()
        let (svg, manifest) = PBRFont3DSVG.export(font: font, svgPath: "sample.f3d.svg")
        let text = try XCTUnwrap(String(data: svg.data, encoding: .utf8))
        XCTAssertEqual(manifest.grid.emBox.xMin, -800)
        XCTAssertEqual(manifest.grid.emBox.yMin, -600)
        XCTAssertEqual(manifest.grid.cellWidth, (1200 - -800) + PBRFont3DSVG.gutter)
        XCTAssertEqual(manifest.grid.cellHeight, (2000 - -600) + PBRFont3DSVG.gutter)
        // Second glyph, second column: one cell across plus the em offset.
        let expectedX = manifest.grid.cellWidth - manifest.grid.emBox.xMin
        let expectedY = -manifest.grid.emBox.yMin
        XCTAssertTrue(
            text.contains("<g id=\"U+004C\" transform=\"translate(\(expectedX),\(expectedY))\">"),
            "glyph 1 sits in column 1 of row 0"
        )
    }

    /// The path parser is deliberately narrow: `.f3d` stores straight lines,
    /// so a curve has nothing to become and flattening one silently would
    /// change the glyph at a tolerance nobody picked.
    func testSVGImportRejectsACommandTheFormatCannotStore() {
        XCTAssertThrowsError(
            try PBRFont3DSVG.parsePath("M 0 0 C 1 1 2 2 3 3 Z", id: "U+0041")
        ) { error in
            guard case PBRFont3DSVG.Error.unsupportedPathCommand = error else {
                return XCTFail("expected unsupportedPathCommand, got \(error)")
            }
        }
        XCTAssertThrowsError(
            try PBRFont3DSVG.parsePath("m 0 0 l 10 0 z", id: "U+0041")
        ) { error in
            guard case PBRFont3DSVG.Error.unsupportedPathCommand = error else {
                return XCTFail("relative commands are not emitted, got \(error)")
            }
        }
    }

    func testSVGPathParserReadsSubpathsAsContours() throws {
        let contours = try PBRFont3DSVG.parsePath(
            "M 0 0 L 10 0 L 10 10 L 0 0 Z M -5 -5 L -5 5 L 5 -5 L -5 -5 Z", id: "U+0041"
        )
        XCTAssertEqual(contours.count, 2)
        XCTAssertEqual(contours[0], loop([(0, 0), (10, 0), (10, 10)]))
        XCTAssertEqual(contours[1].first, point(-5, -5))
        XCTAssertEqual(contours[1].last, point(-5, -5), "the closing repeat survives")
        // Implied linetos after an M, which an editor may emit.
        XCTAssertEqual(
            try PBRFont3DSVG.parsePath("M 0 0 1 1 2 2 Z", id: "U+0041"),
            [[point(0, 0), point(1, 1), point(2, 2)]]
        )
    }

    /// A sheet whose groups were reordered can't be trusted to say which
    /// outline belongs to which character, so it's refused rather than
    /// reconciled.
    func testSVGImportRefusesASheetOutOfStepWithItsManifest() throws {
        let font = sampleFont()
        let (svg, manifest) = PBRFont3DSVG.export(font: font, svgPath: "sample.f3d.svg")
        let text = try XCTUnwrap(String(data: svg.data, encoding: .utf8))
        let scrambled = text.replacingOccurrences(of: "id=\"U+004C\"", with: "id=\"U+004D\"")
        XCTAssertThrowsError(try PBRFont3DSVG.importFont(
            svg: GoDData(data: Data(scrambled.utf8), byteOrder: .big), manifest: manifest
        )) { error in
            guard case PBRFont3DSVG.Error.glyphIdMismatch = error else {
                return XCTFail("expected glyphIdMismatch, got \(error)")
            }
        }
    }

    // MARK: - Real corpus

    /// Folders that may hold unpacked `.f3d` files. `GODDESS_PBR_F3D` wins.
    private var f3dFolders: [String] {
        if let override = ProcessInfo.processInfo.environment["GODDESS_PBR_F3D"] {
            return [override]
        }
        let home = NSHomeDirectory()
        return [
            home + "/Downloads/GODDESS-JP-dump/PBR JP project/Build/Unpacked/Assets/Misc",
            home + "/Downloads/GODDESS-JP-dump/PBR JP project/Build/Unpacked/Data/Text/Fonts",
        ]
    }

    private func corpusFiles() -> [(name: String, bytes: [UInt8])] {
        var found = [(name: String, bytes: [UInt8])]()
        for root in f3dFolders {
            guard let walker = FileManager.default.enumerator(atPath: root) else { continue }
            for case let path as String in walker where path.lowercased().hasSuffix(".f3d") {
                let full = root + "/" + path
                guard let data = FileManager.default.contents(atPath: full) else { continue }
                found.append((full, [UInt8](data)))
            }
        }
        return found.sorted { $0.name < $1.name }
    }

    private func corpus() throws -> [(name: String, bytes: [UInt8])] {
        let files = corpusFiles()
        guard !files.isEmpty else {
            throw XCTSkip("No unpacked PBR .f3d files — set GODDESS_PBR_F3D to run.")
        }
        return files
    }

    /// Every payload has to be accounted for down to the byte, with the
    /// 0xFFFF terminator where it belongs. This is the claim that says the
    /// format description is complete — an unread tail would mean a field
    /// nobody has named.
    func testRealCorpusPayloadsAreConsumedExactlyAndTerminated() throws {
        var glyphCount = 0
        var blanks = 0
        for file in try corpus() {
            let raw = try readIndependently(file.bytes)
            for glyph in raw {
                glyphCount += 1
                guard glyph.payloadLength > 0 else {
                    blanks += 1
                    XCTAssertNil(glyph.terminator)
                    continue
                }
                XCTAssertEqual(
                    glyph.terminator, 0xFFFF,
                    "\(file.name) U+\(String(format: "%04X", glyph.code))"
                )
                XCTAssertEqual(
                    glyph.unreadBytes, 0,
                    "\(file.name) U+\(String(format: "%04X", glyph.code)) left bytes unread"
                )
            }
        }
        XCTAssertGreaterThan(glyphCount, 0)
        print("[PBRFont3D] \(glyphCount) real glyphs consumed exactly (\(blanks) blank)")
    }

    /// The production parser must agree with the independent reader on every
    /// contour, and must accept every real file.
    func testRealCorpusParsesAndAgreesWithTheIndependentReader() throws {
        for file in try corpus() {
            let font = try PBRFont3D(data: GoDData(byteStream: file.bytes, byteOrder: .big))
            let raw = try readIndependently(file.bytes)
            XCTAssertEqual(font.glyphs.count, raw.count, file.name)
            for (glyph, reference) in zip(font.glyphs, raw) {
                XCTAssertEqual(glyph.code, reference.code, file.name)
                XCTAssertEqual(glyph.contours, reference.contours, file.name)
            }
        }
    }

    /// Contours are closed loops. The exporter relies on it (`Z` after the
    /// repeated vertex) and so does the tessellator's normalization.
    func testRealCorpusContoursAreClosedLoops() throws {
        var contours = 0
        for file in try corpus() {
            for glyph in try readIndependently(file.bytes).flatMap(\.contours) {
                contours += 1
                XCTAssertGreaterThanOrEqual(glyph.count, 2, file.name)
                XCTAssertEqual(glyph.first, glyph.last, "\(file.name): contour is not closed")
            }
        }
        XCTAssertGreaterThan(contours, 0)
        print("[PBRFont3D] \(contours) real contours are closed loops")
    }

    /// The stored bounding box is dropped on parse and re-derived on write, so
    /// it has to equal the contour extents on every real glyph — a single
    /// counter-example would mean the box carries something else.
    func testRealCorpusBoundingBoxesEqualTheContourExtents() throws {
        var checked = 0
        for file in try corpus() {
            for reference in try readIndependently(file.bytes) {
                guard let box = reference.box else { continue }
                let glyph = PBRFont3D.Glyph(code: reference.code, contours: reference.contours)
                XCTAssertEqual(
                    glyph.boundingBox, box,
                    "\(file.name) U+\(String(format: "%04X", reference.code))"
                )
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
        print("[PBRFont3D] \(checked) real bounding boxes equal their contour extents")
    }

    /// UVs are dropped on parse and re-derived from a planar projection. The
    /// projection is not exact — it reproduces most components and misses the
    /// rest by one — so the claim under test is that nothing is further out
    /// than that, which is what makes them safe to discard.
    func testRealCorpusUVsMatchTheProjectionWithinOne() throws {
        var exact = 0
        var total = 0
        for file in try corpus() {
            for reference in try readIndependently(file.bytes) {
                for vertex in reference.strips.flatMap({ $0 }) {
                    let (u, v) = PBRFont3D.Projection.uv(
                        for: PBRFont3D.Point(x: vertex.x, y: vertex.y)
                    )
                    XCTAssertLessThanOrEqual(
                        abs(Int(u) - Int(vertex.u)), 1,
                        "\(file.name) u at (\(vertex.x), \(vertex.y))"
                    )
                    XCTAssertLessThanOrEqual(
                        abs(Int(v) - Int(vertex.v)), 1,
                        "\(file.name) v at (\(vertex.x), \(vertex.y))"
                    )
                    if u == vertex.u { exact += 1 }
                    if v == vertex.v { exact += 1 }
                    total += 2
                }
            }
        }
        XCTAssertGreaterThan(total, 0)
        let percentage = 100 * Double(exact) / Double(total)
        XCTAssertGreaterThan(percentage, 99, "the projection should reproduce nearly every texel")
        print(String(format: "[PBRFont3D] %d/%d stored UV components exact (%.2f%%)", exact, total, percentage))
    }

    /// Strips are dropped and re-derived. The derivation has to cover the same
    /// area the outline encloses, or the rebuilt glyph renders with holes
    /// filled in or slivers missing.
    func testRealCorpusTessellationCoversTheOutlineArea() throws {
        var worst = 0.0
        var checked = 0
        for file in try corpus() {
            let font = try PBRFont3D(data: GoDData(byteStream: file.bytes, byteOrder: .big))
            for glyph in font.glyphs where !glyph.isBlank {
                let expected = evenOddDoubleArea(of: glyph.contours)
                guard expected > 0 else { continue }
                let covered = Double(
                    PBRFont3DTessellator.triangulate(contours: glyph.contours)
                        .reduce(0) { $0 + $1.doubleArea }
                )
                let error = abs(covered - expected) / expected
                worst = max(worst, error)
                // Not a tolerance so much as a floating-point epsilon: the
                // sweep and the triangle sum should agree exactly.
                XCTAssertLessThan(
                    error, 1e-9,
                    "\(file.name) U+\(String(format: "%04X", glyph.code)) "
                        + "covered \(covered) of \(expected)"
                )
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
        print(String(format: "[PBRFont3D] %d real glyphs tessellated; worst area error %.6f%%", checked, worst * 100))
    }

    /// A rebuilt file has to re-parse into the same outlines. Byte-identical
    /// is explicitly not the goal — strips and UVs are re-derived — so this is
    /// the claim that stands in for it.
    func testRealCorpusReserializesAndReparsesWithIdenticalContours() throws {
        for file in try corpus() {
            let original = try PBRFont3D(data: GoDData(byteStream: file.bytes, byteOrder: .big))
            let rebuilt = try PBRFont3D(data: try original.data)
            XCTAssertEqual(rebuilt.glyphs, original.glyphs, file.name)
            // And the rebuilt file must satisfy the structural claims too.
            for glyph in try readIndependently(try original.data.rawBytes)
            where glyph.payloadLength > 0 {
                XCTAssertEqual(glyph.terminator, 0xFFFF, file.name)
                XCTAssertEqual(glyph.unreadBytes, 0, file.name)
            }
        }
    }

    func testRealCorpusSurvivesTheSVGRoundTrip() throws {
        for file in try corpus() {
            let stem = URL(fileURLWithPath: file.name).lastPathComponent.withoutExtensions
            let original = try PBRFont3D(
                data: GoDData(byteStream: file.bytes, byteOrder: .big), name: stem
            )
            let rebuilt = try PBRFont3D(outputs: try original.outputs)
            XCTAssertEqual(rebuilt.glyphs, original.glyphs, file.name)
        }
    }

    // MARK: - Test-side geometry

    /// Doubled area of what an outline fills under the even-odd rule, measured
    /// by sweeping bands between consecutive vertex rows.
    ///
    /// Deliberately not the shoelace-minus-holes sum the tessellator's own
    /// classification would produce: that formula is only valid for loops that
    /// don't touch, and it gets `U+2603` — one contour tracing two lobes
    /// through a shared seam — wrong by a factor of nine. A sweep asks the
    /// question the fill rule actually poses (how much of the plane has an odd
    /// crossing count) and doesn't care how the loops are arranged.
    ///
    /// Exact rather than approximate: no edge begins or ends inside a band, so
    /// every crossing moves linearly with y and the midpoint width integrates
    /// the band exactly.
    private func evenOddDoubleArea(of contours: [[PBRFont3D.Point]]) -> Double {
        var edges = [(a: PBRFont3D.Point, b: PBRFont3D.Point)]()
        for contour in contours {
            var points = contour
            while points.count > 1, points.first == points.last { points.removeLast() }
            guard points.count >= 3 else { continue }
            for i in points.indices {
                let a = points[i], b = points[(i + 1) % points.count]
                if a.y != b.y { edges.append((a, b)) }
            }
        }
        guard !edges.isEmpty else { return 0 }

        let rows = Set(edges.flatMap { [Int($0.a.y), Int($0.b.y)] }).sorted()
        var total = 0.0
        for index in 0 ..< rows.count - 1 {
            let low = Double(rows[index]), high = Double(rows[index + 1])
            let middle = (low + high) / 2
            var crossings = [Double]()
            for edge in edges {
                let ay = Double(edge.a.y), by = Double(edge.b.y)
                guard min(ay, by) < middle, middle < max(ay, by) else { continue }
                crossings.append(
                    Double(edge.a.x)
                        + (middle - ay) * (Double(edge.b.x) - Double(edge.a.x)) / (by - ay)
                )
            }
            crossings.sort()
            var width = 0.0
            var pair = 0
            while pair + 1 < crossings.count {
                width += crossings[pair + 1] - crossings[pair]
                pair += 2
            }
            total += width * (high - low)
        }
        return total * 2
    }
}
