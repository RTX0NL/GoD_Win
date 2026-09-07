//
//  PBRFont3DSVG.swift
//  PBR
//
//  Editable artifacts for `PBRFont3D`: one SVG specimen sheet holding every
//  glyph, plus one JSON manifest.
//
//  One file rather than one per glyph. A `.f3d` carries ~450 outlines, and a
//  folder of 450 tiny SVGs is neither easier to edit nor easier to review than
//  a sheet you can open and read at a glance — the same argument that makes
//  the bitmap fonts a single atlas image rather than a directory of stamps.
//
//  Layout: glyphs sit in a fixed grid, each in its own
//  `<g id="U+XXXX" transform="translate(…)">` holding a single `<path>`.
//
//  Three decisions worth stating, because each one is a place a plausible
//  alternative would quietly lose data:
//
//  - **`fill-rule="evenodd"`.** Which way round a `.f3d` contour runs has not
//    been established, and the nonzero rule would render a hole as solid ink
//    whenever the loops happen to share a winding. Even-odd depends on nesting
//    alone, so holes come out right without anyone having to be right about
//    winding. `PBRFont3DTessellator` uses the same rule, so the picture and
//    the rebuilt geometry agree.
//  - **Path coordinates are raw glyph units.** The group transform does the
//    placement, which is how SVG works — a transform applies to children, so
//    putting sheet coordinates in the path *and* a translate would apply the
//    offset twice. An import therefore subtracts nothing, and moving a group
//    in an editor is cosmetic: position isn't glyph data, so a shifted
//    transform must not shift the outline. Grid geometry lives in the
//    manifest, which is what an export reads to place the cells and what a
//    tool reads to interpret them — never inferred from the SVG.
//  - **Every stored vertex is emitted, including a contour's repeated closing
//    vertex.** `Z` already closes a subpath, so that last point is redundant
//    for rendering — but it is present on disk in all 1758 real contours, and
//    dropping it would mean an import had to guess whether to put it back.
//    Writing it makes the round trip exact by construction.
//

import Foundation
import GoDFoundation

public enum PBRFont3DSVG {

    /// Everything the SVG can't carry: which glyph each group is, where the
    /// cells are, and the constants the binary writer re-derives its strips
    /// and UVs from.
    public struct Manifest: Codable, Equatable {
        /// Always `f3d`. Present so a manifest identifies itself when read on
        /// its own, out of the folder it was written into.
        public let format: String
        /// Stem the artifacts and the rebuilt binary are named after.
        public let name: String
        /// Sheet filename, relative to the manifest's own folder.
        public let svgPath: String
        public let grid: Grid
        public let derivation: Derivation
        /// Glyphs in the file's order, which is the order the groups appear in
        /// the sheet. Load-bearing: `common_0034.f3d` is not sorted by code.
        public let glyphs: [Glyph]

        public struct Grid: Codable, Equatable {
            public let columns: Int
            public let rows: Int
            /// Cell pitch in glyph units — the em box plus one texel of gutter.
            public let cellWidth: Int
            public let cellHeight: Int
            /// Union of every glyph's extents. A cell is placed so this box
            /// lands at the cell's origin, which is what makes glyphs line up
            /// on a shared baseline instead of each floating in its own crop.
            public let emBox: EmBox
        }

        public struct EmBox: Codable, Equatable {
            public let xMin: Int
            public let yMin: Int
            public let xMax: Int
            public let yMax: Int
        }

        /// The rules `PBRFont3D` re-derives the discarded payload fields with,
        /// written down rather than left implicit in the code. An editor that
        /// wants to preview UVs, or a human wondering why the rebuilt file
        /// isn't byte-identical, can read them here.
        public struct Derivation: Codable, Equatable {
            /// Glyph units per texel: 200.
            public let unitsPerTexel: Double
            /// Texel coordinate glyph-space x = 0 maps to: 31.5.
            public let uvOriginU: Double
            /// Texel coordinate glyph-space y = 0 maps to: 19.5.
            public let uvOriginV: Double
            /// Plain-language statement of what is derived and what is stored.
            public let note: String
        }

