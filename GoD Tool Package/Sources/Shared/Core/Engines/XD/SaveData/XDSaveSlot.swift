//
//  XDSaveSlot.swift
//
//  Parsed view over a single decrypted 0x28000-byte Pokémon XD save
//  slot. Layout cross-checked against PKHeX (`SAV3XD.cs` +
//  `XDCrypto.cs`) — that's our source of truth, since the disasm-only
//  derivation got several offsets wrong.
//
//  Slot layout (post-decrypt):
//    0x00..0x08  plaintext header (magic + counter)
//    0x08..0x10  cipher key seed (4 × u16 BE) — also plaintext
//    0x10..0x20  body checksum tags (4 × u32 BE in PKHeX's reversed
//                halfword order; XOR-cleared during checksum recompute)
//    0x20..0x40  16 × u16 BE sub-block sizes
//    0x40..0x80  16 × u32 BE sub-block offsets, encoded as
//                `(low_halfword << 0) | (high_halfword << 16)` —
//                both halfwords are big-endian u16 reads at +0 and +2.
//                Resulting offset is relative to slot+0xA8.
//    0x80..0xA8  unused / padding (40 bytes)
//    0xA8..end   sub-block payloads, packed back-to-back per the
//                offset table.
//
//  PKHeX names six of the 16 sub-blocks:
//    0  Config           — language, region, GC version
//    1  Trainer1         — player profile, party (Trainer1 + 0x30)
//    2  PCBox            — storage boxes
//    4  Daycare          — Day-Care state
//    5  StrategyMemo     — Pokédex / Memo entries
//    7  ShadowInfo       — Shadow Pokémon table
//   14  Purifier         — Purify Chamber (commented out in PKHeX)
//  The remaining indices are exposed as `subBlock(N)` for downstream
//  engine work to name + map to struct definitions.
//
//  Round-trip: this type retains the raw slot bytes verbatim and
//  rebuilds them in `assemble()` byte-identically. Sub-block edits
//  via `applySubBlock(_:bytes:)` go through `raw` in place; TOC
//  repacking + size-field updates happen alongside the section→
//  struct mapping work in a future task (the JSON dump path doesn't
//  need them yet — it reads sub-block bytes via the existing TOC).
//

import Foundation
import GoDFoundation

public struct XDSaveSlot: Equatable {
    public static let slotSize: Int = 0x28000

    /// Plaintext slot magic at +0x00..0x01 — `01 01`. Byte +0x02 varies
    /// by region/version (`01` on US/PAL builds, `00` on JP) so it is NOT
    /// part of the validated magic — it round-trips via the captured
    /// header region regardless.
    public static let magic: [UInt8] = [0x01, 0x01]

    /// Number of sub-block entries — fixed at 16 across all observed
    /// XD saves (PKHeX hardcodes this).
    public static let subBlockCount: Int = 16

    /// Offset of the per-sub-block size table within the slot. Each
    /// entry is a u16 BE, total 32 bytes.
    public static let sizeTableOffset: Int = 0x20
    /// Offset of the per-sub-block offset table. Each entry is 4 bytes
    /// — two big-endian u16s combined with the high halfword shifted
    /// up by 16. Total 64 bytes.
    public static let offsetTableOffset: Int = 0x40
    /// Base address sub-block offsets are computed relative to.
    public static let subBlockBaseOffset: Int = 0xA8

    /// Configurable slot-format parameters. Defaults (`.stock`) match
    /// the retail XD save format (16 sub-blocks, size table at 0x20,
    /// offset table at 0x40, body base at 0xA8). A ROM mod that changes
    /// the slot's sub-block layout can override these via the engine's
    /// `saveSlotLayout` — it's on the modder to patch the game's own
    /// save code to match. The four values are all that the TOC read/
    /// write and the from-scratch assembler need to relocate/resize.
    public struct Layout: Codable, Equatable {
        /// Number of sub-block TOC entries. NOT read from persisted
        /// config — the dump/build set it from `saveSections.count` so
        /// the section list is the single source of truth for the count
        /// (add a section spec and the count follows automatically).
        public var subBlockCount: Int = XDSaveSlot.subBlockCount
        public var sizeTableOffset: Int = XDSaveSlot.sizeTableOffset
        public var offsetTableOffset: Int = XDSaveSlot.offsetTableOffset
        public var subBlockBaseOffset: Int = XDSaveSlot.subBlockBaseOffset

