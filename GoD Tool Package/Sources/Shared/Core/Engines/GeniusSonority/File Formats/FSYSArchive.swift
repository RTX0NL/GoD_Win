import GoDFoundation
import GoDEngine
import Structs

public final class FSYSArchive {
    public static let formatName = "fsys"
    
    public struct MetaData: Codable {
        public let unknownFlag1: Bool
        public let unknownFlag2: Bool
        public let debugFlag: Bool
        
        public let unknown1: Int
        public let unknown2: Int
        public let unknown3: Int
        public let unknown4: Int
    }
    
    public struct Entry {
        public struct MetaData: Codable {
            public let name: String
            public let fileType: String
            public let identifier: Int
            public let compress: Bool
            public let includesFullFilename: Bool?
            
            public init(
                name: String,
                fileType: String,
                identifier: Int,
                compress: Bool,
                includesFullFilename: Bool?
            ) {
                self.name = name
                self.fileType = fileType
                self.identifier = identifier
                self.compress = compress
                self.includesFullFilename = includesFullFilename == true ? true : nil
            }
        }
        
        public let metadata: MetaData
        public let filename: String
        public let data: GoDData
        
        public init(metadata: MetaData, filename: String, data: GoDData) {
            self.metadata = metadata
            self.filename = filename
            self.data = data
        }
    }
    
    public var groupID: Int
    public var metaData: MetaData
    public var entries: [Entry] = []

    public init(groupID: Int = 0, metadata: MetaData, entries: [Entry] = []) {
        self.groupID = groupID
        self.metaData = metadata
        self.entries = entries
    }
    
    public init(data: GoDData, engine: GeniusSonorityEngine) throws {
        data.setByteOrder(.big)
        let headerStruct = engine.fsysHeaderStruct
        guard let fsysHeader = data.read(struct: headerStruct, atAddress: 0) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }

        let flags: Int = try fsysHeader.flags
        let metaData = MetaData(
            unknownFlag1: (flags & 0x80000000).boolean,
            unknownFlag2: (flags & 0x40000000).boolean,
            debugFlag: (flags & 0x1).boolean,
            unknown1: try fsysHeader.unknown1,
            unknown2: try fsysHeader.unknown2,
            unknown3: try fsysHeader.unknown3,
            unknown4: try fsysHeader.unknown4
        )
        self.groupID = try fsysHeader.groupID
        self.metaData = metaData

        let entryCount: Int = try fsysHeader.entryCount
        let filePointerListAddress: Int = try fsysHeader.fileMetadataList
        
        guard let fileEntryAddresses: [Int32] = data.readValues(atAddress: filePointerListAddress, count: entryCount) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        
        let fileMetaDataStruct = engine.fsysFileMetaDataStruct
        let fileMetaDataList = fileEntryAddresses.map { address in
            data.read(struct: fileMetaDataStruct, atAddress: address.asInt)
        }
        
        let compressor = LZSSCompressor()
        let lzssHeaderStruct = engine.lzssHeaderStruct
        
