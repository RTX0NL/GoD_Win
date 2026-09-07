//
//  PBRFont3D.swift
//  PBR
//
//  Parser and serializer for Battle Revolution's `.f3d` 3D font — the
//  extruded lettering the game uses for menu headings and the battle HUD,
//  as opposed to the 4bpp bitmap glyphs in `PBRFont`.
//
//  Layout (big-endian), verified on every glyph of both shipped files
//  (`fnt3dall.f3d`, 448 glyphs; `common_0034.f3d`, 482):
//
//  ```
//  File:   char[2] 'F3' | u16 glyphCount | u32 × glyphCount  entry offsets
//  Entry:  u16 characterCode | u32 payloadLength | payload
//  Payload (only when payloadLength > 0):
//     s16 xMin, xMax, yMin, yMax          bounding box
//     u16 stripCount
//       × { u16 vertexCount, vertexCount × (s16 x, s16 y, u8 u, u8 v) }
//     u16 contourCount
//       × { u16 vertexCount, vertexCount × (s16 x, s16 y) }
//     u16 0xFFFF                          terminator
//  ```
//
//  **Only the contours are stored here.** Everything else in the payload is
//  derived data, and re-deriving it is what makes the format editable —
//  a user who drags an outline node would otherwise have to hand-repair the
//  triangle strips and the bounding box to match:
//
//  - *Strips* are triangle strips (n vertices ⇒ n − 2 triangles) forming the
//    glyph's pre-tessellated front face. They are a tessellation of the
//    contours and carry no information the contours don't.
//  - *The bounding box* equals the extents of the contour vertices on all 899
//    non-empty glyphs across both files, without exception.
//  - *UVs* are a global planar projection rather than authored coordinates:
//    `u = round(x / 200 + 31.5)`, `v = round(y / 200 + 19.5)` reproduces
//    99.6% of the stored components exactly and the rest to within ±1. See
//    `Projection`.
//
//  Consequently a rebuilt `.f3d` is *not* byte-identical to the original —
//  our tessellator won't reproduce Nintendo's exact strip lengths, and the
//  ±1 UV cases won't come back. That is the project default (correctness
//  over byte-identical rebuild) and `.f3d` is not a declared 1:1 target.
//  What is guaranteed is that contours survive a round trip untouched and
//  that a re-serialized file re-parses.
//
//  Two things a reader is likely to assume and shouldn't:
//
//  - **Coordinates are x right, y *down*.** Established from geometry rather
//    than convention: in 'L' the foot (2654 units wide) sits in the high-y
//    half and the stem (839 units) in the low-y half, and an L's foot is at
//    the bottom.
//  - **Character codes are not globally sorted.** `fnt3dall.f3d` happens to
//    be ascending, `common_0034.f3d` is not, so a lookup must scan rather
//    than binary-search. The entry order is preserved verbatim for that
//    reason.
//

import Foundation
import GoDFoundation

public struct PBRFont3D: Equatable {
    public static let formatName = "f3d"

    /// Base name used for artifact filenames.
    public var name: String = "f3d"

    /// A vertex in glyph space: x right, y down.
    public struct Point: Equatable, Hashable, Codable {
        public let x: Int16
        public let y: Int16

        public init(x: Int16, y: Int16) {
            self.x = x
            self.y = y
        }
    }

    /// One closed loop of the glyph outline. The first vertex is repeated as
    /// the last on disk — verified on all 1758 contours in both files — and
    /// is kept that way rather than normalized away, so that a contour which
    /// *isn't* closed round-trips as authored instead of being silently
    /// repaired.
    public typealias Contour = [Point]

    public struct BoundingBox: Equatable {
        public let xMin: Int16
        public let xMax: Int16
        public let yMin: Int16
        public let yMax: Int16

        public init(xMin: Int16, xMax: Int16, yMin: Int16, yMax: Int16) {
            self.xMin = xMin
            self.xMax = xMax
            self.yMin = yMin
            self.yMax = yMax
        }
    }

