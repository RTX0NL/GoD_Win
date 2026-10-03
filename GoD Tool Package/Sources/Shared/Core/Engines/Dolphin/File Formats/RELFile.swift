//
//  RELFile.swift
//
//  GameCube/Wii Relocatable Module (.rel) file format — parsed into a
//  fully semantic model; every field the on-disc format encodes is
//  recoverable from the in-memory state alone. The editable form
//  (`outputs`) is the source tree `RelDisassembler` writes and
//  `RelAssembler` reads back — a manifest plus assembly/chunk files.
//
//    - Text sections → [TextInstruction] (raw word + optional SymbolRef
//      for any relocated immediate field)
//    - Data sections → [DataChunk] (`.binary` for opaque bytes,
//      `.pointer` for 4-byte pointer slots; default interpretation when
//      no typemap is supplied is a flat [.binary] span split at each
//      relocation site into (.binary, .pointer, .binary…))
//    - BSS sections → size only
//    - Relocations are derived at serialize time from SymbolRefs on text
//      instructions and pointer chunks in data; the chain-encoded
//      relocation table is not stored
//
//  Byte-identical roundtrip is a hard requirement; any corpus divergence
//  points at an ordering/alignment rule that still needs capturing.
//
//  References:
//    Documentation/File Formats/Shared/REL - Relocatable Module.md
//    GameCube SDK REL documentation
//    Legacy GoD Tool: Objects/file formats/XGRelocationTable.swift
//

import Foundation
import GoDFoundation

public struct RELFile: FileFormat {
    public static let formatName = "rel"

    public var name: String = "rel"

    // MARK: - Header scalars

    /// Module ID — unique identifier for this REL.
    public var moduleID: UInt32
    /// Format version (1, 2, or 3). XD/Colo files are version 3.
    public var version: UInt32

    /// Runtime linked-list pointers (next/prev) — zero on disc, rewritten
    /// by the loader. Preserved verbatim for byte-identical roundtrip.
    public var nextLink: UInt32 = 0
    public var prevLink: UInt32 = 0

    /// Module-name string offset/size. Vestigial in observed XD samples
    /// (points past EOF and never read); preserved verbatim.
    public var nameStringOffset: UInt32 = 0
    public var nameStringSize: UInt32 = 0

    public var prologSection: UInt8 = 0
    public var epilogSection: UInt8 = 0
    public var unresolvedSection: UInt8 = 0
    /// Header byte 0x33 — typically zero padding, preserved verbatim.
    public var headerPadByte: UInt8 = 0
    public var prologOffset: UInt32 = 0
    public var epilogOffset: UInt32 = 0
    public var unresolvedOffset: UInt32 = 0

    // v2+ fields
    public var sectionAlign: UInt32 = 0
    public var bssAlign: UInt32 = 0
    // v3+
    public var fixSize: UInt32 = 0

    // MARK: - Semantic sections

    public var sections: [Section]

    /// Ordered list of modules referenced by relocations, preserved from
    /// the original import-table layout. On serialize, chains are emitted
    /// in this order. Always contains every moduleID referenced by any
    /// SymbolRef in the file.
    public var importedModules: [UInt32]

    // MARK: - Derived

    public var bssSize: UInt32 {
        sections.reduce(UInt32(0)) { acc, s in
            if case .bss(let n) = s.body { return acc + n }
            return acc
        }
    }

    public var headerSize: Int {
        switch version {
        case 1: return 0x40
        case 2: return 0x48
        default: return 0x4C
        }
    }

    public var sectionTableSize: Int { sections.count * 8 }
    public var importTableSize: Int { importedModules.count * 8 }

    public var textSections: [Section] { sections.filter(\.isExecutable) }
    public var dataSections: [Section] {
        sections.filter { !$0.isExecutable && !$0.isBSS && $0.size > 0 }
    }

    // MARK: - Memberwise init

    public init(
        moduleID: UInt32,
        version: UInt32,
        sections: [Section] = [],
        importedModules: [UInt32] = []
    ) {
        self.moduleID = moduleID
        self.version = version
        self.sections = sections
        self.importedModules = importedModules
    }

    // MARK: - Nested types

