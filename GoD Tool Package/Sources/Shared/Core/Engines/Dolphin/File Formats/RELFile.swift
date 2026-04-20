//
//  RELFile.swift
//
//  Full GameCube/Wii Relocatable Module (.rel) file format. Parses every
//  field needed to reconstruct the binary from scratch, and serializes
//  back byte-identically for unmodified files.
//
//  Companion to the older `Rel` class (read-only, used by the existing
//  RelDisassemblyOperation). RELFile is the FileFormat-conforming entry
//  point for the registry and full dump/build cycle.
//
//  References:
//    Documentation/File Formats/Shared/REL - Relocatable Module.md
//    Legacy GoD Tool: Objects/file formats/XGRelocationTable.swift
//    GameCube SDK REL documentation
//

import Foundation
import GoDFoundation

public struct RELFile: FileFormat {
    public static let formatName = "rel"

    public var name: String = "rel"

    // MARK: - Header

    /// Module ID — unique identifier for this REL.
    public var moduleID: UInt32
    /// Format version (1, 2, or 3). XD/Colo files are version 3.
    public var version: UInt32

    // The pair of runtime linked-list pointers (next/prev) at offsets
    // 0x04/0x08 are zero on disc and rewritten by the loader; we keep them
    // settable so unusual files round-trip exactly.
    public var nextLink: UInt32 = 0
    public var prevLink: UInt32 = 0

    /// Module-name string offset/size. Vestigial in observed XD samples
    /// (offset typically points past EOF and the field is unread). Stored
    /// verbatim for byte-identical roundtrip.
    public var nameStringOffset: UInt32 = 0
    public var nameStringSize: UInt32 = 0

    public var bssSize: UInt32 = 0

    public var prologSection: UInt8 = 0
    public var epilogSection: UInt8 = 0
    public var unresolvedSection: UInt8 = 0
    /// Header byte 0x33 — typically zero/padding but preserved.
    public var headerPadByte: UInt8 = 0
    public var prologOffset: UInt32 = 0
    public var epilogOffset: UInt32 = 0
    public var unresolvedOffset: UInt32 = 0

    // v2+ fields (omitted on v1 files)
    public var sectionAlign: UInt32 = 0
    public var bssAlign: UInt32 = 0
    // v3+
    public var fixSize: UInt32 = 0

    public var sections: [Section]
    public var imports: [Import]

    /// Memberwise convenience init covering the most common case
    /// (constructing a fresh REL programmatically). All optional fields
    /// keep their stored defaults; tweak them after init as needed.
    public init(
        moduleID: UInt32,
        version: UInt32,
        sections: [Section] = [],
        imports: [Import] = []
    ) {
        self.moduleID = moduleID
        self.version = version
        self.sections = sections
        self.imports = imports
    }

    /// One section entry. Empty sections (size=0) and the BSS section
    /// (size>0, no file bytes) are kept so the section table preserves
    /// indices and the loader sees the original layout.
    public struct Section: Codable, Equatable {
        public var index: Int
        public var size: UInt32
        public var isExecutable: Bool
        /// True for the BSS section (`size > 0 && fileOffset == 0`).
        public var isBSS: Bool
        /// Section bytes (empty for BSS and zero-sized sections).
        public var data: [UInt8]

        public init(index: Int, size: UInt32, isExecutable: Bool, isBSS: Bool, data: [UInt8] = []) {
            self.index = index
            self.size = size
            self.isExecutable = isExecutable
            self.isBSS = isBSS
            self.data = data
        }
    }

    /// One import — a module the REL references, with a chain of
    /// relocations to apply against it.
    public struct Import: Codable, Equatable {
        public var moduleID: UInt32
        public var relocations: [Relocation]
        public init(moduleID: UInt32, relocations: [Relocation]) {
            self.moduleID = moduleID
            self.relocations = relocations
        }
    }

    /// One relocation entry. The terminating R_DOLPHIN_END (203) is NOT
    /// stored — it's added automatically on serialize.
    public struct Relocation: Codable, Equatable {
        /// Bytes to advance the write cursor before applying this entry.
        public var seekOffset: UInt16
        /// Relocation command (R_PPC_* or R_DOLPHIN_*).
        public var command: UInt8
        /// Target section index (in the import's module).
        public var targetSection: UInt8
        /// Symbol offset within the target section (or addend per command).
        public var addend: UInt32

        public init(seekOffset: UInt16, command: UInt8, targetSection: UInt8, addend: UInt32) {
            self.seekOffset = seekOffset
            self.command = command
            self.targetSection = targetSection
            self.addend = addend
        }

