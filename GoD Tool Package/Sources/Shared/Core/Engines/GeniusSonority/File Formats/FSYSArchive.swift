import GoDFoundation
import GoDEngine
import Structs

public enum FSYSArchiveError: GoDError {
    case duplicateFilenames([String], ErrorTrace = .init())

    public var description: String {
        switch self {
        case let .duplicateFilenames(names, errorTrace):
            return "Error: FSYS archive has duplicate entry filenames: \(names.joined(separator: ", ")). "
                + "Entry filenames must be unique within an archive.\n\(errorTrace)"
        }
    }
}

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

        public init(
            unknownFlag1: Bool,
            unknownFlag2: Bool,
            debugFlag: Bool,
            unknown1: Int,
            unknown2: Int,
            unknown3: Int,
            unknown4: Int
        ) {
            self.unknownFlag1 = unknownFlag1
            self.unknownFlag2 = unknownFlag2
            self.debugFlag = debugFlag
            self.unknown1 = unknown1
            self.unknown2 = unknown2
            self.unknown3 = unknown3
            self.unknown4 = unknown4
        }
    }
    
    public struct Entry {
        public struct MetaData: Codable {
            public let name: String
            public let fileType: String
            public let identifier: Int
            public let compress: Bool
            public let includesFullFilename: Bool?
            /// The full filename exactly as the archive stores it, when the
            /// entry carries one. The project-facing `Entry.filename` is a
            /// *derived* pretty form (stripped `_col`/`_cam`/`_scd` suffixes,
            /// mapped extensions), which is lossy — keeping the raw string
            /// here lets the repack emit the original bytes. Nil when the
            /// entry has no full filename, or (for archives dumped before
            /// this field existed) when it wasn't captured.
            public let fullFilename: String?

            public init(
                name: String,
                fileType: String,
                identifier: Int,
                compress: Bool,
                includesFullFilename: Bool?,
                fullFilename: String? = nil
            ) {
                self.name = name
                self.fileType = fileType
                self.identifier = identifier
                self.compress = compress
                self.includesFullFilename = includesFullFilename == true ? true : nil
                self.fullFilename = fullFilename
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
            unknown2: try fsysHeader.unknown_2,
            unknown3: try fsysHeader.unknown_3,
            unknown4: try fsysHeader.unknown_4
        )
        self.groupID = try fsysHeader.group_id
        self.metaData = metaData

        let entryCount: Int = try fsysHeader.entry_count
        let filePointerListAddress: Int = try fsysHeader.file_metadata_list
        
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
            
            let fileType: Enum.Case? = metaData.file_type
            let identifier: Int = try metaData.identifier
            
            let fileNameOffset: Int = try metaData.filename_pointer
            guard let entryName = data.readString(atAddress: fileNameOffset, format: .utf8) else {
                throw FileFormatErrors.invalid(format: Self.formatName)
            }
            
            let fullFilenameOffset: Int = try metaData.full_filename_pointer
            let fileName: String
            // The archive's own full-filename string, kept verbatim so the
            // repack can re-emit it; `fileName` below is the derived pretty
            // form used for the project filesystem.
            var rawFullFilename: String?

            if fullFilenameOffset != 0 {
                guard var name = data.readString(atAddress: fullFilenameOffset, format: .utf8) else {
                    throw FileFormatErrors.invalid(format: Self.formatName)
                }
                rawFullFilename = name
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
            
            let fileAddress: Int = try metaData.data_address
            let fileSize: Int = try metaData.file_size
            
            guard let rawEntryData = data.read(atAddress: fileAddress, length: fileSize) else {
                throw FileFormatErrors.invalid(format: Self.formatName)
            }
            var entryData = rawEntryData
            if isCompressed {
                guard let lzssHeader = entryData.read(struct: lzssHeaderStruct, atAddress: 0),
                      let compressedSize: Int = lzssHeader.compressed_size,
                      let compressedData = entryData.read(atAddress: lzssHeader.length, length: compressedSize - lzssHeader.length) else {
                    throw FileFormatErrors.invalid(format: Self.formatName)
                }
                let uncompressedSize: Int? = lzssHeader.uncompressed_size
                entryData = try compressor.decompress(compressedData, expectedSize: uncompressedSize)
            }
            
            return Entry(
                metadata: Entry.MetaData(
                    name: entryName,
                    fileType: fileType?.name ?? "", // make sure to use actual unique file type, not the displayed file type
                    identifier: identifier,
                    compress: isCompressed,
                    includesFullFilename: fullFilenameOffset != 0,
                    fullFilename: rawFullFilename
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
        header.magic_bytes = engine.data.fsys.magicBytes
        let unknownFlag1 = metaData.unknownFlag1 ? 0x80000000 : 0x0
        let unknownFlag2 = metaData.unknownFlag2 ? 0x40000000 : 0x0
        let debugFlag = metaData.debugFlag ? 0x1 : 0x0
        header.flags = unknownFlag1 | unknownFlag2 | debugFlag
        header.unknown1 = metaData.unknown1
        header.unknown_2 = metaData.unknown2
        header.unknown_3 = metaData.unknown3
        header.unknown_4 = metaData.unknown4
        header.entry_count = entries.count
        header.group_id = groupID
        
        // Entries are addressed by filename in the registry that drives a
        // repack, so a duplicate would make the mapping ambiguous and
        // silently point two entries at one string. Reject it up front.
        let duplicateFilenames = Dictionary(grouping: entries, by: \.filename)
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        guard duplicateFilenames.isEmpty else {
            throw FSYSArchiveError.duplicateFilenames(duplicateFilenames)
        }

        let result = GoDData(byteOrder: .big)
        result.pad(by: header.length)

        let offsetTableAddress = result.length
        header.file_metadata_list = offsetTableAddress
        // Both the offset table and the string table occupy at least one
        // 0x10 unit even when empty — every zero-entry archive shipped by
        // Colosseum and XD uses that layout.
        let offsetTableLength = max(0x10, (entries.count * 4).aligned(to: 0x10))
        result.pad(by: offsetTableLength)

        let stringTableAddress = result.length
        header.file_names_pointer = stringTableAddress

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
            // Prefer the archive's own stored string; `entry.filename` is
            // the derived pretty form and round-trips lossily.
            result.appendString(
                entry.metadata.fullFilename ?? entry.filename,
                format: .utf8,
                includeTerminator: true
            )
        }
        if entries.isEmpty {
            result.pad(by: 0x10)
        }
        result.align(to: 0x10)

        let entryMetadataStruct = engine.fsysFileMetaDataStruct
        let entryMetadataSize = entryMetadataStruct.length + engine.data.fsys.fileMetaDataPadding
        let allEntriesLength = entryMetadataSize * entries.count
        let firstEntryMetaDataAddress = result.length
        result.pad(by: allEntriesLength)
        
        result.align(to: 0x20)
        let firstEntryAddress = result.length
        header.file_data_pointer = firstEntryAddress
        
        let lzssHeaderStruct = engine.lzssHeaderStruct
        var currentPointerOffset = offsetTableAddress
        var currentMetaDataOffset = firstEntryMetaDataAddress
        let compressor = LZSSCompressor()
        
        let fileTypesEnum = engine.fileTypesEnum
        
        for entry in entries {
            let currentEntryAddress = result.length
            let metaData = StructData(definition: entryMetadataStruct, byteOrder: .big)
            metaData.identifier = entry.metadata.identifier
            // Route the file type through the throwing setter: an entry whose
            // type isn't in the engine's `FileTypes` enum used to be written
            // as type 0 with no complaint, silently corrupting the repack.
            try metaData.setEnumCase("file_type", named: entry.metadata.fileType)
            let fileTypeCase = try fileTypesEnum.get(entry.metadata.fileType)
            metaData.file_type_index = fileTypeCase.rawValue / 2
            metaData.data_address = currentEntryAddress
            metaData.flags = entry.metadata.compress ? 0x80000000 : 0
            metaData.full_filename_pointer = fullnameOffsetsByEntryName[entry.filename] ?? 0
            metaData.filename_pointer = nameOffsetsByEntryFilename[entry.filename] ?? 0
            
            if entry.metadata.compress {
                let lzssHeader = StructData(definition: lzssHeaderStruct, byteOrder: .big)
                lzssHeader.magic_bytes = engine.data.lzss.magicBytes
                
                let compressed = compressor.compress(entry.data)
                
                let compressedSize = compressed.length + lzssHeader.length
                let uncompressedSize = entry.data.length
                
                lzssHeader.uncompressed_size = uncompressedSize
                metaData.uncompressed_size = uncompressedSize
                
                lzssHeader.compressed_size = compressedSize
                metaData.file_size = compressedSize
                
                result.append(lzssHeader.data)
                result.append(compressed)
                
            } else {
                let size = entry.data.length
                metaData.uncompressed_size = size
                metaData.file_size = size
                result.append(entry.data)
            }
            
            result.write(currentMetaDataOffset, AsType: UInt32.self, atAddress: currentPointerOffset)
            result.write(struct: metaData, atAddress: currentMetaDataOffset)

            // Replay the packer's constant filler in the metadata padding
            // region (Colosseum only — see `FSYS.fileMetaDataFill`). It
            // carries no data, but writing it is what makes the repacked
            // archive byte-identical to the original.
            if let fill = engine.data.fsys.fileMetaDataFill, fill.length > 0 {
                let bytes = [UInt8](repeating: UInt8(truncatingIfNeeded: fill.byte), count: fill.length)
                result.write(
                    GoDData(byteStream: bytes, byteOrder: .big),
                    atAddress: UInt(currentMetaDataOffset + fill.offset)
                )
            }
            
            result.align(to: 0x20)
            
            currentPointerOffset += 4
            currentMetaDataOffset += entryMetadataSize
        }
        
        let footerStruct = engine.fsysFooterStruct
        let footer = StructData(definition: footerStruct, byteOrder: .big)
        footer.magic_bytes = engine.data.fsys.magicBytes
        result.append(footer.data)
        
        header.file_size = result.length
        result.write(struct: header, atAddress: 0)
        return result
    }
}