    /// Which field of a PPC instruction (or data word) a relocation
    /// patches. Wraps the on-disc command byte but limits it to the
    /// values that carry a `SymbolRef` — the chain markers (SECTION/NOP/
    /// END) are derived at serialize time from edge layout.
    public enum RelocationFixup: UInt8, Codable, Equatable {
        case addr32    = 1      // 32-bit pointer
        case addr24    = 2      // bits 6..29 of a word (rare)
        case addr16    = 3      // low 16 bits, unsigned
        case addr16_lo = 4      // @l  — bits 16..31
        case addr16_hi = 5      // @h  — bits 16..31 (no carry)
        case addr16_ha = 6      // @ha — bits 16..31 (with +0x8000 carry)
        case addr14    = 7      // conditional branch absolute
        case rel24     = 10     // bits 6..29, PC-relative (bl/b)
        case rel14     = 11     // conditional branch PC-relative

        /// Byte offset from the start of the host 32-bit word where the
        /// patch is applied. HA/LO/HI patch the low 16 bits (bytes 2-3);
        /// everything else patches the full word starting at byte 0.
        var wordInnerOffset: UInt32 {
            switch self {
            case .addr16, .addr16_lo, .addr16_hi, .addr16_ha: return 2
            default: return 0
            }
        }
    }

    /// A pointer into this (or another) module's section-relative address
    /// space. For `moduleID == 0` the target is the DOL; for
    /// `moduleID == self.moduleID` the target is this same REL. External
    /// RELs use their own moduleIDs.
    ///
    /// Invariant across parse/serialize: `(moduleID, section, offset)` is
    /// the exact triple the on-disc relocation encodes — `offset` matches
    /// the reloc's `addend`. For DOL relocations the convention is that
    /// `offset` holds an absolute RAM address; `section` is informational.
    public struct SymbolRef: Equatable {
        public var moduleID: UInt32
        public var section: UInt8
        public var offset: UInt32

        public init(moduleID: UInt32, section: UInt8, offset: UInt32) {
            self.moduleID = moduleID
            self.section = section
            self.offset = offset
        }
    }

    /// A single PowerPC instruction inside a text section. `raw` is the
    /// exact on-disc 32-bit word; if any immediate field is patched by a
    /// relocation at load time, `ref` names the target and `fixup`
    /// identifies which field. Serialize emits `raw` verbatim and a
    /// relocation edge for any non-nil fixup.
    public struct TextInstruction: Equatable {
        public var raw: UInt32
        public var ref: SymbolRef?
        public var fixup: RelocationFixup?

        public init(raw: UInt32, ref: SymbolRef? = nil, fixup: RelocationFixup? = nil) {
            self.raw = raw
            self.ref = ref
            self.fixup = fixup
        }
    }

    /// A slice of a data section. `.binary` is an opaque run of bytes
    /// (default when no typemap is supplied). `.pointer` is a 4-byte
    /// pointer slot whose `restValue` is the 32-bit word stored on disc
    /// (the linker may write a non-zero addend-carrying value here; the
    /// loader computes the final pointer from `restValue` plus the
    /// relocation's target). On serialize it emits `restValue` plus an
    /// ADDR32 relocation edge pointing at `ref`.
    public enum DataChunk: Equatable {
        case binary(bytes: [UInt8])
        case pointer(ref: SymbolRef, restValue: UInt32)

        public var byteLength: Int {
            switch self {
            case .binary(let bytes): return bytes.count
            case .pointer: return 4
            }
        }
    }

    public enum Body: Equatable {
        /// No on-disc bytes. `fileOffset` is the value the original
        /// file held in the section table's offset slot — normally 0,
        /// but some linkers write a placeholder (e.g. the cumulative
        /// cursor at the time the entry was emitted) even for empty
        /// sections. Default 0; preserved only to support byte-identical
        /// roundtrip on such files.
        case empty(fileOffset: UInt32)
        case text([TextInstruction])
        case data([DataChunk])
        case bss(size: UInt32)
    }

    /// One REL section. Identity is its `index` inside the section table;
    /// execution semantics and size are both derived from `body`.
    public struct Section: Equatable {
        public var index: Int
        public var body: Body

        public init(index: Int, body: Body) {
            self.index = index
            self.body = body
        }

        public var isExecutable: Bool {
            if case .text = body { return true }
            return false
        }

        public var isBSS: Bool {
            if case .bss = body { return true }
            return false
        }

        public var isEmpty: Bool {
            if case .empty = body { return true }
            return false
        }

