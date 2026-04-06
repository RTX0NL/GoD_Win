import GoDFoundation
import GoDEngine
import Structs

/// GameCube/Wii Relocatable Module (.rel) file format parser
public final class Rel: FileFormat {
    public static let formatName = ".rel"

    public let moduleID: UInt32
    public let version: UInt32
    public let sections: [Section]
    public let imports: [Import]
    public let relocations: [RelocationEntry]
    /// Symbol pointer table extracted from relocation commands: index → file offset
    public let symbolPointers: [Int: UInt32]

    public let prologSection: UInt8
    public let prologOffset: UInt32
    public let epilogSection: UInt8
    public let epilogOffset: UInt32
    public let bssSection: UInt8
    public let bssSize: UInt32

    public struct Section {
        public let index: Int
        public let fileOffset: UInt32
        public let size: UInt32
        public let isExecutable: Bool
        public let data: GoDData

        public init(index: Int, fileOffset: UInt32, size: UInt32, isExecutable: Bool, data: GoDData) {
            self.index = index
            self.fileOffset = fileOffset
            self.size = size
            self.isExecutable = isExecutable
            self.data = data
        }
    }

    public struct Import {
        public let moduleID: UInt32
        public let relocationsOffset: UInt32

        public init(moduleID: UInt32, relocationsOffset: UInt32) {
            self.moduleID = moduleID
            self.relocationsOffset = relocationsOffset
        }
    }

    public struct RelocationEntry {
        /// Seek offset from the previous write position
        public let offset: UInt16
        /// Relocation command type (1-13 = address patch, 202 = set position, 203 = end)
        public let command: UInt8
        /// Target section index
        public let targetSection: UInt8
        /// Target offset within the section (or addend, depending on command)
        public let addend: UInt32
        /// Which module this relocation belongs to
        public let sourceModuleID: UInt32

        public init(offset: UInt16, command: UInt8, targetSection: UInt8, addend: UInt32, sourceModuleID: UInt32) {
            self.offset = offset
            self.command = command
            self.targetSection = targetSection
            self.addend = addend
            self.sourceModuleID = sourceModuleID
        }

        /// Standard PPC relocation commands
        public static let R_PPC_NONE: UInt8 = 0
        public static let R_PPC_ADDR32: UInt8 = 1
        public static let R_PPC_ADDR24: UInt8 = 2
        public static let R_PPC_ADDR16: UInt8 = 3
        public static let R_PPC_ADDR16_LO: UInt8 = 4
        public static let R_PPC_ADDR16_HI: UInt8 = 5
        public static let R_PPC_ADDR16_HA: UInt8 = 6
        public static let R_PPC_ADDR14: UInt8 = 7
        public static let R_PPC_REL24: UInt8 = 10
        public static let R_PPC_REL14: UInt8 = 11

        /// REL-specific commands
        public static let R_DOLPHIN_NOP: UInt8 = 201
        public static let R_DOLPHIN_SECTION: UInt8 = 202
        public static let R_DOLPHIN_END: UInt8 = 203
    }