        public init(
            subBlockCount: Int = XDSaveSlot.subBlockCount,
            sizeTableOffset: Int = XDSaveSlot.sizeTableOffset,
            offsetTableOffset: Int = XDSaveSlot.offsetTableOffset,
            subBlockBaseOffset: Int = XDSaveSlot.subBlockBaseOffset
        ) {
            self.subBlockCount = subBlockCount
            self.sizeTableOffset = sizeTableOffset
            self.offsetTableOffset = offsetTableOffset
            self.subBlockBaseOffset = subBlockBaseOffset
        }

        /// Only the TOC table offsets are persisted; `subBlockCount` is
        /// derived from `saveSections.count` at runtime.
        private enum CodingKeys: String, CodingKey {
            case sizeTableOffset, offsetTableOffset, subBlockBaseOffset
        }

        /// Returns a copy with the sub-block count set (from the section list).
        public func with(subBlockCount: Int) -> Layout {
            var copy = self
            copy.subBlockCount = subBlockCount
            return copy
        }

        /// Retail XD save format (TOC offsets; count follows the section list).
        public static let stock = Layout()
    }

    /// Plaintext slot header. Only the first 8 bytes of a slot are
    /// unencrypted (magic + reserved + counter) — and they're *not*
    /// the cipher key seed (PKHeX's `XDCrypto.DecryptSlot` reads keys
    /// from `slot[0x08..0x10]`, a separate plaintext field that's
    /// also covered by the body checksum but not encrypted).
    public struct Header: Codable, Equatable {
        public var magic: [UInt8]            // [0x01, 0x01, 0x01]
        public var reserved: UInt8           // +0x03 — observed `0x00`
        public var counter: UInt32           // +0x04 — plaintext save counter

        public init(magic: [UInt8], reserved: UInt8, counter: UInt32) {
            self.magic = magic
            self.reserved = reserved
            self.counter = counter
        }
    }

    /// PKHeX's named sub-blocks. The opaque entries (3, 6, 8..13, 15)
    /// don't have known semantics yet; they're reachable via
    /// `XDSaveSlot.subBlock(at:)` indexed by integer.
    public enum NamedSubBlock: Int, Codable, CaseIterable, Equatable {
        case config        = 0
        case trainer1      = 1
        case pcBox         = 2
        case daycare       = 4
        case strategyMemo  = 5
        case shadowInfo    = 7
        case purifier      = 14
    }

    /// Raw slot bytes — preserved verbatim so `assemble()` round-trips
    /// byte-identically.
    public var raw: GoDData
    public let header: Header
    /// Slot-format parameters this slot was parsed with.
    public let layout: Layout

    public init(raw: GoDData, layout: Layout = .stock) throws {
        guard raw.length == XDSaveSlot.slotSize else {
            throw XDSaveSlotError.invalidSlotSize(expected: XDSaveSlot.slotSize, actual: raw.length)
        }
        raw.setByteOrder(.big)

        let bytes = raw.rawBytes
        let magic = [bytes[0x00], bytes[0x01]]
        guard magic == XDSaveSlot.magic else {
            throw XDSaveSlotError.badMagic(found: [bytes[0x00], bytes[0x01], bytes[0x02]])
        }

        let reserved = bytes[0x03]
        let counter: UInt32 = raw.readSafely(atAddress: 0x04)

        self.raw = raw
        self.header = Header(magic: magic, reserved: reserved, counter: counter)
        self.layout = layout
    }

