//
//  RelManifest.swift
//  Dolphin
//
//  `<name>.rel.json` — the one file that ties a disassembled REL back
//  together. It carries what the source files cannot: the header scalars,
//  the import-table order, the shape of every section, and for each data
//  section the ordered list of chunk files with the type each was mapped
//  to. It carries no bytes. Every byte of the module lives in a file the
//  manifest points at, so editing that file is editing the module.
//
//  Relocations are not listed here either. They are written into the source
//  the way an assembler expects — `lis r3, sym@ha`, `.4byte sym` — and
//  re-derived from it, so inserting or removing a line moves them with the
//  code. Two exceptions keep the manifest lossless:
//
//    - `symbols` names every target the source cannot define as a label:
//      addresses in the DOL or another module, and spots inside this
//      module's own BSS. A label in the source always wins over an entry
//      here, so a moved definition takes effect without editing the JSON.
//    - `restWords` holds the at-rest word at a relocation site when it is
//      not the assembler's default (zero field). 87 pointer slots in
//      Colosseum's `common.rel` carry one; nothing else in either game does.
//
//  `relocations` is a last-resort positional list for fixup kinds the syntax
//  has no spelling for (ADDR16, ADDR24, ADDR14). No retail module uses them.
//

import Foundation
import GoDFoundation
import Disassembler

public struct RelManifest: Codable, Equatable {

    // MARK: Header scalars — see `RELFile` for what each one is.

    public var moduleID: HexInt
    public var version: UInt32
    public var nextLink: HexInt
    public var prevLink: HexInt
    public var nameStringOffset: HexInt
    public var nameStringSize: HexInt
    public var prologSection: UInt8
    public var epilogSection: UInt8
    public var unresolvedSection: UInt8
    public var headerPadByte: UInt8
    public var prologOffset: HexInt
    public var epilogOffset: HexInt
    public var unresolvedOffset: HexInt
    public var sectionAlign: HexInt
    public var bssAlign: HexInt
    public var fixSize: HexInt

    /// Import-table order. Every module a relocation targets must be here;
    /// the assembler appends any it finds missing rather than drop edges.
    public var importedModules: [HexInt]

    /// One entry per section-table slot, in slot order.
    public var sections: [Section]

    /// Name → target for every symbol the source references but does not
    /// define. Keyed by the name as it appears in the `.s`/`.csv` files.
    public var symbols: [String: Symbol]

    public struct Section: Codable, Equatable {
        public var index: Int
        public var kind: Kind
        /// `.empty` only: the value the original section table held in its
        /// offset slot (a placeholder some linkers write; usually 0).
        public var fileOffset: HexInt?
        /// `.bss` only: byte size.
        public var size: Int?
        /// `.text` only: the assembly source, relative to the manifest.
        public var file: String?
        /// `.data` only: the section's chunk files in section order. `file`
        /// paths are relative to the manifest's folder, not to a section
        /// folder, since one manifest describes every section.
        public var chunks: [DataSectionManifest.Chunk]?
        /// At-rest words at relocation sites that are not zero-field,
        /// keyed by section offset in hex.
        public var restWords: [String: HexInt]?
        /// Positional relocations for fixups the source syntax cannot
        /// express. Empty in practice.
        public var relocations: [Relocation]?

        public enum Kind: String, Codable, Equatable {
            case empty, text, data, bss
        }

        public init(
            index: Int,
            kind: Kind,
            fileOffset: HexInt? = nil,
            size: Int? = nil,
            file: String? = nil,
            chunks: [DataSectionManifest.Chunk]? = nil,
            restWords: [String: HexInt]? = nil,
            relocations: [Relocation]? = nil
        ) {
            self.index = index
            self.kind = kind
            self.fileOffset = fileOffset
            self.size = size
            self.file = file
            self.chunks = chunks
            self.restWords = restWords
            self.relocations = relocations
        }
    }

