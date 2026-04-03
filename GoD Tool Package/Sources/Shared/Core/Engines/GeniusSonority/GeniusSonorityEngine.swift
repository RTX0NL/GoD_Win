@_exported import GoDEngine
import GoDFoundation
import Structs

public enum GSGame {
    case colosseum, galeOfDarkness, battleRevolution
}

public struct GeniusSonorityEngine: Engine {
    public typealias DataType = GeniusSonorityEngine.Data
    public typealias EnumsType = GeniusSonorityEngine.Enums
    public typealias StructsType = GeniusSonorityEngine.Structs
    
    public let name = "GeniusSonority Engine"
    public private(set) var data = GeniusSonorityEngine.Data()
    public private(set) var enums = GeniusSonorityEngine.Enums()
    public private(set) var structs = GeniusSonorityEngine.Structs()
    private(set) var definitions: [StructDefinition]!
    
    public init(data: Data, enums: Enums, structs: Structs) throws {
        self.data = data
        self.enums = enums
        self.structs = structs
        definitions = try structs.entries.map(\.name).map { structName in
            try getStruct(structName)
        }
    }
    
    public init(data: Data, enums: Enums, structs: Structs, toc: FsysTOC) throws {
        var enumList = enums.entries
        enumList.removeAll(where: {
            ["FsysGroupIDs"].contains($0.name)
        })
        enumList.append(toc.enumeration)
        try self.init(data: data, enums: Enums(unchecked: enumList), structs: structs)
        self.data.toc.unknown = toc.unknown
        self.data.toc.padding = toc.padding
        self.data.toc.junk1 = toc.junk1
        self.data.toc.junk2 = toc.junk2
        self.data.toc.junk3 = toc.junk3
    }
    
    public static func defaultEngine(for game: GSGame) -> GeniusSonorityEngine {
        defaultEngine(for: game, fsysTOC: nil)
    }
    
    public static func defaultEngine(for game: GSGame, fsysTOC: FsysTOC?) -> GeniusSonorityEngine {
        var data = GeniusSonorityEngine.Data()
        var structsList = GeniusSonorityEngine.Structs.allItems
        var enumList = GeniusSonorityEngine.Enums.allItems
        
        enumList.removeAll(where: {
            ["FileTypes", "FsysGroupIDs"].contains($0.name)
        })
        structsList.removeAll(where: {
            ["FsysTOCEntry"].contains($0.name)
        })
        
        switch game {
        case .colosseum:
            data.fsys.fileMetaDataPadding = 0x20
            data.toc.unknown = 0x104
            structsList.append(Structs.Defaults.fsysTOCEntryStructSmall)
            enumList.append(Enums.Defaults.fileTypesColoXDEnum)
            enumList.append(fsysTOC?.enumeration ?? Enums.Defaults.fsysGroupIDsColoEnum)
            data.fsys.fileTypeReplacements = [
                "mdat": "dat"
            ]
        case .galeOfDarkness:
            data.fsys.fileMetaDataPadding = 0x40
            data.toc.unknown = 0x201
            structsList.append(Structs.Defaults.fsysTOCEntryStructFull)
            enumList.append(Enums.Defaults.fileTypesColoXDEnum)
            enumList.append(fsysTOC?.enumeration ?? Enums.Defaults.fsysGroupIDsXDEnum)
            data.fsys.fileTypeReplacements = [
                "mdat": "dat"
            ]
        case .battleRevolution:
            data.fsys.fileMetaDataPadding = 0x40
            data.toc.unknown = 0x251
            structsList.append(Structs.Defaults.fsysTOCEntryStructFull)
            enumList.append(Enums.Defaults.fileTypesPBREnum)
            enumList.append(fsysTOC?.enumeration ?? Enums.Defaults.fsysGroupIDsPBREnum)
            data.fsys.fileTypeReplacements = [
                "dckp": "bin",
                "dckt": "bin",
                "dcka": "bin",
            ]
        }
        
        switch game {
        case .colosseum:
            data.fsys.archiveFileTypeFolders = [
                "poke_face": ["gtx": "/Assets/Images/pokemon/faces"],
                "poke_body": ["gtx": "/Assets/Images/pokemon/pc-box", "atx": "/Assets/Images/pokemon/pc-box"],
            ]
        case .galeOfDarkness:
            data.fsys.archiveFileTypeFolders = [
                "poke_face": ["gtx": "/Assets/Images/pokemon/faces"],
                "poke_body": ["gtx": "/Assets/Images/pokemon/pc-box", "atx": "/Assets/Images/pokemon/pc-box"],
                "poke_dance": ["gtx": "/Assets/Images/pokemon/purify-chamber", "atx": "/Assets/Images/pokemon/purify-chamber"],
            ]
        case .battleRevolution:
            break
        }

        let structs = GeniusSonorityEngine.Structs(unchecked: structsList)
        let enums = GeniusSonorityEngine.Enums(unchecked: enumList)
        return try! .init(data: data, enums: enums, structs: structs)
    }

    /// Resolves the destination folder for an extracted file based on its type,
    /// the entry filename, and the parent FSYS archive name.
    ///
    /// Resolution priority:
    /// 1. Archive-specific override by file type
    /// 2. Archive-specific override by entry file extension (handles pool/proj suffixes)
    /// 3. Standard file type mapping (also checks entry file extension)
    /// 4. Default folder
    public func resolveFolder(
        forFileType fileType: String,
        entryFilename: String,
        archiveName: String
    ) -> Folder {
        let entryExtension = File(entryFilename).fileType
        let fsys = data.fsys

        // 1. Archive-specific override matching file type
        if let archiveOverrides = fsys.archiveFileTypeFolders[archiveName] {
            if let folder = archiveOverrides[fileType] {
                return folder
            }
            // 2. Archive-specific override matching entry file extension
            if entryExtension != fileType, let folder = archiveOverrides[entryExtension] {
                return folder
            }
        }

        // 3. Standard file type mapping
        if let folder = fsys.fileTypeFolders[fileType] {
            return folder
        }

        // Check entry extension (handles pool/proj suffixed files)
        if entryExtension != fileType, let folder = fsys.fileTypeFolders[entryExtension] {
            return folder
        }

        // 4. Default
        return fsys.defaultFolder
    }
}