    public func assemble() -> GoDData {
        return raw
    }

    // MARK: - Sub-block table

    /// Sub-block size at `index` (0..<16). Reads the u16 BE at
    /// `slot[0x20 + 2*index]`. PKHeX doesn't apply caps to these
    /// values when reading, so we don't either.
    public func subBlockSize(at index: Int) -> Int {
        precondition(index >= 0 && index < layout.subBlockCount)
        let off = layout.sizeTableOffset + index * 2
        let v: UInt16 = raw.readSafely(atAddress: off)
        return Int(v)
    }

    /// Sub-block absolute offset within the slot. Mirrors PKHeX's
    /// quirky encoding:
    ///     subOffset = u16BE(slot[0x40+4i]) | (u16BE(slot[0x40+4i+2]) << 16)
    ///     absolute  = subOffset + 0xA8
    public func subBlockOffset(at index: Int) -> Int {
        precondition(index >= 0 && index < layout.subBlockCount)
        let base = layout.offsetTableOffset + index * 4
        let lo: UInt16 = raw.readSafely(atAddress: base)
        let hi: UInt16 = raw.readSafely(atAddress: base + 2)
        return Int(UInt32(lo) | (UInt32(hi) << 16)) + layout.subBlockBaseOffset
    }

    /// Reads the bytes for sub-block at `index`. Returns nil only
    /// when the resulting slice would land out of bounds.
    public func subBlockBytes(at index: Int) -> GoDData? {
        let off = subBlockOffset(at: index)
        let size = subBlockSize(at: index)
        guard size > 0, off + size <= raw.length else { return nil }
        return raw.read(atAddress: UInt(off), length: UInt(size))
    }

    /// Convenience: same as `subBlockBytes(at:)` keyed by the named
    /// sub-block.
    public func subBlockBytes(_ name: NamedSubBlock) -> GoDData? {
        return subBlockBytes(at: name.rawValue)
    }
}

public extension XDSaveSlot {

    /// Body region — bytes after the slot header tables.
    static let bodyStartOffset: Int = subBlockBaseOffset    // 0xA8
    /// One past the last byte of the encrypted region.
    /// Matches `XDSaveCipher.cipherRange.upperBound` (0x27FD8) so the
    /// repacked body always covers the same byte range the cipher
    /// later runs over.
    static let bodyEndOffset: Int = 0x27FD8

    /// Per-save sub-block placement uses a `16k + 8` lattice within
    /// the slot. Empirically every section in the wild starts at
    /// such an offset (relative to slot start) — `0xA8`, `0x148`,
    /// `0x1158`, `0x3408`, ... all `≡ 8 (mod 16)`. The alignment
    /// constant comes from the body-base offset (`0xA8 mod 16 = 8`)
    /// plus the in-game allocator's 16-byte minimum gap between
    /// neighbouring sections.
    static let sectionAlignment: Int = 16
    static let sectionAlignmentPhase: Int = 8
    /// Minimum byte gap from the end of one section to the start of
    /// the next, before alignment rounding kicks in.
    static let interSectionMinGap: Int = 16

    /// Returns the offset where a new section should start, given
    /// the end offset of the previous section. Implements the rule
    /// `nextStart = align_up_to_(16k+8)(prevEnd + 16)`.
    static func nextSectionStart(after prevEnd: Int) -> Int {
        let target = prevEnd + interSectionMinGap
        let phase = sectionAlignmentPhase
        let align = sectionAlignment
        let delta = (target - phase) % align
        let normalised = delta < 0 ? delta + align : delta
        return normalised == 0 ? target : target + (align - normalised)
    }

