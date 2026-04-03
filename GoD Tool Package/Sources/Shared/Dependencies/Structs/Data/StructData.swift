import GoDFoundation

@dynamicMemberLookup
public class StructData {

    public let definition: StructDefinition
    public let data: GoDData

    public var name: String { definition.name }
    public var properties: [StructDefinition.Property] { definition.properties }
    public var byteOrder: ByteOrder { data.byteOrder }
    public var length: Int { definition.length }
    public var wordSize: Int { definition.wordSize }

    public init(
        definition: StructDefinition,
        data: GoDData
    ) {
        self.definition = definition
        self.data = data

        if data.length < definition.length {
            let difference = Int(definition.length) - data.length
            data.append(GoDData(length: difference))
        }
    }
    
    public convenience init(definition: StructDefinition, byteOrder: ByteOrder) {
        self.init(definition: definition, data: GoDData(length: definition.length, byteOrder: byteOrder))
    }
    
    public subscript(dynamicMember member: String) -> GoDData {
        get throws {
            guard let data: GoDData = self.get(member) else {
                throw StructError.MissingKey(key: member, struct: self, .init())
            }
            return data
        }
    }

    public subscript(dynamicMember member: String) -> GoDData? {
        get {
            self.get(member)
        }
        set {
            self.set(member, to: newValue)
        }
    }
    
    public subscript(dynamicMember member: String) -> StructData {
        get throws {
            guard let data: StructData = self.get(member) else {
                throw StructError.MissingKey(key: member, struct: self, .init())
            }
            return data
        }
    }

    public subscript(dynamicMember member: String) -> StructData? {
        get {
            self.get(member)
        }
        set {
            self.set(member, to: newValue?.data)
        }
    }
    
    public subscript<T: ExpressibleByData>(dynamicMember member: String) -> T {
        get throws {
            let data: GoDData = try self[dynamicMember: member]
            guard let value = T(data: data) else {
                let type = definition.property(for: member) ?? .void
                throw StructError.TypeMismatch(key: member, propertyType: type, type: T.self, struct: self, .init())
            }
            return value
        }
    }

    public subscript<T: DataRepresentable>(dynamicMember member: String) -> T? {
        get {
            self.get(member)
        }
        set {
            self.set(member, to: newValue?.rawData)
        }
    }
    
    public subscript(dynamicMember member: String) -> Int? {
        get {
            self.get(member)
        }
        set {
            self.set(member, to: newValue)
        }
    }
    
    public subscript(dynamicMember member: String) -> String {
        get throws {
            let data: GoDData = try self[dynamicMember: member]
            return data.string(format: .utf8)
        }
    }
    
    public subscript(dynamicMember member: String) -> String? {
        get {
            self.getString(member, format: .utf8)
        }
        set {
            guard let newValue, let type = definition.property(for: member) else {
                return
            }
            switch type {
            case .enumeration(let enumeration):
                if let enumCase = try? enumeration.get(newValue) {
                    let value: Int? = enumCase.rawValue
                    set(member, to: value)
                }
            default:
                set(member, to: newValue, format: .utf8)
            }
        }
    }
    
    public subscript(dynamicMember member: String) -> Enum.Case {
        get throws {
            guard let type = definition.property(for: member) else {
                throw StructError.MissingKey(key: member, struct: self, .init())
            }
            guard case .enumeration(let enumDef) = type else {
                throw StructError.TypeMismatch(key: member, propertyType: type, type: Enum.Case.self, struct: self, .init())
            }

            let rawValue: Int = try self[dynamicMember: member]
            let value = try enumDef.get(rawValue)
            
            return value
        }
    }

    public subscript(dynamicMember member: String) -> Enum.Case? {
        get {
            self.get(member)
        }
        set {
            self.set(member, to: newValue)
        }
    }

    public func get(_ keypath: String) -> GoDData? {
        guard let offset = definition.offset(for: keypath),
              let length = definition.property(for: keypath)?.length else {
            return nil
        }

        return data.read(atAddress: offset, length: length)
    }
    
