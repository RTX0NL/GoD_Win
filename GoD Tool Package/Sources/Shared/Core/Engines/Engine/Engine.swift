import GoDFoundation
import Structs

public protocol EngineEnums: ValidatedSet where Item == Enum {
    var entries: [Enum] { get }
}

public protocol EngineStructs: ValidatedSet where Item == StructMap {
    var entries: [StructMap] { get }
}

public protocol Engine {
    associatedtype DataType: Codable
    associatedtype EnumsType: EngineEnums
    associatedtype StructsType: EngineStructs

    var name: String { get }
    var data: DataType { get }
    var enums: EnumsType { get }
    var structs: StructsType { get }

    init(data: DataType, enums: EnumsType, structs: StructsType) throws

    /// Bundled files that should be copied into the engine folder
    /// alongside the engine JSON on first project setup. Keys are paths
    /// relative to the engine folder (matching the `File` fields on the
    /// engine's `Data.Resources`); values are the bytes to write.
    /// Default: no bundled resources.
    func bundledResources() -> [File: GoDData]
}

public extension Engine {
    func bundledResources() -> [File: GoDData] { [:] }

    func getEnum(_ name: String) -> Enum? {
        enums.entries.first(where: { $0.name == name })
    }
    
    private func getStruct(_ name: String) -> StructMap? {
        structs.entries.first(where: { $0.name == name })
    }
    
    func getStruct(_ name: String) throws -> StructDefinition {
        guard let result = try getStruct(name, callerChain: []) else {
            throw EngineDecodingError.missingStructs([name], .init())
        }
        return result
    }
    
    private func getStruct(_ name: String, callerChain: [String]) throws -> StructDefinition? {
        guard let map: StructMap = getStruct(name) else { return nil }
        func mapToDefinition(field: StructMap.Property) throws -> StructDefinition.Property {
            let fieldName = field.name
            let description = field.description
            
            func toProperty(field: StructField) throws -> StructProperty {
                switch field {
                case .primitive(let type):
                    return .primitive(type)
                case .array(let field, let count):
                    let property = try toProperty(field: field)
                    return .array(property, count: count)
                case .subStruct(let substructName):
                    guard !callerChain.contains(substructName) else {
                        throw EngineDecodingError.cyclicDependency(name, substructName, .init())
                    }
                    guard let subDef: StructDefinition = try getStruct(substructName, callerChain: callerChain + [name]) else {
                        throw EngineDecodingError.missingStructProperty(structName: name, property: fieldName, substructName: substructName, .init())
                    }
                    return .subStruct(subDef)
                case .enumeration(let enumName):
                    guard let def: Enum = getEnum(enumName) else {
                        throw EngineDecodingError.missingEnumProperty(structName: name, property: fieldName, enumName: enumName, .init())
                    }
                    return .enumeration(def)
                case .label:
                    return .label
                case .padding(let length):
                    return .padding(length: length)
                }
            }
            let type = try toProperty(field: field.type)
            return .init(name: fieldName, type: type, description: description)
        }
        
        return .init(
            name: map.name,
            wordSize: map.wordSize,
            alignmentStyle: map.alignmentStyle,
            properties: try map.properties.map(mapToDefinition)
        )
    }
    
    @discardableResult
    func write(to fst: FileSystemTree, in folder: Folder, overwrite: Bool) -> Bool {
        let engineFolder = folder.folder(name)
        _ = fst.createFolder(at: engineFolder, overwrite: overwrite)
        let dataFile = engineFolder.file(name + ".json")
        guard fst.writeFile(data, at: dataFile, overwrite: overwrite) else {
            return false
        }
        
        let enumsFolder = engineFolder.folder("Enumerations")
        fst.createFolder(at: enumsFolder, overwrite: overwrite)
        for enumData in enums.entries {
            let enumFile = enumsFolder.file(enumData.name + ".json")
            guard fst.writeFile(enumData, at: enumFile, overwrite: overwrite) else {
                return false
            }
        }
        
        let structsFolder = engineFolder.folder("Structs")
        fst.createFolder(at: structsFolder, overwrite: overwrite)
        for structMap in structs.entries {
            let structFile = structsFolder.file(structMap.name + ".json")
            guard fst.writeFile(structMap, at: structFile, overwrite: overwrite) else {
                return false
            }
        }

        // Copy bundled reference resources (REL typemap, symbol indexes,
        // DOL symbol maps, etc.) into the engine folder so users can
        // edit them in the project and ops can read them via the
        // `File` paths declared on the engine's Data.
        for (relativeFile, data) in bundledResources() {
            let target = engineFolder.file(relativeFile.path)
            guard fst.writeFile(data, at: target, overwrite: overwrite) else {
                return false
            }
        }

        return true
    }
    
    init(from folder: Folder, in fst: FileSystemTree) throws {
        guard let folderContents = fst.inspectFolder(at: folder) else {
            throw EngineDecodingError.missingFolder(folder, .init())
        }
        guard let engineDataFile = folderContents.files.first(where: { $0.fileType == "json" }) else {
            throw EngineDecodingError.missingData(.init())
        }
        
        guard let rawEngineData = fst.readFile(at: engineDataFile) else {
            throw EngineDecodingError.couldntReadData(engineDataFile, .init())
        }
        
        var decodedEngineData: DataType?
        do {
            decodedEngineData = try JSONDecoder().decode(DataType.self, from: rawEngineData)
        } catch let error {
            throw EngineDecodingError.dataDecodingFailed(error, .init())
        }
        guard let engineData = decodedEngineData else {
            throw EngineDecodingError.generic(.init())
        }
        
        var enumEntries = [Enum]()
        let enumsFolder = folder.folder("Enumerations")
        if folderContents.subFolders.contains(enumsFolder),
           let enumsFolderContents = fst.inspectFolder(at: enumsFolder)?.files.withExtension("json") {
            for file in enumsFolderContents {
                guard let rawEnumData: GoDData = fst.readFile(at: file) else {
                    throw EngineDecodingError.couldntReadEnumData(file, .init())
                }
                do {
                    let enumData = try JSONDecoder().decode(Enum.self, from: rawEnumData)
                    enumEntries.append(enumData)
                } catch let error {
                    throw EngineDecodingError.couldntDecodeEnum(file, error, .init())
                }
            }
        }
        let enums = try EnumsType(validated: enumEntries)
        
        var structEntries = [StructMap]()
        let structsFolder = folder.folder("Structs")
        if folderContents.subFolders.contains(structsFolder),
           let structsFolderContents = fst.inspectFolder(at: structsFolder)?.files.withExtension("json") {
            for file in structsFolderContents {
                guard let rawStructData: GoDData = fst.readFile(at: file) else {
                    throw EngineDecodingError.couldntReadStructData(file, .init())
                }
                do {
                    let structData = try JSONDecoder().decode(StructMap.self, from: rawStructData)
                    structEntries.append(structData)
                } catch let error {
                    throw EngineDecodingError.couldntDecodeStruct(file, error, .init())
                }
            }
        }
        
        let structs = try StructsType(validated: structEntries)
        
        try self.init(
            data: engineData,
            enums: enums,
            structs: structs
        )
    }
}