        /// Declared size per the on-disc section table.
        public var size: UInt32 {
            switch body {
            case .empty: return 0
            case .text(let ins): return UInt32(ins.count) * 4
            case .data(let chunks): return UInt32(chunks.reduce(0) { $0 + $1.byteLength })
            case .bss(let n): return n
            }
        }
    }

    // MARK: - Raw relocation command bytes (parse/serialize only)

    private enum RelocCmd {
        static let R_PPC_NONE:         UInt8 = 0
        static let R_DOLPHIN_NOP:      UInt8 = 201
        static let R_DOLPHIN_SECTION:  UInt8 = 202
        static let R_DOLPHIN_END:      UInt8 = 203
    }

    // MARK: - Binary parse

    /// `FileFormat` entry point: take one `FileData` (or pick the first
    /// if caller passes several) and derive `name` from its file stem
    /// when unambiguous.
    public init(binaries: [FileData]) throws {
        guard let first = binaries.first else {
            throw FileFormatErrors.invalid(format: RELFile.formatName)
        }
        let stem = first.file.fileName.replacingOccurrences(of: ".\(RELFile.formatName)", with: "")
        try self.init(binary: first.data, name: stem.isEmpty ? "rel" : stem)
    }

    public init(binary: GoDData, name: String) throws {
        binary.setByteOrder(.big)
        guard binary.length >= 0x40 else {
            throw FileFormatErrors.invalid(format: RELFile.formatName)
        }

        // ---- Header ----
        let moduleID: UInt32 = binary.readSafely(atAddress: 0x00)
        let nextLink: UInt32 = binary.readSafely(atAddress: 0x04)
        let prevLink: UInt32 = binary.readSafely(atAddress: 0x08)
        let sectionCount: UInt32 = binary.readSafely(atAddress: 0x0C)
        let sectionTableOffset: UInt32 = binary.readSafely(atAddress: 0x10)
        let nameStringOffset: UInt32 = binary.readSafely(atAddress: 0x14)
        let nameStringSize: UInt32 = binary.readSafely(atAddress: 0x18)
        let version: UInt32 = binary.readSafely(atAddress: 0x1C)
        // bssSize at 0x20 is ignored on parse — we derive it from .bss bodies.
        let _bssSizeHeader: UInt32 = binary.readSafely(atAddress: 0x20)
        _ = _bssSizeHeader
        let _relocTableOffset: UInt32 = binary.readSafely(atAddress: 0x24)
        _ = _relocTableOffset
        let importTableOffset: UInt32 = binary.readSafely(atAddress: 0x28)
        let importTableSize: UInt32 = binary.readSafely(atAddress: 0x2C)
        let prologSection: UInt8 = binary.readSafely(atAddress: 0x30)
        let epilogSection: UInt8 = binary.readSafely(atAddress: 0x31)
        let unresolvedSection: UInt8 = binary.readSafely(atAddress: 0x32)
        let headerPadByte: UInt8 = binary.readSafely(atAddress: 0x33)
        let prologOffset: UInt32 = binary.readSafely(atAddress: 0x34)
        let epilogOffset: UInt32 = binary.readSafely(atAddress: 0x38)
        let unresolvedOffset: UInt32 = binary.readSafely(atAddress: 0x3C)

        // The header has no magic, so these are what stand between a
        // non-REL and a "successful" parse. XD ships a particle file named
        // `tractorbeam.rel`: its version word reads 16,778,244 and it
        // declares no sections, and without this check it parsed into an
        // empty module and rebuilt as 76 bytes of its 320 KB.
        guard (1...3).contains(version), sectionCount > 0 else {
            throw FileFormatErrors.invalid(format: RELFile.formatName)
        }

        var sectionAlign: UInt32 = 0
        var bssAlign: UInt32 = 0
        var fixSize: UInt32 = 0
        if version >= 2, binary.length >= 0x48 {
            sectionAlign = binary.readSafely(atAddress: 0x40)
            bssAlign = binary.readSafely(atAddress: 0x44)
        }
        if version >= 3, binary.length >= 0x4C {
            fixSize = binary.readSafely(atAddress: 0x48)
        }

        // ---- Section table → raw descriptors ----
        struct RawSection {
            var index: Int
            var fileOffset: UInt32
            var size: UInt32
            var isExecutable: Bool
        }
        var rawSections: [RawSection] = []
        rawSections.reserveCapacity(Int(sectionCount))
        for i in 0..<Int(sectionCount) {
            let entryOff = Int(sectionTableOffset) + i * 8
            guard entryOff + 8 <= binary.length else {
                throw FileFormatErrors.invalid(format: RELFile.formatName)
            }
            let rawOff: UInt32 = binary.readSafely(atAddress: entryOff)
            let size: UInt32 = binary.readSafely(atAddress: entryOff + 4)
            rawSections.append(RawSection(
                index: i,
                fileOffset: rawOff & ~UInt32(1),
                size: size,
                isExecutable: (rawOff & 1) != 0
            ))
        }

        // ---- Import table + relocation chains → flat edge list ----
        var importedModules: [UInt32] = []
        var edges: [RELFileParseEdge] = []

        let importCount = Int(importTableSize) / 8
        for i in 0..<importCount {
            let entryOff = Int(importTableOffset) + i * 8
            guard entryOff + 8 <= binary.length else { break }
            let modID: UInt32 = binary.readSafely(atAddress: entryOff)
            let chainOff: UInt32 = binary.readSafely(atAddress: entryOff + 4)
            importedModules.append(modID)

            var offset = Int(chainOff)
            var curSection: UInt8 = 0
            var curOffset: UInt32 = 0
            walk: while offset + 8 <= binary.length {
                let seek: UInt16 = binary.readSafely(atAddress: offset)
                let command: UInt8 = binary.readSafely(atAddress: offset + 2)
                let target: UInt8 = binary.readSafely(atAddress: offset + 3)
                let addend: UInt32 = binary.readSafely(atAddress: offset + 4)
                offset += 8
                switch command {
                case RelocCmd.R_DOLPHIN_END:
                    break walk
                case RelocCmd.R_DOLPHIN_SECTION:
                    curSection = target
                    curOffset = 0
                case RelocCmd.R_DOLPHIN_NOP:
                    curOffset &+= UInt32(seek)
                default:
                    curOffset &+= UInt32(seek)
                    edges.append(RELFileParseEdge(
                        sourceSection: curSection,
                        sourceOffset: curOffset,
                        command: command,
                        targetModule: modID,
                        targetSection: target,
                        addend: addend
                    ))
                }
            }
        }

        // ---- Build semantic section bodies ----
        // Index edges by source section for fast lookup.
        var edgesBySection: [UInt8: [RELFileParseEdge]] = [:]
        for e in edges {
            edgesBySection[e.sourceSection, default: []].append(e)
        }

        var parsedSections: [Section] = []
        parsedSections.reserveCapacity(rawSections.count)

        for raw in rawSections {
            let body: Body
            if raw.size > 0, raw.fileOffset == 0 {
                // BSS: non-zero size with no file backing.
                body = .bss(size: raw.size)
            } else if raw.size == 0 {
                // Empty section — preserve whatever the linker wrote
                // into the offset slot so byte-identical roundtrip
                // works for files that use it as a placeholder.
                body = .empty(fileOffset: raw.fileOffset)
            } else {
                guard Int(raw.fileOffset) + Int(raw.size) <= binary.length,
                      let bytes = binary.read(atAddress: Int(raw.fileOffset), length: Int(raw.size))?.rawBytes else {
                    throw FileFormatErrors.invalid(format: RELFile.formatName)
                }
                let sectionEdges = (edgesBySection[UInt8(raw.index)] ?? [])
                    .sorted { $0.sourceOffset < $1.sourceOffset }
                if raw.isExecutable {
                    body = .text(Self.decodeText(bytes: bytes, edges: sectionEdges))
                } else {
                    body = .data(Self.splitData(bytes: bytes, edges: sectionEdges))
                }
            }
            parsedSections.append(Section(index: raw.index, body: body))
        }

        self.name = name
        self.moduleID = moduleID
        self.version = version
        self.nextLink = nextLink
        self.prevLink = prevLink
        self.nameStringOffset = nameStringOffset
        self.nameStringSize = nameStringSize
        self.prologSection = prologSection
        self.epilogSection = epilogSection
        self.unresolvedSection = unresolvedSection
        self.headerPadByte = headerPadByte
        self.prologOffset = prologOffset
        self.epilogOffset = epilogOffset
        self.unresolvedOffset = unresolvedOffset
        self.sectionAlign = sectionAlign
        self.bssAlign = bssAlign
        self.fixSize = fixSize
        self.sections = parsedSections
        self.importedModules = importedModules
    }