    public func get(_ keypath: String) -> Int? {
        guard let data: GoDData = get(keypath),
              let property = definition.property(for: keypath) else { return nil }
        
        func getInteger(_ type: IntegerProperties) -> Int? {
            switch type {
            case .uint8, .uint16, .uint24, .uint32, .uint64:
                return Int(data: data)
            case .int8:
                return data.readTypeAsInt(Int8.self, atAddress: 0)
            case .int16:
                return data.readTypeAsInt(Int16.self, atAddress: 0)
            case .int24:
                guard let firstByte: UInt8 = data.readValue(atAddress: 0) else {
                    return Int(data: data)
                }
                let isNegative = firstByte > 0x7F
                let fillByte = GoDData(byteStream: [isNegative ? 0xFF : 0x00])
                data.insert(fillByte, atOffset: 0)
                return data.readTypeAsInt(Int32.self, atAddress: 0)
            case .int32:
                return data.readTypeAsInt(Int32.self, atAddress: 0)
            case .int64:
                return data.readTypeAsInt(Int64.self, atAddress: 0)
            }
        }
        
        switch property {
        case .primitive(.integer(let type)):
            return getInteger(type)
        case .enumeration(let definition):
            return getInteger(definition.propertyType)
        case .primitive, .array, .subStruct, .padding:
            return Int(data: data)
        }
    }

    public func get(_ keypath: String) -> StructData? {
        guard let property = definition.property(for: keypath),
              let data: GoDData = get(keypath),
              case let .subStruct(structDefinition) = property else {
            return nil
        }

        return StructData(definition: structDefinition, data: data)
    }

    public func get<T: ExpressibleByData>(_ keypath: String) -> T? {
        guard let data: GoDData = get(keypath) else {
            return nil
        }
        return T(data: data)
    }
    
    public func get(_ keypath: String) -> Enum.Case? {
        guard let type = definition.property(for: keypath) else {
            return nil
        }
        guard case .enumeration(let definition) = type else {
            return nil
        }

        let rawValue: Int = get(keypath) ?? 0
        let value = try? definition.get(rawValue)
        
        return value
    }
    
    public func getString(_ keypath: String, format: StringFormats) -> String? {
        guard let data: GoDData = get(keypath) else {
            return nil
        }
        return data.string(format: format)
    }
    
    public func set(_ keypath: String, to value: Int?) {
        let data = (value ?? 0).rawData
        if byteOrder != .unspecified, byteOrder != Environment.byteOrder {
            data.switchByteOrder(boundary: Environment.wordSize)
        }
        set(keypath, to: data)
    }

    public func set(_ keypath: String, to value: GoDData?) {
        guard let offset = definition.offset(for: keypath),
              let length = definition.property(for: keypath)?.length else {
            return
        }
        let newValue = value?.copy ?? GoDData(length: length)
        
        if !newValue.byteOrder.matches(self.byteOrder) {
            newValue.switchByteOrder(boundary: wordSize)
        }
        if newValue.length > length {
            let extra = newValue.length - length
            let extraWords = extra / wordSize
            let extraBytes = extra % wordSize
            for _ in 0 ..< extraWords {
                newValue.delete(start: 0, count: wordSize)
            }
            if byteOrder == .little {
                newValue.delete(start: wordSize - extraBytes, count: extraBytes)
            } else {
                newValue.delete(start: 0, count: extraBytes)
            }
        }
        if newValue.length < length {
            newValue.prepend(GoDData(length: length - newValue.length))
        }
        data.write(newValue, atAddress: offset)
    }

    public func set<T: DataConvertible>(_ keypath: String, to value: T) {
        set(keypath, to: value.rawData)
    }
    
    public func set(_ keypath: String, to value: String, format: StringFormats) {
        set(keypath, to: value.data(format: format))
    }
    
    public func set(_ keypath: String, to value: Enum.Case?) {
        set(keypath, to: value?.rawValue)
    }
}

extension StructData: Equatable {