        // Standard PPC relocation commands
        public static let R_PPC_NONE: UInt8       = 0
        public static let R_PPC_ADDR32: UInt8     = 1
        public static let R_PPC_ADDR24: UInt8     = 2
        public static let R_PPC_ADDR16: UInt8     = 3
        public static let R_PPC_ADDR16_LO: UInt8  = 4
        public static let R_PPC_ADDR16_HI: UInt8  = 5
        public static let R_PPC_ADDR16_HA: UInt8  = 6
        public static let R_PPC_ADDR14: UInt8     = 7
        public static let R_PPC_REL24: UInt8      = 10
        public static let R_PPC_REL14: UInt8      = 11

        // REL-specific commands
        public static let R_DOLPHIN_NOP: UInt8     = 201
        public static let R_DOLPHIN_SECTION: UInt8 = 202
        public static let R_DOLPHIN_END: UInt8     = 203
    }

    // MARK: - Convenience

    public var headerSize: Int {
        switch version {
        case 1: return 0x40
        case 2: return 0x48
        default: return 0x4C   // v3 and beyond
        }
    }

    public var sectionTableSize: Int { sections.count * 8 }
    public var importTableSize: Int { imports.count * 8 }

    /// Sections that contain executable code.
    public var textSections: [Section] {
        sections.filter { $0.isExecutable && $0.size > 0 }
    }

    /// Sections that contain non-executable data (excludes BSS).
    public var dataSections: [Section] {
        sections.filter { !$0.isExecutable && !$0.isBSS && $0.size > 0 }
    }

    // MARK: - Binary parsing

    public init(binary: GoDData) throws {
        try self.init(binary: binary, name: "rel")
    }

    public init(binary: GoDData, name: String) throws {
        binary.setByteOrder(.big)
        guard binary.length >= 0x40 else {
            throw FileFormatErrors.invalid(format: RELFile.formatName)
        }

        let moduleID: UInt32 = binary.readSafely(atAddress: 0x00)
        let nextLink: UInt32 = binary.readSafely(atAddress: 0x04)
        let prevLink: UInt32 = binary.readSafely(atAddress: 0x08)
        let sectionCount: UInt32 = binary.readSafely(atAddress: 0x0C)
        let sectionTableOffset: UInt32 = binary.readSafely(atAddress: 0x10)
        let nameStringOffset: UInt32 = binary.readSafely(atAddress: 0x14)
        let nameStringSize: UInt32 = binary.readSafely(atAddress: 0x18)
        let version: UInt32 = binary.readSafely(atAddress: 0x1C)
        let bssSize: UInt32 = binary.readSafely(atAddress: 0x20)
        let relocTableOffset: UInt32 = binary.readSafely(atAddress: 0x24)
        let importTableOffset: UInt32 = binary.readSafely(atAddress: 0x28)
        let importTableSize: UInt32 = binary.readSafely(atAddress: 0x2C)
        let prologSection: UInt8 = binary.readSafely(atAddress: 0x30)
        let epilogSection: UInt8 = binary.readSafely(atAddress: 0x31)
        let unresolvedSection: UInt8 = binary.readSafely(atAddress: 0x32)
        let headerPadByte: UInt8 = binary.readSafely(atAddress: 0x33)
        let prologOffset: UInt32 = binary.readSafely(atAddress: 0x34)
        let epilogOffset: UInt32 = binary.readSafely(atAddress: 0x38)
        let unresolvedOffset: UInt32 = binary.readSafely(atAddress: 0x3C)

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

        // Section table
        var parsedSections: [Section] = []
        parsedSections.reserveCapacity(Int(sectionCount))
        for i in 0..<Int(sectionCount) {
            let entryOff = Int(sectionTableOffset) + i * 8
            guard entryOff + 8 <= binary.length else {
                throw FileFormatErrors.invalid(format: RELFile.formatName)
            }
            let rawOff: UInt32 = binary.readSafely(atAddress: entryOff)
            let size: UInt32 = binary.readSafely(atAddress: entryOff + 4)
            let fileOff = rawOff & ~UInt32(1)
            let isExecutable = (rawOff & 1) != 0
            let isBSS = (size > 0) && (fileOff == 0)
            var sectionBytes: [UInt8] = []
            if !isBSS, size > 0, fileOff > 0,
               Int(fileOff) + Int(size) <= binary.length,
               let bytes = binary.read(atAddress: Int(fileOff), length: Int(size)) {
                sectionBytes = bytes.rawBytes
            }
            parsedSections.append(Section(
                index: i,
                size: size,
                isExecutable: isExecutable,
                isBSS: isBSS,
                data: sectionBytes
            ))
        }

        // Import table
        let importCount = Int(importTableSize) / 8
        var rawImports: [(moduleID: UInt32, relocOff: UInt32)] = []
        rawImports.reserveCapacity(importCount)
        for i in 0..<importCount {
            let entryOff = Int(importTableOffset) + i * 8
            guard entryOff + 8 <= binary.length else { break }
            let modID: UInt32 = binary.readSafely(atAddress: entryOff)
            let relocOff: UInt32 = binary.readSafely(atAddress: entryOff + 4)
            rawImports.append((modID, relocOff))
        }

        // Relocation chains (one per import, terminated by R_DOLPHIN_END).
        var parsedImports: [Import] = []
        parsedImports.reserveCapacity(rawImports.count)
        for raw in rawImports {
            var offset = Int(raw.relocOff)
            var chain: [Relocation] = []
            while offset + 8 <= binary.length {
                let seek: UInt16 = binary.readSafely(atAddress: offset)
                let command: UInt8 = binary.readSafely(atAddress: offset + 2)
                let target: UInt8 = binary.readSafely(atAddress: offset + 3)
                let addend: UInt32 = binary.readSafely(atAddress: offset + 4)
                offset += 8
                if command == Relocation.R_DOLPHIN_END {
                    // Don't store the END entry — added back on serialize.
                    break
                }
                chain.append(Relocation(
                    seekOffset: seek,
                    command: command,
                    targetSection: target,
                    addend: addend
                ))
            }
            parsedImports.append(Import(moduleID: raw.moduleID, relocations: chain))
        }

        _ = relocTableOffset  // header field preserved verbatim on serialize

        self.name = name
        self.moduleID = moduleID
        self.version = version
        self.nextLink = nextLink
        self.prevLink = prevLink
        self.nameStringOffset = nameStringOffset
        self.nameStringSize = nameStringSize
        self.bssSize = bssSize
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
        self.imports = parsedImports
    }