    /// Reads the slot's 16 sub-block (offset, size) tuples in
    /// *placement order* — i.e. sorted by current physical offset
    /// rather than by sub-block index. This is the order the in-game
    /// `_memcardDuplicateSaveData_multi` Fisher-Yates ended up
    /// producing on the load-time save, and what the rebuild needs
    /// to follow when recomputing offsets so the permutation is
    /// preserved.
    func sectionsInPlacementOrder() -> [(index: Int, offset: Int, size: Int)] {
        var triples: [(index: Int, offset: Int, size: Int)] = []
        for index in 0..<layout.subBlockCount {
            let size = subBlockSize(at: index)
            guard size > 0 else { continue }
            triples.append((index: index, offset: subBlockOffset(at: index), size: size))
        }
        triples.sort { $0.offset < $1.offset }
        return triples
    }

    /// Repacks the slot, preserving the load-time placement order
    /// while recomputing offsets from each section's *current* size.
    ///
    /// `sectionOverrides` lets the caller substitute the bytes for a
    /// specific sub-block index — the override's `length` becomes
    /// the new size, and the rest of the layout shifts to make room.
    /// Empty dictionary = pure round-trip from the loaded slot;
    /// recomputed offsets equal load-time offsets, so the output is
    /// byte-identical to `raw`.
    ///
    /// Inter-section "gap bytes" (the data between one section's end
    /// and the next section's aligned start) are preserved by reading
    /// from the original slot at the same body-relative position.
    /// When edits shift sections, gap bytes stay attached to the
    /// section they used to follow — i.e. they ride along with their
    /// preceding section in the new layout.
    func repacked(sectionOverrides: [Int: GoDData] = [:]) throws -> GoDData {
        let originalBytes = raw.rawBytes
        var output = originalBytes  // start from original; we'll patch tables and body

        // Walk in placement order. For each section, decide its new
        // size (override length or original), compute the new offset
        // via the alignment rule, and patch:
        //   - the size table at slot[0x20..0x40]
        //   - the offset table at slot[0x40..0x80]
        //   - the section payload at the new offset
        //   - the gap bytes that originally followed this section
        let triples = sectionsInPlacementOrder()

        // Stage 1: clear the body so we don't leave stale bytes
        // lying around when sections shift left. Header + tables
        // are written in stage 2.
        for i in layout.subBlockBaseOffset..<XDSaveSlot.bodyEndOffset {
            output[i] = 0
        }

        // Stage 2: place each section, copy its trailing gap, and
        // record the new offset/size for the table writes at end.
        var newOffsets: [Int: Int] = [:]
        var newSizes:  [Int: Int] = [:]
        var cursor = layout.subBlockBaseOffset

        for (placementIdx, triple) in triples.enumerated() {
            let index = triple.index
            let oldOffset = triple.offset
            let oldSize = triple.size

            // Choose the source bytes for this section.
            let payloadBytes: [UInt8]
            let newSize: Int
            if let override = sectionOverrides[index] {
                payloadBytes = override.rawBytes
                newSize = payloadBytes.count
            } else {
                let end = oldOffset + oldSize
                guard end <= originalBytes.count else {
                    throw XDSaveSlotError.invalidSlotSize(
                        expected: XDSaveSlot.slotSize, actual: originalBytes.count
                    )
                }
                payloadBytes = Array(originalBytes[oldOffset..<end])
                newSize = oldSize
            }

            // Place the section. Guard against an enlarged edited
            // section running past the slot's body region (or the fixed
            // output array) — writing beyond would trap on index.
            guard cursor + payloadBytes.count <= output.count,
                  cursor + payloadBytes.count <= XDSaveSlot.bodyEndOffset else {
                throw XDSaveSlotError.repackOverflow(
                    section: index,
                    needed: cursor + payloadBytes.count,
                    available: min(output.count, XDSaveSlot.bodyEndOffset)
                )
            }
            for (i, byte) in payloadBytes.enumerated() {
                output[cursor + i] = byte
            }
            newOffsets[index] = cursor
            newSizes[index] = newSize

            // Carry the original trailing gap. The gap's length is
            // (next section's old start) − (this section's old end).
            // For the LAST placed section, the gap runs to bodyEnd.
            let gapStart = oldOffset + oldSize
            let gapEnd: Int
            if placementIdx + 1 < triples.count {
                gapEnd = triples[placementIdx + 1].offset
            } else {
                gapEnd = XDSaveSlot.bodyEndOffset
            }
            let gapLength = max(0, gapEnd - gapStart)
            // Where the gap should land in the new layout: starts at
            // (cursor + newSize), ends at the alignment-rule-determined
            // start of the next section (or bodyEnd if last).
            let nextCursor = (placementIdx + 1 < triples.count)
                ? XDSaveSlot.nextSectionStart(after: cursor + newSize)
                : XDSaveSlot.bodyEndOffset
            let availableGap = nextCursor - (cursor + newSize)
            let copyLength = min(gapLength, max(0, availableGap))
            if copyLength > 0 && gapStart + copyLength <= originalBytes.count {
                let dst = cursor + newSize
                guard dst + copyLength <= output.count,
                      dst + copyLength <= XDSaveSlot.bodyEndOffset else {
                    throw XDSaveSlotError.repackOverflow(
                        section: index,
                        needed: dst + copyLength,
                        available: min(output.count, XDSaveSlot.bodyEndOffset)
                    )
                }
                for i in 0..<copyLength {
                    output[dst + i] = originalBytes[gapStart + i]
                }
            }

            cursor = nextCursor
        }

        // Stage 3: rewrite the size table at slot[0x20..0x40] and the
        // offset table at slot[0x40..0x80]. The tables span all 16
        // indices including the zero-size ones (which keep their
        // existing entries — this matches how the in-game allocator
        // leaves untouched slots alone).
        for index in 0..<layout.subBlockCount {
            // Size table: u16 BE at slot[0x20 + 2*index].
            let size = newSizes[index] ?? subBlockSize(at: index)
            let sizeOffset = layout.sizeTableOffset + index * 2
            output[sizeOffset]     = UInt8((size >> 8) & 0xFF)
            output[sizeOffset + 1] = UInt8(size & 0xFF)

            // Offset table: u32 stored as (lowHalf, highHalf), each
            // u16 BE, at slot[0x40 + 4*index].
            let absoluteOffset = newOffsets[index] ?? subBlockOffset(at: index)
            let relativeOffset = UInt32(absoluteOffset - layout.subBlockBaseOffset)
            let lo = UInt16(relativeOffset & 0xFFFF)
            let hi = UInt16((relativeOffset >> 16) & 0xFFFF)
            let offBase = layout.offsetTableOffset + index * 4
            output[offBase]     = UInt8((lo >> 8) & 0xFF)
            output[offBase + 1] = UInt8(lo & 0xFF)
            output[offBase + 2] = UInt8((hi >> 8) & 0xFF)
            output[offBase + 3] = UInt8(hi & 0xFF)
        }

        return GoDData(byteStream: output, byteOrder: .big)
    }

