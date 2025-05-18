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
    
    public static func defaultEngine(for game: GSGame) -> GeniusSonorityEngine {
        defaultEngine(for: game, fsysTOC: nil)
    }
    
    public static func defaultEngine(for game: GSGame, fsysTOC: FsysTOC?) -> GeniusSonorityEngine {
        var data = GeniusSonorityEngine.Data()
        let structs = GeniusSonorityEngine.Structs()
        var enumList = GeniusSonorityEngine.Enums.allItems
        enumList.removeAll(where: {
            ["FileTypes", "FsysGroupIDs"].contains($0.name)
        })
        switch game {
        case .colosseum:
            data.fsys.fileMetaDataPadding = 0x20
            enumList.append(Enums.Defaults.fileTypesColoXDEnum)
            enumList.append(fsysTOC?.enumeration ?? Enums.Defaults.fsysGroupIDsColoEnum)
        case .galeOfDarkness:
            data.fsys.fileMetaDataPadding = 0x40
            enumList.append(Enums.Defaults.fileTypesColoXDEnum)
            enumList.append(fsysTOC?.enumeration ?? Enums.Defaults.fsysGroupIDsXDEnum)
        case .battleRevolution:
            data.fsys.fileMetaDataPadding = 0x40
            enumList.append(Enums.Defaults.fileTypesPBREnum)
            enumList.append(fsysTOC?.enumeration ?? Enums.Defaults.fsysGroupIDsPBREnum)
        }
        let enums = GeniusSonorityEngine.Enums(unchecked: enumList)
        return try! .init(data: data, enums: enums, structs: structs)
    }
}