    // MARK: - Binary serialization

    public var binaryData: GoDData {
        get throws {
            // Layout: header → section table → section data (in section
            // order) → import table → relocation chains. Matches the
            // observed layout of every XD/Colo REL.
            let out = GoDData(byteOrder: .big)
            // Pre-compute everything so header offsets are accurate.
            let hdrSize = headerSize
            let secTableOff = hdrSize
            let secTableEnd = secTableOff + sectionTableSize

            var cursor = secTableEnd
            var sectionFileOffsets: [Int: UInt32] = [:]
            for section in sections {
                if section.isBSS || section.size == 0 {
                    sectionFileOffsets[section.index] = 0
                } else {
                    sectionFileOffsets[section.index] = UInt32(cursor)
                    cursor += section.data.count
                }
            }

            let importTableOff = cursor
            cursor += importTableSize

            // Relocation chains lay out sequentially after the import table.
            var importRelocOffsets: [UInt32] = []
            importRelocOffsets.reserveCapacity(imports.count)
            for imp in imports {
                importRelocOffsets.append(UInt32(cursor))
                // Each relocation is 8 bytes, plus an 8-byte END terminator.
                cursor += (imp.relocations.count + 1) * 8
            }
            let relocTableOff = imports.first.map { _ in importRelocOffsets[0] } ?? 0

            // Header
            out.append(moduleID)
            out.append(nextLink)
            out.append(prevLink)
            out.append(UInt32(sections.count))
            out.append(UInt32(secTableOff))
            out.append(nameStringOffset)
            out.append(nameStringSize)
            out.append(version)
            out.append(bssSize)
            out.append(relocTableOff)
            out.append(UInt32(importTableOff))
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

            // Section table
            for section in sections {
                let fileOff = sectionFileOffsets[section.index] ?? 0
                let raw = fileOff | (section.isExecutable ? 1 : 0)
                out.append(raw)
                out.append(section.size)
            }
            assert(out.length == secTableEnd, "section table size mismatch")

            // Section data
            for section in sections where !section.isBSS && section.size > 0 {
                for byte in section.data { out.append(byte) }
            }
            assert(out.length == importTableOff, "section data ended at \(out.length), expected \(importTableOff)")

            // Import table
            for (i, imp) in imports.enumerated() {
                out.append(imp.moduleID)
                out.append(importRelocOffsets[i])
            }

            // Relocation chains
            for imp in imports {
                for reloc in imp.relocations {
                    out.append(reloc.seekOffset)
                    out.append(reloc.command)
                    out.append(reloc.targetSection)
                    out.append(reloc.addend)
                }
                // END terminator (offset=0, command=203, target=0, addend=0)
                out.append(UInt16(0))
                out.append(Relocation.R_DOLPHIN_END)
                out.append(UInt8(0))
                out.append(UInt32(0))
            }

            return out
        }
    }

    // MARK: - Outputs / JSON

    /// Filename for a section's bytes sidecar.
    public func sectionBinFilename(index: Int) -> File {
        File("\(name)_section_\(String(format: "%03d", index)).bin")
    }