    /// Builds a complete decrypted slot *from scratch* out of a captured
    /// header region plus a fresh set of section payloads.
    ///
    /// `headerRegion` is the verbatim `slot[0x00..0xA8]` captured at dump
    /// time. It is carried as opaque metadata because it is too
    /// intertwined with the game's on-card format to safely regenerate:
    /// the cipher key seed (`0x08`), the running-sum checksum tags
    /// (`0x10`, overwritten at encrypt), the 24-entry TOC and scattered
    /// size fields (`0x18..0x98`) the game's `memcardGetMultiSaveDataToSTRUCT`
    /// reads to locate each sub-block, and its 8-byte tail. Everything
    /// *editable* — the sub-block payloads — is supplied fresh in
    /// `sections`; nothing about the sub-block bytes is inherited.
    ///
    /// The inter-sub-block gaps and the large unused tail after the last
    /// sub-block are **left zero**. Per the XD disassembly
    /// (`_memcardStoreSaveData_multi`) those bytes are non-semantic
    /// leftover the game carries forward from its reused I/O buffer — the
    /// game never reads them and re-randomises them each save — so
    /// zeroing them and recomputing the checksum yields a functionally
    /// identical, game-valid slot.
    ///
    /// Each non-zero-size index in the captured TOC must be supplied in
    /// `sections`, and its byte length must equal the TOC size for that
    /// index; a mismatch throws `sectionSizeMismatch`.
    static func assembled(headerRegion: GoDData, sections: [Int: GoDData], layout: Layout = .stock) throws -> GoDData {
        let headerBytes = headerRegion.rawBytes
        guard headerBytes.count == layout.subBlockBaseOffset else {
            throw XDSaveSlotError.invalidHeaderRegion(
                expected: layout.subBlockBaseOffset, actual: headerBytes.count
            )
        }

        var output = [UInt8](repeating: 0, count: XDSaveSlot.slotSize)
        for i in 0..<layout.subBlockBaseOffset { output[i] = headerBytes[i] }

        for index in 0..<layout.subBlockCount {
            // Size table: u16 BE at 0x20 + 2*index.
            let sizeOff = layout.sizeTableOffset + index * 2
            let size = Int(UInt16(headerBytes[sizeOff]) << 8 | UInt16(headerBytes[sizeOff + 1]))
            guard size > 0 else { continue }

            // Offset table: (lo u16 BE, hi u16 BE) at 0x40 + 4*index,
            // combined as low | (high << 16), relative to 0xA8.
            let offBase = layout.offsetTableOffset + index * 4
            let lo = UInt32(UInt16(headerBytes[offBase]) << 8 | UInt16(headerBytes[offBase + 1]))
            let hi = UInt32(UInt16(headerBytes[offBase + 2]) << 8 | UInt16(headerBytes[offBase + 3]))
            let offset = Int(lo | (hi << 16)) + layout.subBlockBaseOffset

            guard let section = sections[index] else {
                throw XDSaveSlotError.missingSection(index: index, size: size)
            }
            guard section.length == size else {
                throw XDSaveSlotError.sectionSizeMismatch(
                    index: index, expected: size, actual: section.length
                )
            }
            guard offset + size <= XDSaveSlot.slotSize else {
                throw XDSaveSlotError.repackOverflow(
                    section: index, needed: offset + size, available: XDSaveSlot.slotSize
                )
            }
            let payload = section.rawBytes
            for i in 0..<size { output[offset + i] = payload[i] }
        }

        return GoDData(byteStream: output, byteOrder: .big)
    }
}