    // MARK: - Text / data decoding helpers

    private static func decodeText(bytes: [UInt8], edges: [RELFileParseEdge]) -> [TextInstruction] {
        var ins: [TextInstruction] = []
        ins.reserveCapacity(bytes.count / 4)
        // Group edges by instruction index for O(1) lookup.
        var edgesByInst: [Int: RELFileParseEdge] = [:]
        for e in edges {
            let instIdx = Int(e.sourceOffset) / 4
            // If multiple edges target the same instruction (rare — only
            // when both halves of a split imm are patched separately)
            // keep the first; both halves reference the same SymbolRef
            // so either encoding is equivalent.
            if edgesByInst[instIdx] == nil {
                edgesByInst[instIdx] = e
            }
        }
        var offset = 0
        var idx = 0
        while offset + 4 <= bytes.count {
            let raw = UInt32(bytes[offset]) << 24
                   | UInt32(bytes[offset + 1]) << 16
                   | UInt32(bytes[offset + 2]) << 8
                   | UInt32(bytes[offset + 3])
            if let e = edgesByInst[idx], let fixup = RelocationFixup(rawValue: e.command) {
                ins.append(TextInstruction(
                    raw: raw,
                    ref: SymbolRef(moduleID: e.targetModule, section: e.targetSection, offset: e.addend),
                    fixup: fixup
                ))
            } else {
                ins.append(TextInstruction(raw: raw))
            }
            offset += 4
            idx += 1
        }
        return ins
    }