        self.entries = try fileMetaDataList.map { metaData in
            guard let metaData else { throw FileFormatErrors.invalid(format: Self.formatName) }
            
            let fileType: Enum.Case? = metaData.fileType
            let identifier: Int = try metaData.identifier
            
            let fileNameOffset: Int = try metaData.filenamePointer
            guard let entryName = data.readString(atAddress: fileNameOffset, format: .utf8) else {
                throw FileFormatErrors.invalid(format: Self.formatName)
            }
            
            let fullFilenameOffset: Int = try metaData.fullFilenamePointer
            let fileName: String

            if fullFilenameOffset != 0 {
                guard var name = data.readString(atAddress: fullFilenameOffset, format: .utf8) else {
                    throw FileFormatErrors.invalid(format: Self.formatName)
                }
                // Strip configurable suffixes from the filename stem
                // e.g. "B1_1_col.ccd" → "B1_1.ccd" when "_col" is in fileNameSuffixReplacements
                if let ext = File(name).fileType {
                    let stem = String(name.dropLast(ext.count + 1)) // drop ".ext"
                    for suffix in engine.data.fsys.fileNameSuffixReplacements {
                        if stem.hasSuffix(suffix) {
                            name = String(stem.dropLast(suffix.count)) + "." + ext
                            break
                        }
                    }
                }
                fileName = name
            } else {
                let fileTypeReplacements = engine.data.fsys.fileTypeReplacements
                var fileTypeName = fileType?.name ?? ""
                if let replacement = fileTypeReplacements[fileTypeName] {
                    fileTypeName = replacement
                }
                let fileExtension = fileType != nil ? "." + fileTypeName : ""
                
                 if engine.data.fsys.fileExtensionSuffixes.contains(where: { entryName.endsWith("_" + $0) }) {
                    var nameParts = entryName.split(separator: "_")
                    let lastPart = String(nameParts.removeLast())
                    fileName = nameParts.joined(separator: "_") + "." + lastPart
                 } else if fileExtension.count > 0, entryName.endsWith(fileExtension) {
                    fileName = entryName
                } else {
                    fileName = entryName + fileExtension
                }
            }
            
            let flags: Int = try metaData.flags
            let isCompressed = (flags & 0x80000000).boolean
            
            let fileAddress: Int = try metaData.dataAddress
            let fileSize: Int = try metaData.fileSize
            
            guard let rawEntryData = data.read(atAddress: fileAddress, length: fileSize) else {
                throw FileFormatErrors.invalid(format: Self.formatName)
            }
            var entryData = rawEntryData
            if isCompressed {
                guard let lzssHeader = entryData.read(struct: lzssHeaderStruct, atAddress: 0),
                      let compressedSize: Int = lzssHeader.compressedSize,
                      let compressedData = entryData.read(atAddress: lzssHeader.length, length: compressedSize - lzssHeader.length) else {
                    throw FileFormatErrors.invalid(format: Self.formatName)
                }
                let uncompressedSize: Int? = lzssHeader.uncompressedSize
                entryData = try compressor.decompress(compressedData, expectedSize: uncompressedSize)
            }
            
            return Entry(
                metadata: Entry.MetaData(
                    name: entryName,
                    fileType: fileType?.name ?? "", // make sure to use actual unique file type, not the displayed file type
                    identifier: identifier,
                    compress: isCompressed,
                    includesFullFilename: fullFilenameOffset != 0
                ),
                filename: fileName,
                data: entryData
            )
        }
    }
    
    public func data(filename: String, engine: GeniusSonorityEngine) throws -> GoDData {
        let groupIDs = engine.fsysGroupIDsEnum
        let enumCase = try groupIDs.get(filename)
        let groupID = enumCase.rawValue
        return try data(groupID: groupID, engine: engine)
    }
    
    public func data(groupID: Int, engine: GeniusSonorityEngine) throws -> GoDData {
        let headerStruct = engine.fsysHeaderStruct
        let header = StructData(definition: headerStruct, byteOrder: .big)
        header.magicBytes = engine.data.fsys.magicBytes
        let unknownFlag1 = metaData.unknownFlag1 ? 0x80000000 : 0x0
        let unknownFlag2 = metaData.unknownFlag2 ? 0x40000000 : 0x0
        let debugFlag = metaData.debugFlag ? 0x1 : 0x0
        header.flags = unknownFlag1 | unknownFlag2 | debugFlag
        header.unknown1 = metaData.unknown1
        header.unknown2 = metaData.unknown2
        header.unknown3 = metaData.unknown3
        header.unknown4 = metaData.unknown4
        header.entryCount = entries.count
        header.groupID = groupID
        
        let result = GoDData(byteOrder: .big)
        result.pad(by: header.length)
        
        let offsetTableAddress = result.length
        header.fileMetadataList = offsetTableAddress
        let offsetTableLength = (entries.count * 4).aligned(to: 0x10)
        result.pad(by: offsetTableLength)
        
        let stringTableAddress = result.length
        header.fileNamesPointer = stringTableAddress
        
        var nameOffsetsByEntryFilename = [String: Int]()
        entries.forEach { entry in
            nameOffsetsByEntryFilename[entry.filename] = result.length
            result.appendString(entry.metadata.name, format: .utf8, includeTerminator: true)
        }
        var fullnameOffsetsByEntryName = [String: Int]()
        entries.forEach { entry in
            guard metaData.debugFlag else {
                fullnameOffsetsByEntryName[entry.filename] = 0
                return
            }
            fullnameOffsetsByEntryName[entry.filename] = result.length
            result.appendString(entry.filename, format: .utf8, includeTerminator: true)
        }
        result.align(to: 0x10)
        
        let entryMetadataStruct = engine.fsysFileMetaDataStruct
        let entryMetadataSize = entryMetadataStruct.length + engine.data.fsys.fileMetaDataPadding
        let allEntriesLength = entryMetadataSize * entries.count
        let firstEntryMetaDataAddress = result.length
        result.pad(by: allEntriesLength)
        
        result.align(to: 0x20)
        let firstEntryAddress = result.length
        header.fileDataPointer = firstEntryAddress
        
        let lzssHeaderStruct = engine.lzssHeaderStruct
        var currentPointerOffset = offsetTableAddress
        var currentMetaDataOffset = firstEntryMetaDataAddress
        let compressor = LZSSCompressor()
        
        let fileTypesEnum = engine.fileTypesEnum
        
        entries.forEach { entry in
            let currentEntryAddress = result.length
            let metaData = StructData(definition: entryMetadataStruct, byteOrder: .big)
            metaData.identifier = entry.metadata.identifier
            metaData.fileType = entry.metadata.fileType
            let fileTypeCase = try? fileTypesEnum.get(entry.metadata.fileType)
            metaData.fileTypeIndex = (fileTypeCase?.rawValue ?? 0) / 2
            metaData.dataAddress = currentEntryAddress
            metaData.flags = entry.metadata.compress ? 0x80000000 : 0
            metaData.fullFilenamePointer = fullnameOffsetsByEntryName[entry.filename] ?? 0
            metaData.filenamePointer = nameOffsetsByEntryFilename[entry.filename] ?? 0
            
            if entry.metadata.compress {
                let lzssHeader = StructData(definition: lzssHeaderStruct, byteOrder: .big)
                lzssHeader.magicBytes = engine.data.lzss.magicBytes
                
                let compressed = compressor.compress(entry.data)
                
                let compressedSize = compressed.length + lzssHeader.length
                let uncompressedSize = entry.data.length
                
                lzssHeader.uncompressedSize = uncompressedSize
                metaData.uncompressedSize = uncompressedSize
                
                lzssHeader.compressedSize = compressedSize
                metaData.fileSize = compressedSize
                
                result.append(lzssHeader.data)
                result.append(compressed)
                
            } else {
                let size = entry.data.length
                metaData.uncompressedSize = size
                metaData.fileSize = size
                result.append(entry.data)
            }
            
            result.write(currentMetaDataOffset, AsType: UInt32.self, atAddress: currentPointerOffset)
            result.write(struct: metaData, atAddress: currentMetaDataOffset)
            
            result.align(to: 0x20)
            
            currentPointerOffset += 4
            currentMetaDataOffset += entryMetadataSize
        }
        
        let footerStruct = engine.fsysFooterStruct
        let footer = StructData(definition: footerStruct, byteOrder: .big)
        footer.magicBytes = engine.data.fsys.magicBytes
        result.append(footer.data)
        
        header.fileSize = result.length
        result.write(struct: header, atAddress: 0)
        return result
    }
}