public enum XDSaveSlotError: Error, CustomStringConvertible {
    case invalidSlotSize(expected: Int, actual: Int)
    case badMagic(found: [UInt8])
    case repackOverflow(section: Int, needed: Int, available: Int)
    case invalidHeaderRegion(expected: Int, actual: Int)
    case missingSection(index: Int, size: Int)
    case sectionSizeMismatch(index: Int, expected: Int, actual: Int)

    public var description: String {
        switch self {
        case let .invalidSlotSize(expected, actual):
            return "XDSaveSlot: slot size \(actual) does not match expected \(expected) (0x28000)"
        case let .badMagic(found):
            let hex = found.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "XDSaveSlot: bad magic at slot start — expected 01 01 01, got \(hex)"
        case let .repackOverflow(section, needed, available):
            return "XDSaveSlot: repacking sub-block \(section) overflows the slot body — needs offset \(needed) but only \(available) bytes are available"
        case let .invalidHeaderRegion(expected, actual):
            return "XDSaveSlot: captured header region is \(actual) bytes, expected \(expected) (0xA8)"
        case let .missingSection(index, size):
            return "XDSaveSlot: cannot assemble — section \(index) (size \(size)) has no reconstructed bytes"
        case let .sectionSizeMismatch(index, expected, actual):
            return "XDSaveSlot: section \(index) rebuilt to \(actual) bytes but the slot TOC expects \(expected) — extend its struct's padding (or fix the edit) so it tiles the section exactly"
        }
    }
}