    public struct Glyph: Equatable {
        /// Character code (Unicode).
        public let code: UInt16
        /// Outline loops: one outer boundary plus a hole per counter. 1–9 per
        /// glyph in the corpus. Empty for a glyph with no geometry, which the
        /// format writes as a zero-length payload (space, and 30 others).
        public let contours: [Contour]

        public init(code: UInt16, contours: [Contour]) {
            self.code = code
            self.contours = contours
        }

        /// A glyph with no outline at all. Written back as `payloadLength 0`,
        /// which is exactly how the corpus stores its blank glyphs.
        public var isBlank: Bool { contours.isEmpty }

        /// Extents of every contour vertex — the value the format stores as
        /// its bounding box, re-derived. `nil` when there are no vertices to
        /// take extents of.
        public var boundingBox: BoundingBox? {
            var xMin = Int16.max, xMax = Int16.min
            var yMin = Int16.max, yMax = Int16.min
            var any = false
            for contour in contours {
                for point in contour {
                    any = true
                    xMin = Swift.min(xMin, point.x)
                    xMax = Swift.max(xMax, point.x)
                    yMin = Swift.min(yMin, point.y)
                    yMax = Swift.max(yMax, point.y)
                }
            }
            guard any else { return nil }
            return BoundingBox(xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax)
        }
    }

    /// Glyphs in the file's own order. Load-bearing: codes are not sorted in
    /// `common_0034.f3d`, so the order is data rather than presentation.
    public let glyphs: [Glyph]

    public init(glyphs: [Glyph], name: String = "f3d") {
        self.glyphs = glyphs
        self.name = name
    }

    /// The planar projection that stands in for the stored UVs.
    ///
    /// The mapping is global — it depends only on a vertex's position in
    /// glyph space, not on which glyph it belongs to — which is what
    /// identifies it as a texture-atlas projection applied at export time
    /// rather than per-glyph authored coordinates. The constants are surfaced
    /// here, and written into the SVG manifest, so an editor can see the rule
    /// instead of having to infer it from the numbers.
    public enum Projection {
        /// Glyph units per texel.
        public static let unitsPerTexel: Double = 200
        /// Texel coordinate that glyph-space x = 0 maps to.
        public static let originU: Double = 31.5
        /// Texel coordinate that glyph-space y = 0 maps to.
        public static let originV: Double = 19.5

        /// Half-away-from-zero rounding, which matched 99.63% of stored
        /// components against 99.61% for round-half-to-even — a small margin,
        /// but measured rather than assumed.
        private static func texel(_ value: Double) -> UInt8 {
            let rounded = value.rounded()
            return UInt8(Swift.max(0, Swift.min(255, rounded)))
        }

        public static func uv(for point: Point) -> (u: UInt8, v: UInt8) {
            (
                u: texel(Double(point.x) / unitsPerTexel + originU),
                v: texel(Double(point.y) / unitsPerTexel + originV)
            )
        }
    }

    public enum Error: GoDError {
        case notA3DFontContainer(ErrorTrace = .init())
        case truncated(glyph: Int, ErrorTrace = .init())
        case payloadOverrun(glyph: Int, code: UInt16, ErrorTrace = .init())
        case missingTerminator(glyph: Int, code: UInt16, found: UInt16, ErrorTrace = .init())
        case payloadNotFullyConsumed(glyph: Int, code: UInt16, remaining: Int, ErrorTrace = .init())
        case tooManyGlyphs(count: Int, ErrorTrace = .init())

