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
            /// Extension used on disk for an entry whose stored type the
            /// engine's `FileTypes` enum doesn't name. FSYS types are even and
            /// the first named one is 2 in both namespaces, so a stored 0 means
            /// "no type" rather than a type the enum is missing — all six
            /// GameCube discs and both PBR builds that carry such entries carry
            /// only 0 (Colosseum 22 per disc, XD 3, PBR US 19 / PAL 23).
            public static let defaultFileExtension = "bin"

            public let name: String
            /// The entry's file type as the engine's `FileTypes` enum names it,
            /// or nil when the archive stores a value the enum doesn't name.
            /// Nil is the semantic "no type" and is written back as index 0, so
            /// it round-trips exactly; the repack reads the type from here and
            /// never from the filename, which is what lets a nil-typed entry
            /// share the `.bin` suffix on disk with the genuine `bin` type
            /// (0x34 in Colo/XD, 0x02 in PBR) without the two being confused.
            public let fileType: String?
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

            /// The suffix this entry takes in the project filesystem: its type
            /// name, or `bin` when it has none. Derived rather than stored so a
            /// registry can't disagree with the file beside it.
            public var fileExtension: String { fileType ?? Self.defaultFileExtension }

            public init(
                name: String,
                fileType: String?,
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
            
            // `file_type` resolves through an `allowUnknownCases` enum, so an
            // unnamed raw value comes back as a synthesized `FileTypes_<raw>`
            // case rather than nil. Keep only a case the enum actually
            // declares: anything else is "no type" and is modelled as nil.
            let storedFileType: Enum.Case? = metaData.file_type
            let namedFileType: Enum.Case? = storedFileType.flatMap { stored in
                engine.fileTypesEnum.values.first { $0.rawValue == stored.rawValue }
            }
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
                var fileTypeName = namedFileType?.name ?? Entry.MetaData.defaultFileExtension
                if let replacement = fileTypeReplacements[fileTypeName] {
                    fileTypeName = replacement
                }
                let fileExtension = "." + fileTypeName
                
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
                    // The declared case name, not the displayed one — and nil
                    // rather than a synthesized name when the type is unnamed.
                    fileType: namedFileType?.name,
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
        // The table of contents is what the game actually looks the ID up in;
        // whether the header repeats it is a per-game convention. PBR leaves
        // this word zero in every archive it ships, so writing the table's
        // value here would move all 1,095 of them off the game's own layout.
        header.group_id = engine.data.fsys.writesGroupIDInHeaderValue ? groupID : 0
        
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

        // One string per entry, in entry order, with the offsets kept by
        // index rather than by name.
        //
        // Two entries sharing a name is ordinary in these archives — it's how
        // a map's files are grouped, `D2_valley_1.fsys` holds six entries
        // called `D2_valley_1` — and the games' own packer repeats the string
        // for each one rather than pointing both at a single copy (checked
        // across Colosseum and XD, including `people_archive`'s two
        // `agent_m_a2` and the 776 `(null)` entries of
        // `stm_se_nakigoe_archive`, all packed back to back with no gaps).
        // Keying these by name collapsed the duplicates onto one offset, so
        // the writer used to reject an archive it could have written
        // correctly.
        var nameOffsets = [Int]()
        nameOffsets.reserveCapacity(entries.count)
        for entry in entries {
            nameOffsets.append(result.length)
            result.appendString(entry.metadata.name, format: .utf8, includeTerminator: true)
        }
        var fullNameOffsets = [Int]()
        fullNameOffsets.reserveCapacity(entries.count)
        for entry in entries {
            guard metaData.debugFlag else {
                fullNameOffsets.append(0)
                continue
            }
            fullNameOffsets.append(result.length)
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
        
        for (entryIndex, entry) in entries.enumerated() {
            let currentEntryAddress = result.length
            let metaData = StructData(definition: entryMetadataStruct, byteOrder: .big)
            metaData.identifier = entry.metadata.identifier
            // Route a named file type through the throwing setter: an entry
            // whose type isn't in the engine's `FileTypes` enum used to be
            // written as type 0 with no complaint, silently corrupting the
            // repack. A nil type is the one case where 0 is correct — it is
            // what the archive stored — so it is written explicitly.
            if let fileTypeName = entry.metadata.fileType {
                try metaData.setEnumCase("file_type", named: fileTypeName)
                metaData.file_type_index = try fileTypesEnum.get(fileTypeName).rawValue / 2
            } else {
                metaData.set("file_type", to: nil as Enum.Case?)
                metaData.file_type_index = 0
            }
            metaData.data_address = currentEntryAddress
            metaData.flags = entry.metadata.compress ? 0x80000000 : 0
            metaData.full_filename_pointer = fullNameOffsets[entryIndex]
            metaData.filename_pointer = nameOffsets[entryIndex]
            
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

                if engine.data.lzss.writesUncompressedChecksum {
                    lzssHeader.unknown = Int(CRC32.compute(entry.data.rawBytes))
                }
                
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
