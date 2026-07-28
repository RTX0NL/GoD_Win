import GoDFoundation

public enum EngineDecodingError: Error, CustomStringConvertible {
    case missingFolder(Folder, ErrorTrace)
    case missingData(ErrorTrace)
    case couldntReadData(File, ErrorTrace)
    case dataDecodingFailed(Error, ErrorTrace)
    case couldntReadEnumData(File, ErrorTrace)
    case couldntDecodeEnum(File, Error, ErrorTrace)
    case couldntReadStructData(File, ErrorTrace)
    case couldntDecodeStruct(File, Error, ErrorTrace)
    case missingEnumProperty(structName: String, property: String, enumName: String, ErrorTrace)
    case missingEnums([String], ErrorTrace)
    case missingStructProperty(structName: String, property: String, substructName: String, ErrorTrace)
    case missingStructs([String], ErrorTrace)
    case cyclicDependency(String, String, ErrorTrace)
    case invalidStructPropertyNames(structName: String, names: [String], ErrorTrace)
    case duplicateStructPropertyNames(structName: String, names: [String], ErrorTrace)
    case generic(ErrorTrace)
    
    public var description: String {
        switch self {
        case let .missingFolder(folder, errorTrace):
            return "Error: Missing folder for engine: \(folder)\n\(errorTrace)"
        case let .missingData(errorTrace):
            return "Error: Missing json data file for engine\n\(errorTrace)"
        case let .couldntReadData(file, errorTrace):
            return "Error: Couldn't read engine data file: \(file)\n\(errorTrace)"
        case let .dataDecodingFailed(error, errorTrace):
            return "Error: Invalid json data for engine.\n\(error)\n\(errorTrace)"
        case let .couldntReadEnumData(file, errorTrace):
            return "Error: Couldn't read enum file: \(file)\n\(errorTrace)"
        case let .couldntDecodeEnum(file, error, errorTrace):
            return "Error: Invalid enum data file: \(file)\n\(error)\n\(errorTrace)"
        case let .couldntReadStructData(file, errorTrace):
            return "Error: Couldn't read struct file: \(file)\n\(errorTrace)"
        case let .couldntDecodeStruct(file, error, errorTrace):
            return "Error: Invalid struct data file: \(file)\n\(error)\n\(errorTrace)"
        case let .missingEnumProperty(structName, property, enumName, errorTrace):
            return "Error: Couldn't find definition for type, '\(enumName)' required by property, '\(property)' of struct, '\(structName)'\n\(errorTrace)"
        case let .missingEnums(names, errorTrace):
            return "Error: Couldn't find entries for enumerations:\n\(names.joined(separator: ", "))\n\(errorTrace)"
        case let .missingStructProperty(structName, property, substructName, errorTrace):
            return "Error: Couldn't find definition for type, '\(substructName)' required by property, '\(property)' of struct, '\(structName)'\n\(errorTrace)"
        case let .missingStructs(names, errorTrace):
            return "Error: Couldn't find entries for structs:\n\(names.joined(separator: ", "))\n\(errorTrace)"
        case let .cyclicDependency(first, second, errorTrace):
            return "Error: Definitions for structs of type `\(first)` and `\(second)` have a cyclic reference to each other.\n\(errorTrace)"
        case let .invalidStructPropertyNames(structName, names, errorTrace):
            return "Error: Struct '\(structName)' has invalid property names: \(names.joined(separator: ", ")). "
                + "A property name must start with a letter or '_' and contain only letters, digits and '_'.\n\(errorTrace)"
        case let .duplicateStructPropertyNames(structName, names, errorTrace):
            return "Error: Struct '\(structName)' declares these property names more than once: \(names.joined(separator: ", ")). "
                + "Property names are matched exactly, so a duplicate makes the field ambiguous.\n\(errorTrace)"
        case let .generic(errorTrace):
            return "Error: Something went wrong\n\(errorTrace)"
        }
    }
}