    public init(outputs: [File: GoDData]) throws {
        let suffix = ".\(RELFile.formatName).json"
        guard let jsonKey = outputs.keys.first(where: { $0.path.hasSuffix(suffix) }) else {
            throw RELFile.missingOutputError(key: "*\(suffix)")
        }
        let stem = String(jsonKey.path.dropLast(suffix.count))
        guard let jsonData = outputs[jsonKey] else {
            throw RELFile.missingOutputError(key: jsonKey.path)
        }
        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: jsonData.data)
        } catch {
            throw RELFile.invalidFileError
        }

        self.name = stem.isEmpty ? "rel" : stem
        self.moduleID = dto.moduleID
        self.version = dto.version
        self.nextLink = dto.nextLink
        self.prevLink = dto.prevLink
        self.nameStringOffset = dto.nameStringOffset
        self.nameStringSize = dto.nameStringSize
        self.bssSize = dto.bssSize
        self.prologSection = dto.prologSection
        self.epilogSection = dto.epilogSection
        self.unresolvedSection = dto.unresolvedSection
        self.headerPadByte = dto.headerPadByte
        self.prologOffset = dto.prologOffset
        self.epilogOffset = dto.epilogOffset
        self.unresolvedOffset = dto.unresolvedOffset
        self.sectionAlign = dto.sectionAlign
        self.bssAlign = dto.bssAlign
        self.fixSize = dto.fixSize
        self.imports = dto.imports

        // Reattach section data from sidecar files.
        var rebuilt: [Section] = []
        rebuilt.reserveCapacity(dto.sections.count)
        for sectionDTO in dto.sections {
            var sectionBytes: [UInt8] = []
            if !sectionDTO.isBSS && sectionDTO.size > 0 {
                let binKey = File("\(self.name)_section_\(String(format: "%03d", sectionDTO.index)).bin")
                guard let data = outputs[binKey] else {
                    throw RELFile.missingOutputError(key: binKey.path)
                }
                sectionBytes = data.rawBytes
                guard sectionBytes.count == Int(sectionDTO.size) else {
                    throw FileFormatErrors.failedToEncode(
                        format: RELFile.formatName,
                        target: "section \(sectionDTO.index) size mismatch (\(sectionBytes.count) vs declared \(sectionDTO.size))"
                    )
                }
            }
            rebuilt.append(Section(
                index: sectionDTO.index,
                size: sectionDTO.size,
                isExecutable: sectionDTO.isExecutable,
                isBSS: sectionDTO.isBSS,
                data: sectionBytes
            ))
        }
        self.sections = rebuilt
    }

    public var outputs: [File: GoDData] {
        get throws {
            let dto = DTO(
                moduleID: moduleID,
                version: version,
                nextLink: nextLink,
                prevLink: prevLink,
                nameStringOffset: nameStringOffset,
                nameStringSize: nameStringSize,
                bssSize: bssSize,
                prologSection: prologSection,
                epilogSection: epilogSection,
                unresolvedSection: unresolvedSection,
                headerPadByte: headerPadByte,
                prologOffset: prologOffset,
                epilogOffset: epilogOffset,
                unresolvedOffset: unresolvedOffset,
                sectionAlign: sectionAlign,
                bssAlign: bssAlign,
                fixSize: fixSize,
                sections: sections.map {
                    SectionDTO(
                        index: $0.index,
                        size: $0.size,
                        isExecutable: $0.isExecutable,
                        isBSS: $0.isBSS
                    )
                },
                imports: imports
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(dto)

            var artifacts: [File: GoDData] = [
                jsonFilename: GoDData(data: jsonData, byteOrder: .big)
            ]
            for section in sections where !section.isBSS && section.size > 0 {
                let key = sectionBinFilename(index: section.index)
                artifacts[key] = GoDData(byteStream: section.data, byteOrder: .big)
            }
            return artifacts
        }
    }

    // MARK: - DTOs

    private struct DTO: Codable {
        let moduleID: UInt32
        let version: UInt32
        let nextLink: UInt32
        let prevLink: UInt32
        let nameStringOffset: UInt32
        let nameStringSize: UInt32
        let bssSize: UInt32
        let prologSection: UInt8
        let epilogSection: UInt8
        let unresolvedSection: UInt8
        let headerPadByte: UInt8
        let prologOffset: UInt32
        let epilogOffset: UInt32
        let unresolvedOffset: UInt32
        let sectionAlign: UInt32
        let bssAlign: UInt32
        let fixSize: UInt32
        let sections: [SectionDTO]
        let imports: [Import]
    }

    private struct SectionDTO: Codable {
        let index: Int
        let size: UInt32
        let isExecutable: Bool
        let isBSS: Bool
    }
}
