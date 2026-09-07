//
//  PBRFont3DTessellator.swift
//  PBR
//
//  Turns a `.f3d` glyph's outline loops into the triangles that become its
//  front face. Split out of `PBRFont3D` because it is a pure geometry routine
//  with no knowledge of the format — the same reasoning that keeps the LZ77
//  encoder out of the archive writers. It sits under PBR rather than in
//  `GoDFoundation` only because `.f3d` is currently its one caller; a second
//  consumer is the cue to move it.
//
//  **Even-odd, not winding.** Which way round a `.f3d` contour runs has not
//  been established, so nothing here reads a winding direction as intent.
//  Nesting depth decides instead: a loop enclosed by an even number of other
//  loops is a boundary, one enclosed by an odd number is a hole. That is the
//  same rule `fill-rule="evenodd"` gives the exported SVG, so the picture a
//  user edits and the geometry the game draws agree by construction.
//
//  The algorithm is ear clipping (Eberly, *Triangulation by Ear Clipping*)
//  with each hole bridged into its enclosing boundary first. The bridge is
//  chosen by search rather than by the usual leftmost-ray heuristic — the
//  shortest vertex pair that neither crosses any edge nor leaves the filled
//  region. That is slower and much easier to be sure of, which is the right
//  trade at these sizes: the largest real glyph has 9 loops and 40 vertices
//  in its longest one.
//
//  Two properties matter downstream:
//
//  - **Every output vertex is an input vertex.** Bridges reuse existing points
//    and no intersection point is ever invented, so the face can't drift off
//    the outline through rounding — `.f3d` coordinates are 16-bit integers
//    with no room to absorb a fractional vertex.
//  - **It always terminates.** A polygon with no valid ear left is possible
//    in principle, and rather than spin, the loop then clips its flattest
//    corner and carries on. No real glyph reaches that fallback.
//
//  Measured on both shipped files: all 899 non-blank glyphs tessellate to
//  exactly the area their outline encloses, with no hole left uncut and the
//  degenerate fallback never taken. `PBRFont3DTests` asserts that against an
//  area measured by scanline sweep rather than by this code.
//

import Foundation

public enum PBRFont3DTessellator {

    public struct Triangle: Equatable {
        public let a: PBRFont3D.Point
        public let b: PBRFont3D.Point
        public let c: PBRFont3D.Point

        public init(a: PBRFont3D.Point, b: PBRFont3D.Point, c: PBRFont3D.Point) {
            self.a = a
            self.b = b
            self.c = c
        }

        /// Twice the unsigned area. Doubled because the signed form is an
        /// integer cross product, and halving it would be the only place a
        /// fraction entered an otherwise exact computation.
        public var doubleArea: Int {
            abs(PBRFont3DTessellator.cross(a, b, c))
        }
    }

    /// Triangulates a glyph's outline under the even-odd rule.
    ///
    /// Never throws. A malformed outline yields fewer triangles rather than an
    /// error, because a glyph whose face can't be built is still a glyph whose
    /// outline must survive the round trip: the outline is the stored data and
    /// the face is derived from it, so the derivation failing must not take
    /// the source down with it.
    public static func triangulate(contours: [PBRFont3D.Contour]) -> [Triangle] {
        let loops = contours.flatMap(simpleLoops(from:))
        guard !loops.isEmpty else { return [] }

        // Depth = how many other loops enclose this one.
        var depths = [Int](repeating: 0, count: loops.count)
        var enclosers = [[Int]](repeating: [], count: loops.count)
        for i in loops.indices {
            for j in loops.indices where j != i {
                if encloses(loops[j], loops[i]) {
                    depths[i] += 1
                    enclosers[i].append(j)
                }
            }
        }

        // A hole belongs to the deepest loop that encloses it — its immediate
        // parent — which is what makes a counter inside a counter come out
        // right instead of every hole collapsing onto the outermost boundary.
        var holesByParent = [Int: [Int]]()
        for i in loops.indices where depths[i] % 2 == 1 {
            guard let parent = enclosers[i].max(by: { depths[$0] < depths[$1] }) else { continue }
            holesByParent[parent, default: []].append(i)
        }

        var triangles = [Triangle]()
        for i in loops.indices where depths[i] % 2 == 0 {
            // Ear clipping is written for a counter-clockwise polygon, so the
            // boundary is oriented that way and its holes the other way; the
            // bridge splice then leaves one consistently wound loop.
            let boundary = oriented(loops[i], counterClockwise: true)
            let holes = (holesByParent[i] ?? []).map { oriented(loops[$0], counterClockwise: false) }
            triangles.append(contentsOf: earClip(merge(holes: holes, into: boundary)))
        }
        return triangles
    }