        public struct Glyph: Codable, Equatable {
            public let code: Int
            /// `U+XXXX` — the `id` of this glyph's group in the sheet.
            public let id: String
            /// The character itself, for readability while editing. Never
            /// parsed: `code` is the field that means anything.
            public let character: String
            public let column: Int
            public let row: Int
            /// Number of subpaths this glyph's `d` attribute should hold.
            /// Checked on import, so a hand-edit that drops a counter is
            /// reported rather than silently accepted.
            public let contourCount: Int
        }
    }

    public enum Error: GoDError {
        case malformedSVG(reason: String, ErrorTrace = .init())
        case glyphCountMismatch(expected: Int, found: Int, ErrorTrace = .init())
        case glyphIdMismatch(index: Int, expected: String, found: String, ErrorTrace = .init())
        case contourCountMismatch(id: String, expected: Int, found: Int, ErrorTrace = .init())
        case unsupportedPathCommand(id: String, command: String, ErrorTrace = .init())
        case malformedPathData(id: String, reason: String, ErrorTrace = .init())
        case coordinateOutOfRange(id: String, value: Double, ErrorTrace = .init())

        public var description: String {
            switch self {
            case let .malformedSVG(reason, trace):
                return "Error: PBR 3D font sheet is malformed — \(reason).\n\(trace)"
            case let .glyphCountMismatch(expected, found, trace):
                return "Error: PBR 3D font sheet holds \(found) glyph groups; the manifest "
                    + "describes \(expected).\n\(trace)"
            case let .glyphIdMismatch(index, expected, found, trace):
                return "Error: PBR 3D font sheet group \(index) is '\(found)'; the manifest "
                    + "expects '\(expected)'. Groups must stay in the manifest's order.\n\(trace)"
            case let .contourCountMismatch(id, expected, found, trace):
                return "Error: PBR 3D font glyph \(id) has \(found) subpaths; the manifest "
                    + "expects \(expected).\n\(trace)"
            case let .unsupportedPathCommand(id, command, trace):
                return "Error: PBR 3D font glyph \(id) uses path command '\(command)'. Only "
                    + "absolute M, L and Z are supported — a curve has no representation in "
                    + "a format that stores straight-line contours.\n\(trace)"
            case let .malformedPathData(id, reason, trace):
                return "Error: PBR 3D font glyph \(id) has unreadable path data — \(reason).\n\(trace)"
            case let .coordinateOutOfRange(id, value, trace):
                return "Error: PBR 3D font glyph \(id) has coordinate \(value), which doesn't "
                    + "fit the format's signed 16-bit vertices.\n\(trace)"
            }
        }
    }

    /// Gutter between cells, in glyph units. One texel of the UV projection,
    /// so the sheet's spacing is stated in the format's own unit rather than
    /// an arbitrary number of pixels.
    public static let gutter = Int(PBRFont3D.Projection.unitsPerTexel)

    /// Glyphs per row. 16 so a row is a Unicode block row when codes happen to
    /// be contiguous, which they are across most of both files.
    public static let columns = 16

    // MARK: - Export