    private static func splitData(bytes: [UInt8], edges: [RELFileParseEdge]) -> [DataChunk] {
        // Default typemap: one `.binary` span, split into
        // (.binary, .pointer, .binary, …) at each 4-byte ADDR32 site.
        var chunks: [DataChunk] = []
        var cursor = 0
        for e in edges {
            guard e.command == RelocationFixup.addr32.rawValue else {
                // Non-ADDR32 relocs on data are unusual; fall through to
                // treat as opaque (the at-rest bytes will still roundtrip
                // but the pointer semantics are lost).
                continue
            }
            let at = Int(e.sourceOffset)
            guard at + 4 <= bytes.count, at >= cursor else { continue }
            if at > cursor {
                chunks.append(.binary(bytes: Array(bytes[cursor..<at])))
            }
            let restValue = (UInt32(bytes[at]) << 24)
                          | (UInt32(bytes[at + 1]) << 16)
                          | (UInt32(bytes[at + 2]) << 8)
                          | UInt32(bytes[at + 3])
            chunks.append(.pointer(
                ref: SymbolRef(
                    moduleID: e.targetModule,
                    section: e.targetSection,
                    offset: e.addend
                ),
                restValue: restValue
            ))
            cursor = at + 4
        }
        if cursor < bytes.count {
            chunks.append(.binary(bytes: Array(bytes[cursor..<bytes.count])))
        }
        if chunks.isEmpty {
            chunks = [.binary(bytes: bytes)]
        }
        return chunks
    }

    // MARK: - Binary serialize

    /// `FileFormat` entry point: single REL binary.
    public var binaries: [FileData] {
        get throws {
            [FileData(file: File("\(name).\(RELFile.formatName)"), data: try binaryBytes)]
        }
    }