    public struct Symbol: Codable, Equatable {
        public var moduleID: HexInt
        public var section: UInt8
        public var offset: HexInt

        public init(moduleID: HexInt, section: UInt8, offset: HexInt) {
            self.moduleID = moduleID
            self.section = section
            self.offset = offset
        }

        public init(_ ref: RELFile.SymbolRef) {
            self.init(moduleID: HexInt(ref.moduleID), section: ref.section, offset: HexInt(ref.offset))
        }

        public var ref: RELFile.SymbolRef {
            RELFile.SymbolRef(moduleID: moduleID.uint32, section: section, offset: offset.uint32)
        }
    }

    public struct Relocation: Codable, Equatable {
        /// Offset of the host word from the section start.
        public var offset: HexInt
        public var fixup: RELFile.RelocationFixup
        public var symbol: String

        public init(offset: HexInt, fixup: RELFile.RelocationFixup, symbol: String) {
            self.offset = offset
            self.fixup = fixup
            self.symbol = symbol
        }
    }

    // MARK: - Header transfer

    /// A manifest carrying `rel`'s header and import order, with no
    /// sections or symbols yet.
    public init(headerOf rel: RELFile) {
        moduleID = HexInt(rel.moduleID)
        version = rel.version
        nextLink = HexInt(rel.nextLink)
        prevLink = HexInt(rel.prevLink)
        nameStringOffset = HexInt(rel.nameStringOffset)
        nameStringSize = HexInt(rel.nameStringSize)
        prologSection = rel.prologSection
        epilogSection = rel.epilogSection
        unresolvedSection = rel.unresolvedSection
        headerPadByte = rel.headerPadByte
        prologOffset = HexInt(rel.prologOffset)
        epilogOffset = HexInt(rel.epilogOffset)
        unresolvedOffset = HexInt(rel.unresolvedOffset)
        sectionAlign = HexInt(rel.sectionAlign)
        bssAlign = HexInt(rel.bssAlign)
        fixSize = HexInt(rel.fixSize)
        importedModules = rel.importedModules.map { HexInt($0) }
        sections = []
        symbols = [:]
    }

    /// Writes the header scalars and import order into `rel`.
    public func applyHeader(to rel: inout RELFile) {
        rel.moduleID = moduleID.uint32
        rel.version = version
        rel.nextLink = nextLink.uint32
        rel.prevLink = prevLink.uint32
        rel.nameStringOffset = nameStringOffset.uint32
        rel.nameStringSize = nameStringSize.uint32
        rel.prologSection = prologSection
        rel.epilogSection = epilogSection
        rel.unresolvedSection = unresolvedSection
        rel.headerPadByte = headerPadByte
        rel.prologOffset = prologOffset.uint32
        rel.epilogOffset = epilogOffset.uint32
        rel.unresolvedOffset = unresolvedOffset.uint32
        rel.sectionAlign = sectionAlign.uint32
        rel.bssAlign = bssAlign.uint32
        rel.fixSize = fixSize.uint32
        rel.importedModules = importedModules.map(\.uint32)
    }

    // MARK: - Serialization

    public static func fileName(for relName: String) -> String { "\(relName).\(RELFile.formatName).json" }

    public func encoded() throws -> GoDData {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return GoDData(data: try encoder.encode(self), byteOrder: .big)
    }

    public init(json: GoDData) throws {
        self = try JSONDecoder().decode(RelManifest.self, from: json.data)
    }

    /// `restWords` key for a section offset.
    public static func offsetKey(_ offset: UInt32) -> String {
        "0x" + String(offset, radix: 16, uppercase: true)
    }

    /// Parses a `restWords` key back to an offset. Accepts the hex form
    /// written by `offsetKey` and a plain decimal.
    public static func offset(fromKey key: String) -> UInt32? {
        if key.hasPrefix("0x") || key.hasPrefix("0X") {
            return UInt32(key.dropFirst(2), radix: 16)
        }
        return UInt32(key)
    }
}