    public static func == (lhs: StructData, rhs: StructData) -> Bool {
        lhs.data.rawBytes == rhs.data.rawBytes
    }
}

extension StructData: CustomStringConvertible {
    public var description: String {
        func description(for primitive: StructPrimitives, name: String) -> String {
            switch primitive {
            case .void:
                return "\(name) = null"
            case .integer:
                guard let value: Int = get(name) else { return "\(name) = N/A" }
                return "\(name) = \(value)"
            case .float:
                guard let value: Float = get(name) else { return "\(name) = N/A" }
                return "\(name) = \(value)"
            case .double:
                guard let value: Double = get(name) else { return "\(name) = N/A" }
                return "\(name) = \(value)"
            case .boolean:
                guard let value: Bool = get(name) else { return "\(name) = N/A" }
                return "\(name) = \(value)"
            case .character(let format):
                guard let string: String = getString(name, format: format) else { return "\(name) = N/A" }
                return "\(name) = \(string)"
            }
        }
        
        var result = ""
        for property in properties {
            let name = property.name
            let typeName = property.type.description
            
            switch property.type {
            case .primitive(let type):
                result += description(for: type, name: name) + " <\(typeName)>\n"
            case .array(.primitive(.character(let format)), _):
                result += description(for: .character(format), name: name) + " <\(typeName)>\n"
            case .enumeration(let enumeration):
                guard let value: Int = get(name) else { result += "\(name) = N/A\n"; continue }
                let enumValue = try? enumeration.get(value)
                result += "\(name) = \(enumValue?.name ?? "unknown") (\(value)) <\(enumeration.name)>\n"
            case .subStruct:
                guard let data: StructData = get(name) else {
                    result += "N/A"; continue
                }
                result += "\(name):\n" + data.description + "\n"
            case .array(_, let count):
                result += "\(name): \(count) items <\(typeName)>\n"
            case .padding:
                continue
            }
        }
        result.removeLast()
        return result
    }
}

extension StructData: Encodable {
    