    public static func export(
        font: PBRFont3D, svgPath: String
    ) -> (svg: GoDData, manifest: Manifest) {
        let emBox = self.emBox(of: font)
        let cellWidth = (emBox.xMax - emBox.xMin) + gutter
        let cellHeight = (emBox.yMax - emBox.yMin) + gutter
        let rows = max(1, (font.glyphs.count + columns - 1) / columns)

        var entries = [Manifest.Glyph]()
        entries.reserveCapacity(font.glyphs.count)
        var body = ""
        for (index, glyph) in font.glyphs.enumerated() {
            let column = index % columns
            let row = index / columns
            let id = identifier(for: glyph.code)
            entries.append(Manifest.Glyph(
                code: Int(glyph.code),
                id: id,
                character: character(for: glyph.code),
                column: column,
                row: row,
                contourCount: glyph.contours.count
            ))

            let x = column * cellWidth - emBox.xMin
            let y = row * cellHeight - emBox.yMin
            body += "  <g id=\"\(id)\" transform=\"translate(\(x),\(y))\">"
            if glyph.contours.isEmpty {
                // A blank glyph still gets a group, so group order and glyph
                // order stay the same list. An empty `d` would be a path with
                // no subpaths, which some editors delete outright.
                body += "</g>\n"
            } else {
                body += "\n    <path fill-rule=\"evenodd\" d=\"\(pathData(for: glyph))\"/>\n  </g>\n"
            }
        }

        let width = columns * cellWidth
        let height = rows * cellHeight
        var svg = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        svg += "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(width) \(height)\">\n"
        svg += "  <title>\(escape(font.name)).f3d</title>\n"
        svg += body
        svg += "</svg>\n"

        let manifest = Manifest(
            format: PBRFont3D.formatName,
            name: font.name,
            svgPath: svgPath,
            grid: Manifest.Grid(
                columns: columns,
                rows: rows,
                cellWidth: cellWidth,
                cellHeight: cellHeight,
                emBox: emBox
            ),
            derivation: Manifest.Derivation(
                unitsPerTexel: PBRFont3D.Projection.unitsPerTexel,
                uvOriginU: PBRFont3D.Projection.originU,
                uvOriginV: PBRFont3D.Projection.originV,
                note: "Only the contours in this sheet are stored in the .f3d. The triangle "
                    + "strips, the per-glyph bounding box and the vertex UVs are re-derived on "
                    + "build: strips by triangulating the contours under the even-odd rule, the "
                    + "box from the contour extents, and each UV as "
                    + "u = round(x / unitsPerTexel + uvOriginU), "
                    + "v = round(y / unitsPerTexel + uvOriginV)."
            ),
            glyphs: entries
        )
        return (GoDData(data: Data(svg.utf8), byteOrder: .big), manifest)
    }

    /// One subpath per contour: `M x y L x y … Z`.
    private static func pathData(for glyph: PBRFont3D.Glyph) -> String {
        var parts = [String]()
        for contour in glyph.contours where !contour.isEmpty {
            var subpath = "M \(contour[0].x) \(contour[0].y)"
            for point in contour.dropFirst() {
                subpath += " L \(point.x) \(point.y)"
            }
            parts.append(subpath + " Z")
        }
        return parts.joined(separator: " ")
    }

    /// Union of every glyph's extents. Falls back to a unit box for a font
    /// with no geometry at all, so the grid never collapses to zero size.
    private static func emBox(of font: PBRFont3D) -> Manifest.EmBox {
        var xMin = Int.max, xMax = Int.min, yMin = Int.max, yMax = Int.min
        for glyph in font.glyphs {
            guard let box = glyph.boundingBox else { continue }
            xMin = min(xMin, Int(box.xMin))
            xMax = max(xMax, Int(box.xMax))
            yMin = min(yMin, Int(box.yMin))
            yMax = max(yMax, Int(box.yMax))
        }
        guard xMin <= xMax, yMin <= yMax else {
            return Manifest.EmBox(xMin: 0, yMin: 0, xMax: 1, yMax: 1)
        }
        return Manifest.EmBox(xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax)
    }

    public static func identifier(for code: UInt16) -> String {
        "U+" + String(format: "%04X", code)
    }

    /// The glyph's character, or an empty string for a code that isn't one.
    /// Cosmetic only — nothing reads it back. Unescaped, because this goes
    /// into the JSON manifest rather than the sheet, and JSON does its own
    /// escaping; control codes are dropped so neither file has to carry one.
    private static func character(for code: UInt16) -> String {
        guard code >= 0x20, code != 0x7F, let scalar = Unicode.Scalar(code) else { return "" }
        return String(Character(scalar))
    }