    public init(data: GoDData) throws {
        data.setByteOrder(.big)

        guard data.length >= 0x40 else {
            throw Self.invalidFileError
        }

        moduleID = data.readSafely(atAddress: 0x00)
        let numSections: UInt32 = data.readSafely(atAddress: 0x0C)
        let sectionInfoOffset: UInt32 = data.readSafely(atAddress: 0x10)
        version = data.readSafely(atAddress: 0x1C)
        bssSize = data.readSafely(atAddress: 0x20)
        let relocTableOffset: UInt32 = data.readSafely(atAddress: 0x24)
        let importTableOffset: UInt32 = data.readSafely(atAddress: 0x28)
        let importTableSize: UInt32 = data.readSafely(atAddress: 0x2C)
        prologSection = data.readSafely(atAddress: 0x30)
        epilogSection = data.readSafely(atAddress: 0x31)
        bssSection = data.readSafely(atAddress: 0x33)
        prologOffset = data.readSafely(atAddress: 0x34)
        epilogOffset = data.readSafely(atAddress: 0x38)

        // Parse section table
        var parsedSections = [Section]()
        for i in 0..<Int(numSections) {
            let entryOffset = Int(sectionInfoOffset) + i * 8
            guard entryOffset + 8 <= data.length else { break }

            let rawOffset: UInt32 = data.readSafely(atAddress: entryOffset)
            let sectionSize: UInt32 = data.readSafely(atAddress: entryOffset + 4)

            let fileOffset = rawOffset & ~0x3  // clear bottom 2 bits
            let isExecutable = (rawOffset & 1) != 0

            let sectionData: GoDData
            if sectionSize > 0 && fileOffset > 0 && Int(fileOffset + sectionSize) <= data.length {
                sectionData = data.read(atAddress: Int(fileOffset), length: Int(sectionSize)) ?? .none
            } else {
                sectionData = .none
            }

            parsedSections.append(Section(
                index: i,
                fileOffset: fileOffset,
                size: sectionSize,
                isExecutable: isExecutable,
                data: sectionData
            ))
        }
        sections = parsedSections

        // Parse import table
        let numImports = Int(importTableSize) / 8
        var parsedImports = [Import]()
        for i in 0..<numImports {
            let entryOffset = Int(importTableOffset) + i * 8
            guard entryOffset + 8 <= data.length else { break }

            let modID: UInt32 = data.readSafely(atAddress: entryOffset)
            let relocOffset: UInt32 = data.readSafely(atAddress: entryOffset + 4)
            parsedImports.append(Import(moduleID: modID, relocationsOffset: relocOffset))
        }
        imports = parsedImports

        // Parse relocation table and build symbol pointer table
        var parsedRelocations = [RelocationEntry]()
        var parsedSymbolPointers = [Int: UInt32]()
        var currentPointerIndex = 0
        // Track known targets for deduplication — when multiple relocations
        // target the same address (e.g. HA/LO pairs), they share one pointer index
        var targetToPointerIndex = [UInt32: Int]()

        for imp in parsedImports {
            var offset = Int(imp.relocationsOffset)

            while offset + 8 <= data.length {
                let seekOffset: UInt16 = data.readSafely(atAddress: offset)
                let command: UInt8 = data.readSafely(atAddress: offset + 2)
                let targetSection: UInt8 = data.readSafely(atAddress: offset + 3)
                let addend: UInt32 = data.readSafely(atAddress: offset + 4)

                if command == RelocationEntry.R_DOLPHIN_END { break }

                let entry = RelocationEntry(
                    offset: seekOffset,
                    command: command,
                    targetSection: targetSection,
                    addend: addend,
                    sourceModuleID: imp.moduleID
                )
                parsedRelocations.append(entry)

                // Build symbol pointer table from all standard relocation commands.
                // Deduplicate by target address — HA/LO pairs and repeated references
                // to the same address share one pointer index.
                if command >= 1 && command <= 13 {
                    let sectionIndex = Int(targetSection)
                    if let section = parsedSections.first(where: { $0.index == sectionIndex }) {
                        let fileOff = UInt32(section.fileOffset) + addend
                        if targetToPointerIndex[fileOff] == nil {
                            targetToPointerIndex[fileOff] = currentPointerIndex
                            parsedSymbolPointers[currentPointerIndex] = fileOff
                            currentPointerIndex += 1
                        }
                    }
                }

                offset += 8
            }
        }
        relocations = parsedRelocations
        symbolPointers = parsedSymbolPointers
    }

    /// Get the text sections (executable)
    public var textSections: [Section] {
        sections.filter { $0.isExecutable && $0.size > 0 }
    }

    /// Get the data sections (non-executable, non-empty)
    public var dataSections: [Section] {
        sections.filter { !$0.isExecutable && $0.size > 0 }
    }

    /// Resolve a symbol pointer index to a file offset using the symbol pointer table
    public func symbolOffset(for index: Int) -> UInt32? {
        symbolPointers[index]
    }
}
