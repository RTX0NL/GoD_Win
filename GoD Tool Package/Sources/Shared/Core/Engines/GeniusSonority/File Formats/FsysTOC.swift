import GoDFoundation
import GoDEngine
import Structs

public final class FsysTOC {
    public static var formatName = "FsysTOC"
    
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
    
    public init(fsysIDsByFilename: [String : Int] = [:], unknown: Int) {
        self.unknown = unknown
        self.fsysIDsByFilename = fsysIDsByFilename
    }
    
    public init(tocData: GoDData, engine: GeniusSonorityEngine) throws {
        tocData.setByteOrder(.big)
        let headerStruct = engine.fsysTOCHeaderStruct
        guard let header = tocData.read(struct: headerStruct, atAddress: 0),
              let entryCount: Int = header.entryCount,
              let entryTableAddress: Int = header.entryTableAddress else {
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
            guard let groupID: Int = entry.groupID,
                  let filenameAddress: Int = entry.filenameAddress,
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
        
        header.magicBytes = engine.data.toc.magicBytes
        header.unknown = self.unknown
        header.junk1 = self.junk1
        header.junk2 = self.junk2
        header.junk3 = self.junk3
        header.stringTableAddress = headerStruct.length
        header.entryCount = entries.count
        
        let tocData = GoDData(length: header.length, byteOrder: .big)
        let entryTable = GoDData(length: 0, byteOrder: .big)
        
        entries.forEach { (filename, groupID) in
            let filenameAddress = tocData.length
            tocData.appendString(filename, format: .utf8, includeTerminator: true)
            
            let entry = StructData(definition: entryStruct, byteOrder: .big)
            entry.filenameAddress = filenameAddress
            entry.groupID = groupID
            entryTable.append(entry.data)
        }
        
        tocData.align(to: 0x20)
        header.entryTableAddress = tocData.length
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