    // MARK: - Loop preparation

    /// Reduces one stored contour to the simple loops it actually traces.
    ///
    /// Drops the repeated closing vertex and any consecutive duplicates, then
    /// splits at any vertex the loop visits twice. That second step is not
    /// tidying: `U+2603` is one contour that walks the snowman's body, up
    /// through a three-vertex seam into the head, and back down the same
    /// seam — a figure eight whose two lobes wind opposite ways. Treated as a
    /// single loop it has a signed area of *body minus head* and no valid ear
    /// sequence; split at the repeated vertices it is two ordinary loops that
    /// tessellate exactly. The stored contour keeps its original shape — this
    /// is only the working copy.
    private static func simpleLoops(from contour: PBRFont3D.Contour) -> [[PBRFont3D.Point]] {
        var points = [PBRFont3D.Point]()
        for point in contour where points.last != point {
            points.append(point)
        }
        while points.count > 1, points.first == points.last {
            points.removeLast()
        }
        guard points.count >= 3 else { return [] }

        var finished = [[PBRFont3D.Point]]()
        var pending = [points]
        while let current = pending.popLast() {
            var seen = [PBRFont3D.Point: Int]()
            var repeatedAt: (first: Int, second: Int)?
            for (index, point) in current.enumerated() {
                if let first = seen[point] {
                    repeatedAt = (first, index)
                    break
                }
                seen[point] = index
            }
            guard let cut = repeatedAt else {
                // A zero-area loop contributes nothing and has no orientation
                // to take, so it is dropped rather than carried.
                if current.count >= 3, signedDoubleArea(current) != 0 {
                    finished.append(current)
                }
                continue
            }
            // Both halves are strictly shorter than the loop they came from,
            // so this terminates.
            pending.append(Array(current[cut.first ..< cut.second]))
            pending.append(Array(current[..<cut.first]) + Array(current[cut.second...]))
        }
        return finished
    }

    /// Twice the signed area under the shoelace convention; positive is
    /// counter-clockwise. Exact — 16-bit inputs can't overflow `Int`.
    private static func signedDoubleArea(_ loop: [PBRFont3D.Point]) -> Int {
        var total = 0
        for i in loop.indices {
            let a = loop[i]
            let b = loop[(i + 1) % loop.count]
            total += Int(a.x) * Int(b.y) - Int(b.x) * Int(a.y)
        }
        return total
    }

    private static func oriented(
        _ loop: [PBRFont3D.Point], counterClockwise: Bool
    ) -> [PBRFont3D.Point] {
        (signedDoubleArea(loop) > 0) == counterClockwise ? loop : loop.reversed()
    }

    /// Whether `outer` encloses `inner`, decided by a vote of `inner`'s
    /// vertices rather than by testing one of them.
    ///
    /// A single sample is what a well-behaved outline needs, since loops that
    /// don't cross are wholly in or wholly out. Real glyphs aren't that
    /// well behaved: `U+30CD` is two strokes that meet at exactly one shared
    /// vertex, and a ray cast from a point sitting *on* the other loop's
    /// boundary answers arbitrarily. Sampling every vertex makes one such
    /// coincidence a minority.
    private static func encloses(_ outer: [PBRFont3D.Point], _ inner: [PBRFont3D.Point]) -> Bool {
        let votes = inner.filter { contains(outer, x: Double($0.x), y: Double($0.y)) }.count
        return votes * 2 > inner.count
    }