    private var binaryBytes: GoDData {
        get throws {
            let out = GoDData(byteOrder: .big)
            let hdrSize = headerSize
            let secTableOff = hdrSize
            let secTableEnd = secTableOff + sectionTableSize

            // Lay out section bodies (non-empty, non-bss) sequentially.
            var cursor = secTableEnd
            var sectionFileOffsets: [Int: UInt32] = [:]
            for s in sections {
                switch s.body {
                case .empty(let fileOffset):
                    sectionFileOffsets[s.index] = fileOffset
                case .bss:
                    sectionFileOffsets[s.index] = 0
                default:
                    sectionFileOffsets[s.index] = UInt32(cursor)
                    cursor += Int(s.size)
                }
            }

            let importTableOff = cursor
            cursor += importTableSize

            // Derive edges from SymbolRefs and group by target module.
            let allEdges = try collectEdges()
            var edgesByModule: [UInt32: [RELFileParseEdge]] = [:]
            for e in allEdges {
                edgesByModule[e.targetModule, default: []].append(e)
            }

            // Canonical chain layout: for each import-module, edges
            // grouped by source section in ascending section-index order,
            // within section sorted by source offset.
            var chainOffsets: [UInt32] = []
            var chainBytes: [[(UInt16, UInt8, UInt8, UInt32)]] = []
            for mod in importedModules {
                chainOffsets.append(UInt32(cursor))
                let modEdges = edgesByModule[mod] ?? []
                let encoded = Self.encodeChain(edges: modEdges)
                chainBytes.append(encoded)
                cursor += encoded.count * 8
            }
            let relocTableOff: UInt32 = chainOffsets.first ?? 0

            // ---- Header ----
            out.append(moduleID)
            out.append(nextLink)
            out.append(prevLink)
            out.append(UInt32(sections.count))
            out.append(UInt32(secTableOff))
            out.append(nameStringOffset)
            out.append(nameStringSize)
            out.append(version)
            out.append(bssSize)
            // When there are no imports, the original files hold 0 in
            // both the reloc-table and import-table offset fields rather
            // than a computed (would-be) end-of-sections address.
            let reportedImportTableOff: UInt32 = importedModules.isEmpty ? 0 : UInt32(importTableOff)
            out.append(relocTableOff)
            out.append(reportedImportTableOff)
            out.append(UInt32(importTableSize))
            out.append(prologSection)
            out.append(epilogSection)
            out.append(unresolvedSection)
            out.append(headerPadByte)
            out.append(prologOffset)
            out.append(epilogOffset)
            out.append(unresolvedOffset)
            if version >= 2 {
                out.append(sectionAlign)
                out.append(bssAlign)
            }
            if version >= 3 {
                out.append(fixSize)
            }
            assert(out.length == hdrSize, "header size mismatch")

            // ---- Section table ----
            for s in sections {
                let fileOff = sectionFileOffsets[s.index] ?? 0
                let raw = fileOff | (s.isExecutable ? UInt32(1) : UInt32(0))
                out.append(raw)
                out.append(s.size)
            }
            assert(out.length == secTableEnd, "section table size mismatch")

            // ---- Section bodies ----
            for s in sections {
                switch s.body {
                case .empty, .bss:
                    continue
                case .text(let ins):
                    for i in ins {
                        out.append(i.raw)
                    }
                case .data(let chunks):
                    for c in chunks {
                        switch c {
                        case .binary(let bytes):
                            for b in bytes { out.append(b) }
                        case .pointer(_, let restValue):
                            // Emit the on-disc rest value; the ADDR32
                            // reloc computed from `ref` will overwrite
                            // (or be combined with) it at load time.
                            out.append(restValue)
                        }
                    }
                }
            }
            assert(out.length == importTableOff,
                   "section data ended at \(out.length), expected \(importTableOff)")

            // ---- Import table ----
            for (i, mod) in importedModules.enumerated() {
                out.append(mod)
                out.append(chainOffsets[i])
            }

            // ---- Relocation chains ----
            for chain in chainBytes {
                for (seek, cmd, tgt, addend) in chain {
                    out.append(seek)
                    out.append(cmd)
                    out.append(tgt)
                    out.append(addend)
                }
            }

            return out
        }
    }

    /// Collect every relocation edge implied by the semantic model:
    /// - text-section SymbolRefs on instructions
    /// - data-section `.pointer` chunks (ADDR32 at the chunk offset)
    private func collectEdges() throws -> [RELFileParseEdge] {
        var edges: [RELFileParseEdge] = []
        for s in sections {
            switch s.body {
            case .empty, .bss:
                continue
            case .text(let ins):
                var wordOffset: UInt32 = 0
                for inst in ins {
                    if let ref = inst.ref, let fixup = inst.fixup {
                        edges.append(RELFileParseEdge(
                            sourceSection: UInt8(s.index),
                            sourceOffset: wordOffset + fixup.wordInnerOffset,
                            command: fixup.rawValue,
                            targetModule: ref.moduleID,
                            targetSection: ref.section,
                            addend: ref.offset
                        ))
                    }
                    wordOffset &+= 4
                }
            case .data(let chunks):
                var chunkOffset: UInt32 = 0
                for c in chunks {
                    if case .pointer(let ref, _) = c {
                        edges.append(RELFileParseEdge(
                            sourceSection: UInt8(s.index),
                            sourceOffset: chunkOffset,
                            command: RelocationFixup.addr32.rawValue,
                            targetModule: ref.moduleID,
                            targetSection: ref.section,
                            addend: ref.offset
                        ))
                    }
                    chunkOffset &+= UInt32(c.byteLength)
                }
            }
        }
        return edges
    }