        public var description: String {
            switch self {
            case let .notA3DFontContainer(trace):
                return "Error: not a PBR 3D font (no 'F3' magic, or a glyph table that doesn't fit).\n\(trace)"
            case let .truncated(glyph, trace):
                return "Error: PBR 3D font glyph \(glyph) runs past the end of the file.\n\(trace)"
            case let .payloadOverrun(glyph, code, trace):
                return "Error: PBR 3D font glyph \(glyph) (U+\(Self.hex(code))) declares more "
                    + "geometry than its payload holds.\n\(trace)"
            case let .missingTerminator(glyph, code, found, trace):
                return "Error: PBR 3D font glyph \(glyph) (U+\(Self.hex(code))) ends with "
                    + "0x\(Self.hex(found)) where the 0xFFFF terminator should be.\n\(trace)"
            case let .payloadNotFullyConsumed(glyph, code, remaining, trace):
                return "Error: PBR 3D font glyph \(glyph) (U+\(Self.hex(code))) left \(remaining) "
                    + "bytes of its payload unread.\n\(trace)"
            case let .tooManyGlyphs(count, trace):
                return "Error: a PBR 3D font holds at most 65535 glyphs; this one has \(count).\n\(trace)"
            }
        }

        private static func hex(_ value: UInt16) -> String {
            String(format: "%04X", value)
        }
    }

    // MARK: - Parse

    public init(data: GoDData, name: String = "f3d") throws {
        data.setByteOrder(.big)
        self.name = name

        guard data.length >= 4,
              let magic = data.read(atAddress: 0, length: 2),
              magic.rawBytes == Array("F3".utf8) else {
            throw Error.notA3DFontContainer()
        }
        let glyphCount = Int(data.readSafely(atAddress: 2) as UInt16)
        let tableEnd = 4 + glyphCount * 4
        guard tableEnd <= data.length else { throw Error.notA3DFontContainer() }

        var parsed = [Glyph]()
        parsed.reserveCapacity(glyphCount)
        for index in 0 ..< glyphCount {
            let entry = Int(data.readSafely(atAddress: 4 + index * 4) as UInt32)
            guard entry >= tableEnd, entry + 6 <= data.length else {
                throw Error.truncated(glyph: index)
            }
            let code: UInt16 = data.readSafely(atAddress: entry)
            // The payload length, not the gap to the next entry, is what
            // bounds a payload. The two agree on every entry of both files,
            // but only one of them is stated by the entry itself, and entry
            // offsets are not guaranteed to be sorted.
            let payloadLength = Int(data.readSafely(atAddress: entry + 2) as UInt32)
            let payloadStart = entry + 6
            let payloadEnd = payloadStart + payloadLength
            guard payloadEnd <= data.length else { throw Error.truncated(glyph: index) }

            guard payloadLength > 0 else {
                parsed.append(Glyph(code: code, contours: []))
                continue
            }

            var cursor = payloadStart
            /// Advances the cursor, refusing to read past this glyph's payload
            /// — a bad count would otherwise walk into the next glyph and
            /// produce plausible-looking garbage.
            func take(_ bytes: Int) throws -> Int {
                guard bytes >= 0, cursor + bytes <= payloadEnd else {
                    throw Error.payloadOverrun(glyph: index, code: code)
                }
                let address = cursor
                cursor += bytes
                return address
            }

            // The bounding box is read and discarded: it equals the contour
            // extents everywhere in the corpus, and the writer re-derives it.
            _ = try take(8)

            // Strips are the tessellated front face. Skipped for the same
            // reason — they are a function of the contours below.
            let stripCountAddress = try take(2)
            let stripCount = Int(data.readSafely(atAddress: stripCountAddress) as UInt16)
            for _ in 0 ..< stripCount {
                let countAddress = try take(2)
                let vertexCount = Int(data.readSafely(atAddress: countAddress) as UInt16)
                _ = try take(vertexCount * 6)
            }

            let contourCountAddress = try take(2)
            let contourCount = Int(data.readSafely(atAddress: contourCountAddress) as UInt16)
            var contours = [Contour]()
            contours.reserveCapacity(contourCount)
            for _ in 0 ..< contourCount {
                let countAddress = try take(2)
                let vertexCount = Int(data.readSafely(atAddress: countAddress) as UInt16)
                let verticesAddress = try take(vertexCount * 4)
                var contour = Contour()
                contour.reserveCapacity(vertexCount)
                for vertex in 0 ..< vertexCount {
                    let address = verticesAddress + vertex * 4
                    contour.append(Point(
                        x: data.readSafely(atAddress: address),
                        y: data.readSafely(atAddress: address + 2)
                    ))
                }
                contours.append(contour)
            }

            let terminatorAddress = try take(2)
            let terminator: UInt16 = data.readSafely(atAddress: terminatorAddress)
            guard terminator == 0xFFFF else {
                throw Error.missingTerminator(glyph: index, code: code, found: terminator)
            }
            guard cursor == payloadEnd else {
                throw Error.payloadNotFullyConsumed(
                    glyph: index, code: code, remaining: payloadEnd - cursor
                )
            }

            parsed.append(Glyph(code: code, contours: contours))
        }
        self.glyphs = parsed
    }