    /// Even-odd ray-casting containment test. Doubles rather than exact
    /// arithmetic because the caller passes edge midpoints, which are half-
    /// integers; the inputs are 16-bit, so the intersection can never land
    /// close enough to a vertex for the precision to change the answer.
    private static func contains(_ loop: [PBRFont3D.Point], x: Double, y: Double) -> Bool {
        var inside = false
        var j = loop.count - 1
        for i in loop.indices {
            let ax = Double(loop[i].x), ay = Double(loop[i].y)
            let bx = Double(loop[j].x), by = Double(loop[j].y)
            if (ay > y) != (by > y), x < (bx - ax) * (y - ay) / (by - ay) + ax {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // MARK: - Hole bridging

    /// Splices every hole into the boundary through a two-way bridge, leaving
    /// one simple loop that ear clipping can consume.
    ///
    /// Holes are merged leftmost-first purely for determinism. After each
    /// splice the merged loop's own even-odd interior is exactly "inside the
    /// boundary and outside everything cut out so far", so the next bridge can
    /// be validated against that one loop plus the holes still waiting —
    /// no separate bookkeeping of what has already been removed.
    ///
    /// A hole with no valid bridge is left uncut rather than forced. That
    /// loses the counter on a pathological glyph; forcing it would produce
    /// overlapping triangles across the whole face.
    private static func merge(
        holes: [[PBRFont3D.Point]], into boundary: [PBRFont3D.Point]
    ) -> [PBRFont3D.Point] {
        var pending = holes.sorted { lhs, rhs in
            (lhs.map(\.x).min() ?? 0) < (rhs.map(\.x).min() ?? 0)
        }
        var result = boundary

        while !pending.isEmpty {
            let hole = pending.removeFirst()
            guard let bridge = bridge(from: hole, to: result, avoiding: pending) else { continue }
            // result[0...b] + the whole hole starting and ending at hole[h]
            // + back to result[b]: the two repeated vertices are the bridge,
            // walked once in each direction.
            var spliced = Array(result[0 ... bridge.loopIndex])
            for step in 0 ..< hole.count {
                spliced.append(hole[(bridge.holeIndex + step) % hole.count])
            }
            spliced.append(hole[bridge.holeIndex])
            spliced.append(result[bridge.loopIndex])
            spliced.append(contentsOf: result[(bridge.loopIndex + 1)...])
            result = spliced
        }
        return result
    }

    /// The shortest vertex pair joining `hole` to `loop` that is a legal
    /// bridge: it crosses no edge of the loop, of the hole, or of any hole
    /// still to be merged, and its midpoint lies in the filled region.
    ///
    /// The midpoint test is what rules out a bridge that leaves the shape
    /// without crossing anything — it can happen when the segment exits and
    /// re-enters exactly through vertices, which the crossing test deliberately
    /// tolerates because a bridge is anchored on vertices by construction.
    private static func bridge(
        from hole: [PBRFont3D.Point],
        to loop: [PBRFont3D.Point],
        avoiding pending: [[PBRFont3D.Point]]
    ) -> (loopIndex: Int, holeIndex: Int)? {
        var candidates = [(loopIndex: Int, holeIndex: Int, distance: Int)]()
        candidates.reserveCapacity(loop.count * hole.count)
        for l in loop.indices {
            for h in hole.indices {
                let dx = Int(loop[l].x) - Int(hole[h].x)
                let dy = Int(loop[l].y) - Int(hole[h].y)
                candidates.append((l, h, dx * dx + dy * dy))
            }
        }
        candidates.sort { $0.distance < $1.distance }

        for candidate in candidates {
            let a = loop[candidate.loopIndex]
            let b = hole[candidate.holeIndex]
            guard a != b else { continue }
            if crossesAnyEdge(a, b, of: loop) { continue }
            if crossesAnyEdge(a, b, of: hole) { continue }
            if pending.contains(where: { crossesAnyEdge(a, b, of: $0) }) { continue }
            let midX = (Double(a.x) + Double(b.x)) / 2
            let midY = (Double(a.y) + Double(b.y)) / 2
            guard contains(loop, x: midX, y: midY),
                  !contains(hole, x: midX, y: midY),
                  !pending.contains(where: { contains($0, x: midX, y: midY) }) else { continue }
            return (candidate.loopIndex, candidate.holeIndex)
        }
        return nil
    }

    private static func crossesAnyEdge(
        _ a: PBRFont3D.Point, _ b: PBRFont3D.Point, of loop: [PBRFont3D.Point]
    ) -> Bool {
        loop.indices.contains { i in
            segmentsCross(a, b, loop[i], loop[(i + 1) % loop.count])
        }
    }

    /// Segment intersection, with contact at a shared vertex not counting.
    /// A bridge ends on a vertex of both loops, so meeting there is the
    /// intended outcome rather than a crossing; anything else that touches —
    /// including a segment merely grazing a vertex — does count, because it
    /// would leave the spliced loop self-touching and the ear clipper with no
    /// valid ear at that point.
    private static func segmentsCross(
        _ a: PBRFont3D.Point, _ b: PBRFont3D.Point,
        _ c: PBRFont3D.Point, _ d: PBRFont3D.Point
    ) -> Bool {
        if a == c || a == d || b == c || b == d { return false }
        let d1 = cross(a, b, c), d2 = cross(a, b, d)
        let d3 = cross(c, d, a), d4 = cross(c, d, b)
        if d1 != 0, d2 != 0, d3 != 0, d4 != 0 {
            return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0))
        }
        if d1 == 0, isBetween(a, b, c) { return true }
        if d2 == 0, isBetween(a, b, d) { return true }
        if d3 == 0, isBetween(c, d, a) { return true }
        if d4 == 0, isBetween(c, d, b) { return true }
        return false
    }

    /// Whether a point known to be collinear with `a`–`b` lies within it.
    private static func isBetween(
        _ a: PBRFont3D.Point, _ b: PBRFont3D.Point, _ p: PBRFont3D.Point
    ) -> Bool {
        min(a.x, b.x) <= p.x && p.x <= max(a.x, b.x)
            && min(a.y, b.y) <= p.y && p.y <= max(a.y, b.y)
    }

    // MARK: - Ear clipping

    private static func earClip(_ polygon: [PBRFont3D.Point]) -> [Triangle] {
        var loop = polygon
        var triangles = [Triangle]()
        triangles.reserveCapacity(max(0, loop.count - 2))

        while loop.count > 3 {
            var clipped = false
            for i in loop.indices where isEar(at: i, in: loop) {
                triangles.append(Triangle(
                    a: loop[(i + loop.count - 1) % loop.count],
                    b: loop[i],
                    c: loop[(i + 1) % loop.count]
                ))
                loop.remove(at: i)
                clipped = true
                break
            }
            guard !clipped else { continue }
            // No ear exists, which means the outline touches or crosses
            // itself. Drop the flattest corner: it contributes the least area,
            // so the face degrades locally instead of the loop hanging.
            guard let flattest = loop.indices.min(by: {
                abs(cornerCross(at: $0, in: loop)) < abs(cornerCross(at: $1, in: loop))
            }) else { break }
            loop.remove(at: flattest)
        }

        if loop.count == 3, cross(loop[0], loop[1], loop[2]) != 0 {
            triangles.append(Triangle(a: loop[0], b: loop[1], c: loop[2]))
        }
        return triangles
    }

    private static func cornerCross(at index: Int, in loop: [PBRFont3D.Point]) -> Int {
        cross(
            loop[(index + loop.count - 1) % loop.count],
            loop[index],
            loop[(index + 1) % loop.count]
        )
    }

    /// Whether the corner at `index` can be clipped off as a triangle.
    ///
    /// The containment test is *inclusive* and applies *only to reflex
    /// vertices*, and both halves of that are load-bearing:
    ///
    /// - Inclusive, because these outlines are full of axis-aligned edges and
    ///   a reflex corner very often lands exactly on a candidate ear's edge
    ///   rather than inside it. A strict test called those ears valid and
    ///   emitted triangles that overlapped the rest of the glyph — 'H' came
    ///   out 45% over its own area.
    /// - Reflex only, because an inclusive test applied to every vertex would
    ///   reject ears that merely touch a convex corner, which can't overlap
    ///   anything. That includes both copies of a bridge vertex, so a blanket
    ///   inclusive test would strand every polygon with a hole in it.
    private static func isEar(at index: Int, in loop: [PBRFont3D.Point]) -> Bool {
        // Convex, and strictly so: a collinear corner has no area, and
        // clipping it would emit a degenerate triangle.
        guard cornerCross(at: index, in: loop) > 0 else { return false }
        let previous = (index + loop.count - 1) % loop.count
        let next = (index + 1) % loop.count
        let a = loop[previous], b = loop[index], c = loop[next]
        for i in loop.indices where i != index && i != previous && i != next {
            guard cornerCross(at: i, in: loop) <= 0 else { continue }
            let p = loop[i]
            if cross(a, b, p) >= 0, cross(b, c, p) >= 0, cross(c, a, p) >= 0 { return false }
        }
        return true
    }

    // MARK: - Primitives

    /// Twice the signed area of triangle abc; positive when counter-clockwise.
    /// Exact: 16-bit inputs can't overflow `Int`.
    static func cross(_ a: PBRFont3D.Point, _ b: PBRFont3D.Point, _ c: PBRFont3D.Point) -> Int {
        (Int(b.x) - Int(a.x)) * (Int(c.y) - Int(a.y))
            - (Int(b.y) - Int(a.y)) * (Int(c.x) - Int(a.x))
    }
}