    private static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }

    // MARK: - Import

    /// Rebuilds a font from a sheet and its manifest.
    ///
    /// The manifest is authoritative for which glyph is which and in what
    /// order; the sheet supplies only outlines. Anything the two disagree
    /// about is an error rather than something to reconcile — a sheet whose
    /// groups have been reordered or deleted is a sheet whose glyph codes can
    /// no longer be trusted, and guessing would put outlines on the wrong
    /// characters.
    public static func importFont(
        svg: GoDData, manifest: Manifest, name: String? = nil
    ) throws -> PBRFont3D {
        guard let text = String(data: svg.data, encoding: .utf8) else {
            throw Error.malformedSVG(reason: "not UTF-8 text")
        }
        let groups = try parseGroups(text)
        guard groups.count == manifest.glyphs.count else {
            throw Error.glyphCountMismatch(expected: manifest.glyphs.count, found: groups.count)
        }

        var glyphs = [PBRFont3D.Glyph]()
        glyphs.reserveCapacity(groups.count)
        for (index, entry) in manifest.glyphs.enumerated() {
            let group = groups[index]
            guard group.id == entry.id else {
                throw Error.glyphIdMismatch(index: index, expected: entry.id, found: group.id)
            }
            let contours = try group.pathData.map { try parsePath($0, id: entry.id) } ?? []
            guard contours.count == entry.contourCount else {
                throw Error.contourCountMismatch(
                    id: entry.id, expected: entry.contourCount, found: contours.count
                )
            }
            glyphs.append(PBRFont3D.Glyph(code: UInt16(truncatingIfNeeded: entry.code), contours: contours))
        }
        return PBRFont3D(glyphs: glyphs, name: name ?? manifest.name)
    }

    /// Scans the sheet for `<g id="…">` elements and the `d` attribute of the
    /// single path inside each.
    ///
    /// A hand-rolled scan rather than an XML parser: the sheet has exactly one
    /// nesting level and a fixed shape, so a parser would be a dependency
    /// bought to read four attribute values. It is strict about that shape and
    /// says so when it doesn't hold, which is the behavior that matters —
    /// silently skipping an element it didn't understand would drop a glyph.
    private static func parseGroups(
        _ text: String
    ) throws -> [(id: String, pathData: String?)] {
        var groups = [(id: String, pathData: String?)]()
        var cursor = text.startIndex
        while let open = text.range(of: "<g", range: cursor ..< text.endIndex) {
            // `<g` also prefixes any future `<glyph`-style element, so the
            // element name has to actually end here.
            guard open.upperBound == text.endIndex
                    || text[open.upperBound].isWhitespace
                    || text[open.upperBound] == ">"
                    || text[open.upperBound] == "/" else {
                cursor = open.upperBound
                continue
            }
            guard let tagEnd = text.range(of: ">", range: open.upperBound ..< text.endIndex) else {
                throw Error.malformedSVG(reason: "an unterminated <g> tag")
            }
            let attributes = String(text[open.upperBound ..< tagEnd.lowerBound])
            guard let id = attribute("id", in: attributes) else {
                throw Error.malformedSVG(reason: "a <g> element with no id")
            }
            guard let close = text.range(of: "</g>", range: tagEnd.upperBound ..< text.endIndex) else {
                throw Error.malformedSVG(reason: "an unclosed <g id=\"\(id)\">")
            }
            let contents = String(text[tagEnd.upperBound ..< close.lowerBound])
            groups.append((id: id, pathData: try pathAttribute(in: contents, id: id)))
            cursor = close.upperBound
        }
        guard !groups.isEmpty else {
            throw Error.malformedSVG(reason: "no <g> glyph groups")
        }
        return groups
    }

    private static func pathAttribute(in contents: String, id: String) throws -> String? {
        guard let open = contents.range(of: "<path") else { return nil }
        guard let tagEnd = contents.range(of: ">", range: open.upperBound ..< contents.endIndex) else {
            throw Error.malformedSVG(reason: "an unterminated <path> in \(id)")
        }
        let attributes = String(contents[open.upperBound ..< tagEnd.lowerBound])
        guard let data = attribute("d", in: attributes) else {
            throw Error.malformedPathData(id: id, reason: "the <path> has no d attribute")
        }
        return data
    }

    /// Reads one attribute value out of a start tag's attribute run.
    ///
    /// Matches a *whole* attribute name — `d` must not be found inside
    /// `fill-rule`, and the ordering of attributes in a hand-edited file is
    /// not something to rely on — and accepts either quote character, since
    /// an editor that rewrites the sheet may well prefer single quotes.
    private static func attribute(_ name: String, in attributes: String) -> String? {
        var search = attributes.startIndex
        while let key = attributes.range(of: name, range: search ..< attributes.endIndex) {
            search = key.upperBound
            if key.lowerBound > attributes.startIndex {
                let preceding = attributes[attributes.index(before: key.lowerBound)]
                guard preceding.isWhitespace else { continue }
            }
            var cursor = key.upperBound
            func skipWhitespace() {
                while cursor < attributes.endIndex, attributes[cursor].isWhitespace {
                    cursor = attributes.index(after: cursor)
                }
            }
            skipWhitespace()
            guard cursor < attributes.endIndex, attributes[cursor] == "=" else { continue }
            cursor = attributes.index(after: cursor)
            skipWhitespace()
            guard cursor < attributes.endIndex else { continue }
            let quote = attributes[cursor]
            guard quote == "\"" || quote == "'" else { continue }
            cursor = attributes.index(after: cursor)
            guard let end = attributes.range(
                of: String(quote), range: cursor ..< attributes.endIndex
            ) else { return nil }
            return String(attributes[cursor ..< end.lowerBound])
        }
        return nil
    }

    /// Parses the subset of SVG path syntax the exporter emits: absolute `M`,
    /// absolute `L`, and `Z`.
    ///
    /// Deliberately narrow. `.f3d` stores straight-line contours and nothing
    /// else, so a curve command has no representation to convert into — a
    /// parser that accepted one would have to flatten it silently, at a
    /// tolerance nobody chose. Refusing is the honest answer, and it tells the
    /// user exactly which glyph and which command to fix. Repeated coordinate
    /// pairs after `M` or `L` are accepted because SVG defines them as implied
    /// linetos and an editor may well produce them.
    static func parsePath(_ data: String, id: String) throws -> [PBRFont3D.Contour] {
        var contours = [PBRFont3D.Contour]()
        var current = PBRFont3D.Contour()
        var command: Character?
        var index = data.startIndex

        func finishSubpath() {
            if !current.isEmpty { contours.append(current) }
            current = []
        }

        while index < data.endIndex {
            let character = data[index]
            if character.isWhitespace || character == "," {
                index = data.index(after: index)
                continue
            }
            if character.isLetter {
                switch character {
                case "M":
                    finishSubpath()
                    command = "M"
                case "L":
                    command = "L"
                case "Z", "z":
                    finishSubpath()
                    command = nil
                default:
                    throw Error.unsupportedPathCommand(id: id, command: String(character))
                }
                index = data.index(after: index)
                continue
            }
            guard let active = command else {
                throw Error.malformedPathData(id: id, reason: "coordinates before any command")
            }
            let x = try number(&index, in: data, id: id)
            let y = try number(&index, in: data, id: id)
            current.append(PBRFont3D.Point(
                x: try coordinate(x, id: id), y: try coordinate(y, id: id)
            ))
            // A second pair under an `M` is an implied lineto, per the spec.
            if active == "M" { command = "L" }
        }
        finishSubpath()
        return contours
    }

    private static func number(
        _ index: inout String.Index, in data: String, id: String
    ) throws -> Double {
        while index < data.endIndex, data[index].isWhitespace || data[index] == "," {
            index = data.index(after: index)
        }
        let start = index
        if index < data.endIndex, data[index] == "-" || data[index] == "+" {
            index = data.index(after: index)
        }
        while index < data.endIndex, data[index].isNumber || data[index] == "." {
            index = data.index(after: index)
        }
        if index < data.endIndex, data[index] == "e" || data[index] == "E" {
            index = data.index(after: index)
            if index < data.endIndex, data[index] == "-" || data[index] == "+" {
                index = data.index(after: index)
            }
            while index < data.endIndex, data[index].isNumber {
                index = data.index(after: index)
            }
        }
        guard start < index, let value = Double(data[start ..< index]) else {
            throw Error.malformedPathData(id: id, reason: "expected a number")
        }
        return value
    }

    /// Rounds an SVG coordinate onto the format's integer vertex grid.
    /// Coordinates the exporter wrote are already integral; this exists so an
    /// editor that reformatted them as `12.0` still imports.
    private static func coordinate(_ value: Double, id: String) throws -> Int16 {
        let rounded = value.rounded()
        guard rounded >= Double(Int16.min), rounded <= Double(Int16.max) else {
            throw Error.coordinateOutOfRange(id: id, value: value)
        }
        return Int16(rounded)
    }
}