    // MARK: - Serialize

    public var data: GoDData {
        get throws {
            guard glyphs.count <= 0xFFFF else {
                throw Error.tooManyGlyphs(count: glyphs.count)
            }

            // Entries are built standalone so the offset table is written from
            // real sizes rather than predicted ones.
            let bodies = glyphs.map(Self.entryBody(for:))

            var bytes = [UInt8]()
            bytes.append(contentsOf: Array("F3".utf8))
            Self.appendU16(glyphs.count, to: &bytes)
            var offset = 4 + bodies.count * 4
            for body in bodies {
                Self.appendU32(offset, to: &bytes)
                offset += body.count
            }
            for body in bodies { bytes.append(contentsOf: body) }
            return GoDData(byteStream: bytes, byteOrder: .big)
        }
    }

    /// One `u16 code | u32 payloadLength | payload` record.
    private static func entryBody(for glyph: Glyph) -> [UInt8] {
        var payload = [UInt8]()
        if !glyph.contours.isEmpty {
            let box = glyph.boundingBox
                // A glyph whose contours exist but hold no vertices has no
                // extents; the format has nowhere to say so, and a zero box is
                // the only honest answer.
                ?? BoundingBox(xMin: 0, xMax: 0, yMin: 0, yMax: 0)
            appendS16(box.xMin, to: &payload)
            appendS16(box.xMax, to: &payload)
            appendS16(box.yMin, to: &payload)
            appendS16(box.yMax, to: &payload)

            // Every triangle is emitted as its own three-vertex strip. The
            // engine draws strips, so this renders identically to Nintendo's
            // longer runs; only the file is bigger. Reproducing their exact
            // strip lengths would mean reimplementing their stripifier, which
            // buys nothing the format is being edited for.
            let triangles = PBRFont3DTessellator.triangulate(contours: glyph.contours)
            appendU16(triangles.count, to: &payload)
            for triangle in triangles {
                appendU16(3, to: &payload)
                for point in [triangle.a, triangle.b, triangle.c] {
                    appendS16(point.x, to: &payload)
                    appendS16(point.y, to: &payload)
                    let (u, v) = Projection.uv(for: point)
                    payload.append(u)
                    payload.append(v)
                }
            }

            appendU16(glyph.contours.count, to: &payload)
            for contour in glyph.contours {
                appendU16(contour.count, to: &payload)
                for point in contour {
                    appendS16(point.x, to: &payload)
                    appendS16(point.y, to: &payload)
                }
            }

            appendU16(0xFFFF, to: &payload)
        }

        var body = [UInt8]()
        appendU16(Int(glyph.code), to: &body)
        appendU32(payload.count, to: &body)
        body.append(contentsOf: payload)
        return body
    }

    private static func appendU16(_ value: Int, to array: inout [UInt8]) {
        array.append(UInt8((value >> 8) & 0xFF))
        array.append(UInt8(value & 0xFF))
    }

    private static func appendU32(_ value: Int, to array: inout [UInt8]) {
        array.append(UInt8((value >> 24) & 0xFF))
        array.append(UInt8((value >> 16) & 0xFF))
        array.append(UInt8((value >> 8) & 0xFF))
        array.append(UInt8(value & 0xFF))
    }

    private static func appendS16(_ value: Int16, to array: inout [UInt8]) {
        appendU16(Int(UInt16(bitPattern: value)), to: &array)
    }
}