    /// Encode a module's edge list into the on-disc chain format
    /// (R_DOLPHIN_SECTION markers, seek deltas, NOPs to bridge >64K
    /// gaps, terminating END). Edges are canonically ordered by
    /// (sourceSection, sourceOffset).
    private static func encodeChain(edges: [RELFileParseEdge]) -> [(UInt16, UInt8, UInt8, UInt32)] {
        let sorted = edges.sorted {
            if $0.sourceSection != $1.sourceSection { return $0.sourceSection < $1.sourceSection }
            return $0.sourceOffset < $1.sourceOffset
        }
        var out: [(UInt16, UInt8, UInt8, UInt32)] = []
        var curSection: UInt8? = nil
        var curOffset: UInt32 = 0
        for e in sorted {
            if curSection != e.sourceSection {
                out.append((0, RelocCmd.R_DOLPHIN_SECTION, e.sourceSection, 0))
                curSection = e.sourceSection
                curOffset = 0
            }
            var delta = e.sourceOffset &- curOffset
            while delta > 0xFFFF {
                out.append((0xFFFF, RelocCmd.R_DOLPHIN_NOP, 0, 0))
                delta &-= 0xFFFF
            }
            out.append((UInt16(delta), e.command, e.targetSection, e.addend))
            curOffset = e.sourceOffset
        }
        // END terminator
        out.append((0, RelocCmd.R_DOLPHIN_END, 0, 0))
        return out
    }

    // MARK: - FileFormat outputs / inputs (source tree)

    /// The editable source tree `RelDisassembler` writes with no type map:
    /// the `<name>.rel.json` manifest first, then `textN.s`, `dataN.s` and
    /// `dataN/…` chunk files. The manifest carries header, imports, chunk
    /// list and symbol table but no bytes — every byte of the module lives
    /// in one of the other files. See `RelManifest`.
    public var outputs: [FileData] {
        get throws { try RelDisassembler().artifacts(for: self) }
    }

    /// Rebuilds the module from the artifact bundle `outputs` produced, or an
    /// edited copy of it. Every path is read relative to the manifest's
    /// folder, so a bundle can be handed over with or without a common
    /// prefix.
    public init(outputs: [FileData]) throws {
        let suffix = ".\(RELFile.formatName).json"
        guard let manifestEntry = outputs.first(where: { $0.file.path.hasSuffix(suffix) }) else {
            throw RELFile.missingOutputError(key: "*\(suffix)")
        }
        let stem = String(manifestEntry.file.name.dropLast(suffix.count))
        let prefix: String? = manifestEntry.file.parentFolder.map { $0.path == "/" ? "/" : $0.path + "/" }

        let fst = InMemoryFST()
        let root = Folder("/")
        for entry in outputs {
            var relative = entry.file.path
            if let prefix, relative.hasPrefix(prefix) {
                relative.removeFirst(prefix.count)
            }
            try fst.writeFile(entry.data, at: root.file(relative), overwrite: true)
        }
        self = try RelAssembler().assemble(relName: stem.isEmpty ? "rel" : stem, in: root, fileSystem: fst)
    }
}

// MARK: - Codable for SymbolRef
//
// The one nested type that still needs a JSON form: `RegisterExportsPattern`
// records symbol pairs with it. Addressy fields go through `HexInt` so the
// output reads as hex.

extension RELFile.SymbolRef: Codable {
    private struct Wire: Codable {
        let moduleID: HexInt
        let section: UInt8
        let offset: HexInt
    }
    public init(from decoder: Decoder) throws {
        let w = try Wire(from: decoder)
        self.init(moduleID: w.moduleID.uint32, section: w.section, offset: w.offset.uint32)
    }
    public func encode(to encoder: Encoder) throws {
        try Wire(moduleID: HexInt(moduleID), section: section, offset: HexInt(offset)).encode(to: encoder)
    }
}

// MARK: - Internal parse/serialize edge carrier

/// Flat relocation edge used during parse (when building semantic
/// bodies from the on-disc chains) and serialize (when deriving chains
/// from SymbolRefs). Not part of RELFile's public API — exists only to
/// move edges between the two directions.
struct RELFileParseEdge {
    var sourceSection: UInt8
    var sourceOffset: UInt32
    var command: UInt8
    var targetModule: UInt32
    var targetSection: UInt8
    var addend: UInt32
}
