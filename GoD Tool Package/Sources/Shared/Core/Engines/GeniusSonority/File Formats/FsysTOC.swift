import GoDFoundation
import GoDEngine
import Structs

/// The disc's table of contents as a project artifact.
///
/// The rebuild derives most of the table from the archives it finds, which
/// loses the entries naming archives the disc doesn't actually ship — 11 on
/// the XD US disc, where the table lists the PAL-only `pocket_menu_ge`,
/// `fight_common_uk` and friends. Those are complete entries with real group
/// IDs, not stray strings, so dropping them shortens the table. This manifest
/// carries every entry the disc listed; one whose `file` is empty is exactly
/// such a dangling name, written back verbatim with nothing to pack.
public struct FsysTOCManifest: Codable {
    public struct Entry: Codable {
        /// The name as the table's own string table stores it.
        public let name: String
        public let groupID: Int
        /// Path of the archive's registry in the project, or empty when the
        /// disc lists a name it ships no archive for.
        public let file: String

        public init(name: String, groupID: Int, file: String) {
            self.name = name
            self.groupID = groupID
            self.file = file
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// Entries the project has no archive for, which the rebuild has to
    /// re-emit from here or lose.
    public var danglingEntries: [Entry] { entries.filter { $0.file.isEmpty } }
}

public final class FsysTOC {
    public static var formatName = "FsysTOC"
    /// Filename of the project-side manifest, beside `FST.json`.
    public static let manifestFileName = "GSfsys.toc.json"
    
    public var unknown: Int
    public var padding: Int?
    public var junk1: Int?
    public var junk2: Int?
    public var junk3: Int?
    
    private var fsysIDsByFilename = [String: Int]()
    
    public var enumeration: Enum {
        Enum(
            name: GeniusSonorityEngine.Enums.Defaults.fsysGroupIDsColoEnum.name,
            allowUnknownCases: GeniusSonorityEngine.Enums.Defaults.fsysGroupIDsColoEnum.allowUnknownCases,
            values: fsysIDsByFilename.map { Enum.Case(name: $0.key, rawValue: $0.value) }.sorted(by: { $0.name < $1.name }),
            propertyType: GeniusSonorityEngine.Enums.Defaults.fsysGroupIDsColoEnum.propertyType
        )
    }
    
    /// Every listed name with its group ID, in the order the table stores
    /// them (ascending by group ID, which is how both games write it).
    public var listedEntries: [(name: String, groupID: Int)] {
        fsysIDsByFilename
            .map { (name: $0.key, groupID: $0.value) }
            .sorted { $0.groupID < $1.groupID }
    }

    public init(fsysIDsByFilename: [String : Int] = [:], unknown: Int) {
        self.unknown = unknown
        self.fsysIDsByFilename = fsysIDsByFilename
    }
    
    public init(tocData: GoDData, engine: GeniusSonorityEngine) throws {
        tocData.setByteOrder(.big)
        let headerStruct = engine.fsysTOCHeaderStruct
        guard let header = tocData.read(struct: headerStruct, atAddress: 0),
              let entryCount: Int = header.entry_count,
              let entryTableAddress: Int = header.entry_table_address else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        
        self.unknown = try header.unknown
        self.junk1 = header.junk1
        self.junk2 = header.junk2
        self.junk3 = header.junk3
        
        let entryStruct = engine.fsysTOCEntryStruct
        guard let entries = tocData.read(structs: entryStruct, atAddress: entryTableAddress, count: entryCount) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        
        try entries.forEach { entry in
            guard let groupID: Int = entry.group_id,
                  let filenameAddress: Int = entry.filename_address,
                  let filename = tocData.readString(atAddress: filenameAddress, format: .utf8) else {
                throw FileFormatErrors.invalid(format: Self.formatName)
            }
            fsysIDsByFilename[filename] = groupID
        }
        
        let entriesSize = (entries.count + 1) * entryStruct.length
        let entriesEnd = (entryTableAddress + entriesSize).aligned(to: 0x20)
        let padding = max(0, tocData.length - entriesEnd)
        if padding > 0 {
            self.padding = padding
        }
    }
    
    public init(enumeration: Enum, engine: GeniusSonorityEngine) {
        self.unknown = engine.data.toc.unknown
        self.junk1 = engine.data.toc.junk1
        self.junk2 = engine.data.toc.junk2
        self.junk3 = engine.data.toc.junk3
        self.padding = engine.data.toc.padding
        enumeration.values.forEach { entry in
            self.fsysIDsByFilename[entry.name] = entry.rawValue
        }
    }
    
    public func tocData(with engine: GeniusSonorityEngine) throws -> GoDData {
        let headerStruct = engine.fsysTOCHeaderStruct
        let entryStruct = engine.fsysTOCEntryStruct
        let header = StructData(definition: headerStruct, data: .init(length: headerStruct.length, byteOrder: .big))
        
        let entries = fsysIDsByFilename.sorted { e1, e2 in
            e1.value < e2.value
        }
        
        header.magic_bytes = engine.data.toc.magicBytes
        header.unknown = self.unknown
        header.junk1 = self.junk1
        header.junk2 = self.junk2
        header.junk3 = self.junk3
        header.string_table_address = headerStruct.length
        header.entry_count = entries.count
        
        let tocData = GoDData(length: header.length, byteOrder: .big)
        let entryTable = GoDData(length: 0, byteOrder: .big)
        
        entries.forEach { (filename, groupID) in
            let filenameAddress = tocData.length
            tocData.appendString(filename, format: .utf8, includeTerminator: true)
            
            let entry = StructData(definition: entryStruct, byteOrder: .big)
            entry.filename_address = filenameAddress
            entry.group_id = groupID
            entryTable.append(entry.data)
        }
        
        tocData.align(to: 0x20)
        header.entry_table_address = tocData.length
        tocData.write(struct: header, atAddress: 0)
        
        entryTable.append(.init(length: entryStruct.length, byteOrder: .big))
        entryTable.align(to: 0x20)
        tocData.append(entryTable)
        
        if let padding {
            tocData.pad(by: padding)
        }
        
        return tocData
    }
    
    public func fsysID(for file: File) -> Int? {
        fsysID(for: file.fileName)
    }
    
    public func fsysID(for filename: String) -> Int? {
        fsysIDsByFilename[filename]
    }
    
    public func filename(for fsysID: Int) -> String? {
        fsysIDsByFilename.first { (key: String, value: Int) in
            value == fsysID
        }?.key
    }
}