    public func encode(to encoder: Encoder) throws {
        func readInt(subType: IntegerProperties, from data: GoDData) -> Int {
            switch subType {
            case .uint8: return data.readTypeAsInt(UInt8.self, atAddress: 0)
            case .int8: return data.readTypeAsInt(Int8.self, atAddress: 0)
            case .uint16: return data.readTypeAsInt(UInt16.self, atAddress: 0)
            case .int16: return data.readTypeAsInt(Int16.self, atAddress: 0)
            case .uint24, .int24:
                let extended = GoDData(length: 4, byteOrder: data.byteOrder)
                extended.write(data, atAddress: 1)
                return extended.readTypeAsInt(Int32.self, atAddress: 0)
            case .uint32: return data.readTypeAsInt(UInt32.self, atAddress: 0)
            case .int32: return data.readTypeAsInt(Int32.self, atAddress: 0)
            case .uint64: return data.readTypeAsInt(UInt64.self, atAddress: 0)
            case .int64: return data.readTypeAsInt(Int64.self, atAddress: 0)
            }
        }
        
        func readEnum(definition: Enum, from data: GoDData) throws -> String {
            let value = readInt(subType: definition.propertyType, from: data)
            let enumCase = try definition.get(value)
            return enumCase.name
        }
        
        func encode(
            data: GoDData,
            type: StructProperty,
            count: Int,
            container: inout UnkeyedEncodingContainer
        ) throws {
            switch type {
            case .padding:
                return
            case .primitive(let type):
                switch type {
                case .void:
                    return
                case .integer(let subType):
                    var offset = 0
                    for _ in 0 ..< count {
                        if let data: GoDData = data.read(atAddress: offset, length: subType.length) {
                            let value = readInt(subType: subType, from: data)
                            try container.encode(value)
                        }
                        offset += subType.length
                    }
                case .float:
                    var offset = 0
                    for _ in 0 ..< count {
                        if let value: Float = data.readPrimtive(atAddress: offset) {
                            try container.encode(value)
                        }
                        offset += Float.byteLength
                    }
                case .double:
                    var offset = 0
                    for _ in 0 ..< count {
                        if let value: Double = data.readPrimtive(atAddress: offset) {
                            try container.encode(value)
                        }
                        offset += Double.byteLength
                    }
                case .boolean:
                    var offset = 0
                    for _ in 0 ..< count {
                        if let value: Bool = data.readPrimtive(atAddress: offset) {
                            try container.encode(value)
                        }
                        offset += Bool.byteLength
                    }
                case .character(let format):
                    if let value: String = data.readString(atAddress: 0, format: format, maxCharacters: count) {
                        try container.encode(value)
                    }
                }
            case .enumeration(let definition):
                var offset = 0
                for _ in 0 ..< count {
                    if let data: GoDData = data.read(atAddress: offset, length: definition.propertyType.length) {
                        let value = try readEnum(definition: definition, from: data)
                        try container.encode(value)
                    }
                    offset += definition.propertyType.length
                }
            case .array(let subProperty, let subCount):
                var offset = 0
                for _ in 0 ..< count {
                    if let data: GoDData = data.read(atAddress: offset, length: subProperty.length * subCount) {
                        var container = container.nestedUnkeyedContainer()
                        try encode(data: data, type: subProperty, count: subCount, container: &container)
                    }
                    offset += subProperty.length * subCount
                }
            case .subStruct(let definition):
                var offset = 0
                for _ in 0 ..< count {
                    if let data: GoDData = data.read(atAddress: offset, length: definition.length) {
                        var container = container.nestedContainer(keyedBy: CustomCodingKeys.self)
                        let structData = StructData(definition: definition, data: data)
                        try definition.properties.forEach { property in
                            if let data: GoDData = structData.get(property.name) {
                                try encode(data: data, type: property.type, key: .init(property.name), container: &container)
                            }
                        }
                    }
                    offset += definition.length
                }
                var container = container.nestedContainer(keyedBy: CustomCodingKeys.self)
                let structData = StructData(definition: definition, data: data)
                try definition.properties.forEach { property in
                    guard let data: GoDData = structData.get(property.name) else { return }
                    try encode(data: data, type: property.type, key: .init(property.name), container: &container)
                }
            }
        }
        
        func encode(
            data: GoDData,
            type: StructProperty,
            key: CustomCodingKeys,
            container: inout KeyedEncodingContainer<CustomCodingKeys>
        ) throws {
            switch type {
            case .padding:
                return
            case .primitive(let type):
                switch type {
                case .void:
                    return
                case .integer(let subType):
                    let value = readInt(subType: subType, from: data)
                    try container.encode(value, forKey: key)
                case .float:
                    let value: Float = data.readPrimtive(atAddress: 0)!
                    try container.encode(value, forKey: key)
                case .double:
                    let value: Double = data.readPrimtive(atAddress: 0)!
                    try container.encode(value, forKey: key)
                case .boolean:
                    let value: Bool = !data.isNull
                    try container.encode(value, forKey: key)
                case .character(let format):
                    let value: String = data.readString(atAddress: 0, format: format, maxCharacters: 1)!
                    try container.encode(value, forKey: key)
                }
            case .enumeration(let definition):
                let value = try readEnum(definition: definition, from: data)
                try container.encode(value, forKey: key)
            case .array(let subProperty, let count):
                var container = container.nestedUnkeyedContainer(forKey: key)
                try encode(data: data, type: subProperty, count: count, container: &container)
            case .subStruct(let definition):
                var container = container.nestedContainer(keyedBy: CustomCodingKeys.self, forKey: key)
                let structData = StructData(definition: definition, data: data)
                try definition.properties.forEach { property in
                    guard let data: GoDData = structData.get(property.name) else { return }
                    try encode(data: data, type: property.type, key: .init(property.name), container: &container)
                }
            }
        }
        
        var container = encoder.container(keyedBy: CustomCodingKeys.self)
        
        try container.encode(definition.name, forKey: "type")
        try encode(data: self.data, type: .subStruct(self.definition), key: "data", container: &container)
    }
}
