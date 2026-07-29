import Foundation
import GoDFoundation

@dynamicMemberLookup
public class StructData {

    public let definition: StructDefinition
    public let data: GoDData

    /// Maps label property names to their label name strings.
    /// These are NOT stored in the raw binary data — they exist only in this side dictionary.
    /// During assembly, label names are resolved to UInt32 addresses via the global symbol table.
    public var labelValues: [String: String] = [:]

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
            data.append(GoDData(length: difference, byteOrder: data.byteOrder))
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
            self.set(member, to: newValue?.rawData(byteOrder: self.byteOrder))
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

    // MARK: - Label accessors

    /// Get the label name for a label property
    public func getLabel(_ keypath: String) -> String? {
        guard let property = definition.property(for: keypath),
              case .label = property else { return nil }
        return labelValues[keypath]
    }

    /// Set the label name for a label property
    public func setLabel(_ keypath: String, to labelName: String?) {
        guard let property = definition.property(for: keypath),
              case .label = property else { return }
        labelValues[keypath] = labelName
    }

    // MARK: - Data accessors

    /// Warns, in debug builds, when a lookup missed only because of spelling.
    ///
    /// Property names are matched exactly, and the optional accessors return
    /// nil rather than throwing, so `header.fileDataPointer` against a
    /// declared `file_data_pointer` would otherwise read as "field absent"
    /// and write nothing. The throwing accessors carry the same hint in
    /// `StructError.MissingKey`.
    private func warnIfNearMiss(_ keypath: String) {
        #if DEBUG
        if let suggestion = definition.closestPropertyName(to: keypath) {
            FileHandle.standardError.write(Data(
                "WARNING: struct '\(definition.name)' has no property '\(keypath)' — did you mean '\(suggestion)'?\n".utf8
            ))
        }
        #endif
    }

    public func get(_ keypath: String) -> GoDData? {
        guard let offset = definition.offset(for: keypath),
              let length = definition.property(for: keypath)?.length else {
            warnIfNearMiss(keypath)
            return nil
        }

        return data.read(atAddress: offset, length: length)
    }
    
    public func get(_ keypath: String) -> Int? {
        guard let data: GoDData = get(keypath),
              let property = definition.property(for: keypath) else { return nil }
        
        func getInteger(_ type: IntegerProperties) -> Int? {
            Self.readInteger(from: data, width: type.length, signed: type.isSigned, byteOrder: self.byteOrder)
        }
        
        switch property {
        case .primitive(.integer(let type)):
            return getInteger(type)
        case .enumeration(let definition):
            return getInteger(definition.propertyType)
        case .primitive, .array, .subStruct, .label, .padding:
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
        let data = (value ?? 0).rawData(byteOrder: self.byteOrder)
        set(keypath, to: data)
    }

    public func set(_ keypath: String, to value: GoDData?) {
        guard let offset = definition.offset(for: keypath),
              let length = definition.property(for: keypath)?.length else {
            warnIfNearMiss(keypath)
            return
        }
        let newValue = value?.copy ?? GoDData(length: length, byteOrder: self.byteOrder)

        if newValue.length > length {
            // Truncate to the field width by dropping the most-significant
            // (high-order) bytes. Those live at the FRONT for big-endian and
            // at the BACK for little-endian, so the delete position depends
            // on byte order. (The previous word-chunk logic always deleted
            // from the front, which discards the LOW bytes on little-endian
            // and corrupts the value.)
            let extra = newValue.length - length
            if byteOrder == .little {
                newValue.delete(start: length, count: extra)
            } else {
                newValue.delete(start: 0, count: extra)
            }
        }
        if newValue.length < length {
            // Zero-extend on the high-order side: the front for big-endian,
            // the back for little-endian.
            let padding = GoDData(length: length - newValue.length, byteOrder: self.byteOrder)
            if byteOrder == .little {
                newValue.append(padding)
            } else {
                newValue.prepend(padding)
            }
        }
        data.write(newValue, atAddress: offset)
    }

    public func set<T: DataConvertible>(_ keypath: String, to value: T) {
        set(keypath, to: value.rawData(byteOrder: self.byteOrder))
    }
    
    public func set(_ keypath: String, to value: String, format: StringFormats) {
        set(keypath, to: value.data(format: format))
    }
    
    public func set(_ keypath: String, to value: Enum.Case?) {
        set(keypath, to: value?.rawValue)
    }

    /// Writes an enum-typed field by case name, throwing if the field isn't
    /// an enum or the enum doesn't define that case.
    ///
    /// Prefer this over the `String?` dynamic-member setter for anything
    /// that writes real game data: a subscript setter can't throw, so that
    /// path can only skip an unrecognised case silently, leaving the field
    /// at whatever it already held (zero, for a fresh struct). A file type
    /// the engine's enum doesn't list would then be written as type 0.
    public func setEnumCase(_ keypath: String, named caseName: String) throws {
        guard let type = definition.property(for: keypath) else {
            throw StructError.MissingKey(key: keypath, struct: self, .init())
        }
        guard case .enumeration(let enumeration) = type else {
            throw StructError.TypeMismatch(key: keypath, propertyType: type, type: Enum.Case.self, struct: self, .init())
        }
        let enumCase = try enumeration.get(caseName)
        set(keypath, to: enumCase.rawValue)
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
            case .float, .lossless_float:
                guard let value: Float = get(name) else { return "\(name) = N/A" }
                return "\(name) = \(value)"
            case .double, .lossless_double:
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
            case .label:
                let labelName = labelValues[name] ?? "N/A"
                result += "\(name) = \(labelName) <label>\n"
            case .array(_, let count):
                result += "\(name): \(count) items <\(typeName)>\n"
            case .padding:
                continue
            }
        }
        if !result.isEmpty { result.removeLast() }
        return result
    }
}

extension StructData: Encodable {
    
    public func encode(to encoder: Encoder) throws {
        func readInt(subType: IntegerProperties, from data: GoDData) -> Int {
            StructData.readInteger(from: data, width: subType.length, signed: subType.isSigned, byteOrder: data.byteOrder) ?? 0
        }
        
        // Enum fields encode as the case name when the raw value has a
        // named case, and as the raw integer otherwise — an unnamed
        // value must not fail the whole struct's encode. The decoder
        // accepts both forms symmetrically.
        func encodeEnum(definition: Enum, from data: GoDData, into container: inout UnkeyedEncodingContainer) throws {
            let value = readInt(subType: definition.propertyType, from: data)
            if let enumCase = try? definition.get(value) {
                try container.encode(enumCase.name)
            } else {
                try container.encode(value)
            }
        }

        // A boolean field must hold exactly 0 or 1. Anything else means
        // the definition and the data disagree — most often a field typed
        // `boolean` that is really a small integer or a bitfield — and
        // collapsing it to `true` would silently rewrite the byte as 1 on
        // the way back out.
        func readBool(from data: GoDData, key: CustomCodingKeys) throws -> Bool {
            guard let raw = data[safe: 0] else {
                throw encodeReadError(key, "Bool")
            }
            switch raw {
            case 0: return false
            case 1: return true
            default:
                throw EncodingError.invalidValue(
                    raw,
                    EncodingError.Context(
                        codingPath: [key],
                        debugDescription: "StructData: boolean field '\(key.stringValue)' holds 0x\(String(raw, radix: 16, uppercase: true)), which is neither 0 nor 1 — the field is probably not a boolean"
                    )
                )
            }
        }

        // Raised when a single-value field's backing data is too short
        // to decode the expected primitive (previously a force-unwrap
        // crash on malformed / truncated struct data).
        func encodeReadError(_ key: CustomCodingKeys, _ typeName: String) -> EncodingError {
            EncodingError.invalidValue(
                typeName,
                EncodingError.Context(
                    codingPath: [key],
                    debugDescription: "StructData: field data too short to read \(typeName) for key '\(key.stringValue)'"
                )
            )
        }
        
        func encode(
            data: GoDData,
            type: StructProperty,
            count: Int,
            labels: [String: String],
            container: inout UnkeyedEncodingContainer
        ) throws {
            switch type {
            case .padding:
                return
            case .label:
                // Label elements carry no per-element name, so the raw
                // pointer address is emitted as an auto label string.
                // The decoder records these into `labelValues` under
                // `name[i]` keys and the importer resolves them back
                // to addresses at assembly time.
                var offset = 0
                for _ in 0 ..< count {
                    if let element: GoDData = data.read(atAddress: offset, length: 4),
                       let address = StructData.readInteger(from: element, width: 4, signed: false, byteOrder: data.byteOrder) {
                        try container.encode("lbl_\(String(format: "%08X", UInt32(truncatingIfNeeded: address)))")
                    }
                    offset += 4
                }
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
                case .lossless_float:
                    var offset = 0
                    for _ in 0 ..< count {
                        if let value: Float = data.readPrimtive(atAddress: offset) {
                            try container.encode(LosslessFloat(value))
                        }
                        offset += Float.byteLength
                    }
                case .lossless_double:
                    var offset = 0
                    for _ in 0 ..< count {
                        if let value: Double = data.readPrimtive(atAddress: offset) {
                            try container.encode(LosslessDouble(value))
                        }
                        offset += Double.byteLength
                    }
                case .boolean:
                    var offset = 0
                    for index in 0 ..< count {
                        if let element: GoDData = data.read(atAddress: offset, length: Bool.byteLength) {
                            try container.encode(
                                readBool(from: element, key: CustomCodingKeys("[\(index)]"))
                            )
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
                        try encodeEnum(definition: definition, from: data, into: &container)
                    }
                    offset += definition.propertyType.length
                }
            case .array(let subProperty, let subCount):
                var offset = 0
                for _ in 0 ..< count {
                    if let data: GoDData = data.read(atAddress: offset, length: subProperty.length * subCount) {
                        var container = container.nestedUnkeyedContainer()
                        try encode(data: data, type: subProperty, count: subCount, labels: labels, container: &container)
                    }
                    offset += subProperty.length * subCount
                }
            case .subStruct(let definition):
                var offset = 0
                for _ in 0 ..< count {
                    if let data: GoDData = data.read(atAddress: offset, length: definition.length) {
                        var container = container.nestedContainer(keyedBy: CustomCodingKeys.self)
                        let structData = StructData(definition: definition, data: data)
                        structData.labelValues = labels
                        var subPaddingIdx = 0
                        var subOffset = 0
                        try definition.properties.forEach { property in
                            try encodeProperty(property, of: structData, labels: structData.labelValues, paddingIndex: &subPaddingIdx, offset: &subOffset, alignment: definition.alignmentStyle, container: &container)
                        }
                    }
                    offset += definition.length
                }
            }
        }

        // `.padding(length:)` produces a property literally named
        // `"padding"`, so a struct with multiple padding regions
        // would collide on the same JSON key. We auto-rename them
        // to `padding_<i>` at encode time, where `i` counts padding
        // properties within the current keyed-container scope.
        // The decoder applies the same scheme symmetrically.
        func paddingKey(_ index: Int) -> CustomCodingKeys {
            CustomCodingKeys("padding_\(index)")
        }

        func encodeProperty(
            _ property: StructDefinition.Property,
            of structData: StructData,
            labels: [String: String],
            paddingIndex: inout Int,
            offset: inout Int,
            alignment: StructAlignmentStyles,
            container: inout KeyedEncodingContainer<CustomCodingKeys>
        ) throws {
            switch alignment {
            case .none:
                break
            case .cStyle:
                let alignmentOffset = offset % property.type.alignment
                if alignmentOffset > 0 {
                    offset += property.type.alignment - alignmentOffset
                }
            }

            let key: CustomCodingKeys
            if property.name == "padding" {
                key = paddingKey(paddingIndex)
                paddingIndex += 1
            } else {
                key = CustomCodingKeys(property.name)
            }
            let length = property.type.length
            switch property.type {
            case .label:
                let labelName = structData.labelValues[property.name] ?? ""
                try container.encode(labelName, forKey: key)
            default:
                if let data: GoDData = structData.data.read(atAddress: offset, length: length) {
                    try encode(data: data, type: property.type, key: key, labels: labels, container: &container)
                }
            }
            offset += length
        }

        func encode(
            data: GoDData,
            type: StructProperty,
            key: CustomCodingKeys,
            labels: [String: String],
            container: inout KeyedEncodingContainer<CustomCodingKeys>
        ) throws {
            switch type {
            case .padding:
                return
            case .label:
                return
            case .primitive(let type):
                switch type {
                case .void:
                    return
                case .integer(let subType):
                    let value = readInt(subType: subType, from: data)
                    try container.encode(value, forKey: key)
                case .float:
                    guard let value: Float = data.readPrimtive(atAddress: 0) else {
                        throw encodeReadError(key, "Float")
                    }
                    try container.encode(value, forKey: key)
                case .double:
                    guard let value: Double = data.readPrimtive(atAddress: 0) else {
                        throw encodeReadError(key, "Double")
                    }
                    try container.encode(value, forKey: key)
                case .lossless_float:
                    guard let value: Float = data.readPrimtive(atAddress: 0) else {
                        throw encodeReadError(key, "LosslessFloat")
                    }
                    try container.encode(LosslessFloat(value), forKey: key)
                case .lossless_double:
                    guard let value: Double = data.readPrimtive(atAddress: 0) else {
                        throw encodeReadError(key, "LosslessDouble")
                    }
                    try container.encode(LosslessDouble(value), forKey: key)
                case .boolean:
                    try container.encode(readBool(from: data, key: key), forKey: key)
                case .character(let format):
                    guard let value: String = data.readString(atAddress: 0, format: format, maxCharacters: 1) else {
                        throw encodeReadError(key, "String")
                    }
                    try container.encode(value, forKey: key)
                }
            case .enumeration(let definition):
                let raw = readInt(subType: definition.propertyType, from: data)
                if let enumCase = try? definition.get(raw) {
                    try container.encode(enumCase.name, forKey: key)
                } else {
                    try container.encode(raw, forKey: key)
                }
            case .array(let subProperty, let count):
                var container = container.nestedUnkeyedContainer(forKey: key)
                try encode(data: data, type: subProperty, count: count, labels: labels, container: &container)
            case .subStruct(let definition):
                var container = container.nestedContainer(keyedBy: CustomCodingKeys.self, forKey: key)
                let structData = StructData(definition: definition, data: data)
                structData.labelValues = labels
                var subPaddingIdx = 0
                var subOffset = 0
                try definition.properties.forEach { property in
                    try encodeProperty(property, of: structData, labels: structData.labelValues, paddingIndex: &subPaddingIdx, offset: &subOffset, alignment: definition.alignmentStyle, container: &container)
                }
            }
        }

        var container = encoder.container(keyedBy: CustomCodingKeys.self)

        try container.encode(definition.name, forKey: "type")

        // Encode struct properties using encodeProperty for label-aware encoding
        var dataContainer = container.nestedContainer(keyedBy: CustomCodingKeys.self, forKey: "data")
        var topPaddingIdx = 0
        var topOffset = 0
        for property in definition.properties {
            try encodeProperty(property, of: self, labels: self.labelValues, paddingIndex: &topPaddingIdx, offset: &topOffset, alignment: definition.alignmentStyle, container: &dataContainer)
        }
    }
}

// MARK: - JSON → StructData decode
//
// Inverse of `encode(to:)`. Mirrors the encoder's switch ladder
// case-by-case so the two halves stay byte-identical when no edits
// are made — this is what unblocks edits-survive-rebuild for both
// the save pipeline and the DOL/REL chunk pipeline.
//
// `StructData` can't conform to plain `Decodable` because the JSON
// alone doesn't carry the schema — the `StructDefinition` has to
// come in from outside. Two equivalent entry points:
//   1. `init(definition:json:)` for callers that have a `GoDData`
//      / `Data` blob in hand (the common case for ops reading a
//      `.json` file off disk).
//   2. `init(definition:from:)` for callers using `JSONDecoder`
//      manually — pass the definition through `decoder.userInfo`
//      under `StructData.definitionUserInfoKey` and standard
//      `decode(StructData.self, from:)` works.
//
// `.label` properties round-trip into `self.labelValues`. The
// underlying 4 on-disk bytes are left zero — the symbol resolver
// (DOL/REL) or the in-place save layout (XD/Colo) writes the real
// pointer at assembly / repack time. Same shape as encode, where
// `.label` only emits the label name and not its on-disk value.
//
// `.padding` properties are no-ops on both sides — neither the
// encoder nor the decoder touches the underlying bytes, so they
// stay whatever the surrounding context wrote into them. (For a
// fresh `StructData(definition:byteOrder:)` that's zeros.)

public extension StructData {

    /// Pass a `StructDefinition` in `JSONDecoder.userInfo` under
    /// this key to use vanilla `decode(StructData.self, from:)`.
    static let definitionUserInfoKey = CodingUserInfoKey(rawValue: "structData.definition")!

    /// Decode JSON bytes into a fresh `StructData` of the given
    /// definition. The JSON must match the shape `encode(to:)`
    /// produces: a top-level object with `"type"` (definition name,
    /// for sanity-checking) and `"data"` (the field tree).
    convenience init(
        definition: StructDefinition,
        json: GoDData,
        byteOrder: ByteOrder = .big
    ) throws {
        self.init(definition: definition, byteOrder: byteOrder)

        let raw = try JSONSerialization.jsonObject(with: json.data, options: [])
        guard let root = raw as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "StructData JSON is not a top-level object"
            ))
        }
        if let typeName = root["type"] as? String, typeName != definition.name {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CustomCodingKeys("type")],
                debugDescription: "StructData JSON 'type' is '\(typeName)', expected '\(definition.name)'"
            ))
        }
        guard let dataNode = root["data"] as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CustomCodingKeys("data")],
                debugDescription: "StructData JSON missing 'data' object"
            ))
        }

        try StructData.populate(
            properties: definition.properties,
            into: data,
            atOffset: 0,
            wordSize: definition.wordSize,
            alignment: definition.alignmentStyle,
            from: dataNode,
            labelValues: &self.labelValues,
            byteOrder: byteOrder
        )
    }

    convenience init(from decoder: Decoder) throws {
        guard let definition = decoder.userInfo[StructData.definitionUserInfoKey] as? StructDefinition else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "StructData.init(from:) needs a StructDefinition under decoder.userInfo[StructData.definitionUserInfoKey]"
            ))
        }
        // Re-encode the decoder's container back into JSON bytes,
        // then run the schema-aware path. This is slightly wasteful
        // but lets us reuse the JSONSerialization-driven implementation
        // — Decoder doesn't expose enough machinery to walk a
        // schema-driven tree directly.
        let container = try decoder.singleValueContainer()
        let any = try container.decode(JSONAny.self).value
        let bytes = try JSONSerialization.data(withJSONObject: any, options: [])
        try self.init(
            definition: definition,
            json: GoDData(byteStream: [UInt8](bytes), byteOrder: .big)
        )
    }

    // MARK: - Field walker

    private static func populate(
        properties: [StructDefinition.Property],
        into data: GoDData,
        atOffset baseOffset: Int,
        wordSize: Int,
        alignment: StructAlignmentStyles,
        from dataNode: [String: Any],
        labelValues: inout [String: String],
        byteOrder: ByteOrder
    ) throws {
        var offset = baseOffset
        // Mirror the encoder's auto-indexed padding scheme — each
        // padding-named property gets the synthesized JSON key
        // `padding_<i>`, scoped to this populate call (so each
        // sub-struct has its own padding counter).
        var paddingIndex = 0
        for property in properties {
            switch alignment {
            case .none:
                break
            case .cStyle:
                let alignmentOffset = offset % property.type.alignment
                if alignmentOffset > 0 {
                    offset += property.type.alignment - alignmentOffset
                }
            }

            // The bare `.padding` StructProperty case never appears
            // in JSON output — encode skips it — so we skip it here
            // too. (Note: `.padding(length:)` on the StructDefinition.
            // Property *helper* expands to `.array(.uint8, count: N)`
            // with name "padding"; that path goes through `.array`
            // with the synthesized key below.)
            if case .padding = property.type {
                offset += property.type.length
                continue
            }

            // Synthesize the JSON key — `padding_<i>` for padding
            // properties, the property's own name otherwise.
            let key: String
            if property.name == "padding" {
                key = "padding_\(paddingIndex)"
                paddingIndex += 1
            } else {
                key = property.name
            }
            let value = dataNode[key]

            try writeValue(
                value,
                type: property.type,
                propertyName: key,
                into: data,
                atOffset: offset,
                labelValues: &labelValues,
                byteOrder: byteOrder
            )
            offset += property.type.length
        }
    }

    /// Writes one value at one offset, dispatching on its declared type.
    /// Internal rather than private because the CSV codec is a third
    /// serialization over this same ladder — it decomposes a row into leaf
    /// columns and writes each through here, so the byte-level rules
    /// (widths, sign, byte order, enum raw values, string padding) have
    /// exactly one implementation.
    internal static func writeValue(
        _ value: Any?,
        type: StructProperty,
        propertyName: String,
        into data: GoDData,
        atOffset offset: Int,
        labelValues: inout [String: String],
        byteOrder: ByteOrder
    ) throws {
        switch type {
        case .padding:
            return    // already handled by caller
        case .label:
            // Recover the label name into `labelValues`; leave the
            // 4 on-disk bytes zero (matches `encode`'s asymmetry).
            if let name = value as? String {
                labelValues[propertyName] = name
            }
            return
        case .primitive(let prim):
            try writePrimitive(
                value,
                primitive: prim,
                propertyName: propertyName,
                into: data,
                atOffset: offset,
                count: 1,
                byteOrder: byteOrder
            )
        case .enumeration(let definition):
            // Case name preferred; raw integer accepted for values the
            // enum doesn't name (the encoder emits those as integers)
            // or hand-edited numeric values. `allowUnknownCases` enums
            // synthesize `<Enum_Name>_<raw>` names on encode — parse
            // the raw value back out of that shape too.
            let rawValue: Int
            let unknownCasePrefix = definition.name.replacingOccurrences(of: " ", with: "_") + "_"
            if let name = value as? String, let resolved = try? definition.get(name) {
                rawValue = resolved.rawValue
            } else if let name = value as? String,
                      name.hasPrefix(unknownCasePrefix),
                      let synthesized = Int(name.dropFirst(unknownCasePrefix.count)) {
                rawValue = synthesized
            } else if let intValue = coerceToInt(value) {
                rawValue = intValue
            } else {
                throw decodingError("expected case name or raw value for enum '\(definition.name)' at '\(propertyName)'", offset)
            }
            try writeInteger(
                rawValue,
                width: definition.propertyType.length,
                signed: definition.propertyType.isSigned,
                into: data,
                atOffset: offset,
                byteOrder: byteOrder
            )
        case .array(let subProperty, let count):
            try writeArray(
                value,
                element: subProperty,
                count: count,
                propertyName: propertyName,
                into: data,
                atOffset: offset,
                labelValues: &labelValues,
                byteOrder: byteOrder
            )
        case .subStruct(let definition):
            guard let nested = value as? [String: Any] else {
                throw decodingError("expected object for sub-struct '\(definition.name)' at '\(propertyName)'", offset)
            }
            try populate(
                properties: definition.properties,
                into: data,
                atOffset: offset,
                wordSize: definition.wordSize,
                alignment: definition.alignmentStyle,
                from: nested,
                labelValues: &labelValues,
                byteOrder: byteOrder
            )
        }
    }

    private static func writeArray(
        _ value: Any?,
        element: StructProperty,
        count: Int,
        propertyName: String,
        into data: GoDData,
        atOffset offset: Int,
        labelValues: inout [String: String],
        byteOrder: ByteOrder
    ) throws {
        // Older dumps omitted label arrays entirely (the encoder used
        // to skip label elements) — tolerate a missing value and leave
        // the pointer slots zero.
        if case .label = element, value == nil {
            return
        }

        // Special case: an array of characters. The encoder uses a
        // nested unkeyed container with a single `readString(
        // maxCharacters: count)` element, so the JSON shape is an
        // array containing one string — `["hello"]`. Tolerate
        // either the wrapped or unwrapped form on decode.
        if case .primitive(.character(let format)) = element {
            let string: String?
            if let s = value as? String {
                string = s
            } else if let arr = value as? [Any], let s = arr.first as? String {
                string = s
            } else {
                string = nil
            }
            guard let unwrapped = string else {
                throw decodingError("expected String (or [String]) for char array at '\(propertyName)'", offset)
            }
            try writeString(
                unwrapped,
                format: format,
                count: count,
                into: data,
                atOffset: offset,
                byteOrder: byteOrder
            )
            return
        }

        // Otherwise the JSON shape is an array of `count` elements.
        // Each element is dispatched via `writeValue` at its own
        // offset — using the array's own per-element stride
        // (`element.length`).
        guard let array = value as? [Any] else {
            throw decodingError("expected array for '\(propertyName)' (\(element))", offset)
        }
        let stride = element.length
        let take = Swift.min(array.count, count)
        for i in 0..<take {
            // Array elements have no name in the JSON — synthesise
            // one for error messages.
            let elementName = "\(propertyName)[\(i)]"
            try writeValue(
                array[i],
                type: element,
                propertyName: elementName,
                into: data,
                atOffset: offset + i * stride,
                labelValues: &labelValues,
                byteOrder: byteOrder
            )
        }
        // `take < count` is silently tolerated — trailing elements
        // stay zero. Matches the encoder, which only emits as many
        // elements as it could read.
    }

    private static func writePrimitive(
        _ value: Any?,
        primitive: StructPrimitives,
        propertyName: String,
        into data: GoDData,
        atOffset offset: Int,
        count: Int,
        byteOrder: ByteOrder
    ) throws {
        switch primitive {
        case .void:
            return
        case .integer(let subType):
            guard let intValue = coerceToInt(value) else {
                throw decodingError("expected number for '\(propertyName)' (\(subType))", offset)
            }
            try writeInteger(
                intValue,
                width: subType.length,
                signed: subType.isSigned,
                into: data,
                atOffset: offset,
                byteOrder: byteOrder
            )
        case .float:
            guard let dbl = coerceToDouble(value) else {
                throw decodingError("expected number for '\(propertyName)' (float)", offset)
            }
            let bits = Float(dbl).bitPattern
            try writeInteger(
                Int(bits),
                width: 4,
                signed: false,
                into: data,
                atOffset: offset,
                byteOrder: byteOrder
            )
        case .double:
            guard let dbl = coerceToDouble(value) else {
                throw decodingError("expected number for '\(propertyName)' (double)", offset)
            }
            let bits = dbl.bitPattern
            // UInt64 → 8 bytes via the same writer (Int(bits) on
            // 64-bit Swift is fine; bit-pattern preserved).
            try writeInteger(
                Int(bitPattern: UInt(bits)),
                width: 8,
                signed: false,
                into: data,
                atOffset: offset,
                byteOrder: byteOrder
            )
        case .lossless_float:
            // Encoded as a JSON string of `Float.description`. Round-
            // trips bit-pattern-stable for normals AND denormals.
            guard let s = value as? String, let f = Float(s) else {
                throw decodingError("expected string-encoded Float for '\(propertyName)' (lossless_float)", offset)
            }
            try writeInteger(
                Int(f.bitPattern),
                width: 4,
                signed: false,
                into: data,
                atOffset: offset,
                byteOrder: byteOrder
            )
        case .lossless_double:
            guard let s = value as? String, let d = Double(s) else {
                throw decodingError("expected string-encoded Double for '\(propertyName)' (lossless_double)", offset)
            }
            try writeInteger(
                Int(bitPattern: UInt(d.bitPattern)),
                width: 8,
                signed: false,
                into: data,
                atOffset: offset,
                byteOrder: byteOrder
            )
        case .boolean:
            guard let b = coerceToBool(value) else {
                throw decodingError("expected bool for '\(propertyName)'", offset)
            }
            data.write(GoDData(byteStream: [b ? UInt8(1) : UInt8(0)], byteOrder: byteOrder), atAddress: offset)
        case .character(let format):
            guard let string = value as? String else {
                throw decodingError("expected String for '\(propertyName)' (char)", offset)
            }
            try writeString(string, format: format, count: count, into: data, atOffset: offset, byteOrder: byteOrder)
        }
    }

    /// Reads a `width`-byte integer from `data` (starting at offset 0),
    /// interpreting the bytes in `byteOrder` and sign-extending from the
    /// field's top bit when `signed`. Handles widths 1...8 uniformly, so
    /// it is correct for 24-bit fields and for little-endian layouts —
    /// unlike the old per-width paths, which assumed big-endian byte order
    /// and zero-extended 24-bit values (so negative int24 read as large
    /// positives). Returns nil if `data` is shorter than `width`.
    static func readInteger(
        from data: GoDData,
        width: Int,
        signed: Bool,
        byteOrder: ByteOrder
    ) -> Int? {
        let raw = data.rawBytes
        guard width >= 1, width <= 8, raw.count >= width else { return nil }
        var value: UInt64 = 0
        for i in 0..<width {
            // Accumulate most-significant byte first, resolved per byte order.
            let byte = (byteOrder == .big) ? raw[i] : raw[width - 1 - i]
            value = (value << 8) | UInt64(byte)
        }
        if signed, width < 8 {
            let signBit: UInt64 = 1 << (width * 8 - 1)
            if value & signBit != 0 {
                value |= ~UInt64(0) << (width * 8)   // sign-extend to 64 bits
            }
        }
        return Int(bitPattern: UInt(value))
    }

    /// Internal so the CSV codec can write a float's raw bit pattern when a
    /// cell carries one (`0x7FA00000`) — a NaN payload doesn't survive being
    /// parsed as a number, so those bits are written as an integer instead.
    internal static func writeInteger(
        _ value: Int,
        width: Int,
        signed: Bool,
        into data: GoDData,
        atOffset offset: Int,
        byteOrder: ByteOrder
    ) throws {
        // Use 64-bit two's-complement representation, then truncate
        // to `width` bytes in big- or little-endian order. This
        // handles all signed/unsigned widths uniformly without
        // worrying about Swift's narrower-width int literals.
        let unsigned = UInt64(bitPattern: Int64(value))
        var bytes = [UInt8](repeating: 0, count: width)
        for i in 0..<width {
            let shift = (byteOrder == .big) ? (width - 1 - i) * 8 : i * 8
            bytes[i] = UInt8((unsigned >> shift) & 0xFF)
        }
        data.write(GoDData(byteStream: bytes, byteOrder: byteOrder), atAddress: offset)
        _ = signed   // silence unused warning; sign is implicit in the bit pattern above
    }

    private static func writeString(
        _ string: String,
        format: StringFormats,
        count: Int,
        into data: GoDData,
        atOffset offset: Int,
        byteOrder: ByteOrder
    ) throws {
        // Encode the string in the format's encoding, truncate or
        // zero-pad to exactly `count` characters' worth of bytes.
        let stride = format.characterLength
        let totalBytes = count * stride
        let encoded = string.data(format: format)
        var raw = encoded.rawBytes
        // Foundation prepends a UTF-16 BOM that on-card data never
        // has. Strip it for any format that lands on a UTF-16-shaped
        // encoding (gs* + utf16/unicode).
        switch format {
        case .gs, .gsColo, .gsXD, .gsPBR, .utf16_big, .unicode_big:
            if raw.count >= 2, raw[0] == 0xFE, raw[1] == 0xFF {
                raw.removeFirst(2)
            }
        case .utf16_little, .unicode_little:
            if raw.count >= 2, raw[0] == 0xFF, raw[1] == 0xFE {
                raw.removeFirst(2)
            }
        default:
            break
        }
        var out = [UInt8](repeating: 0, count: totalBytes)
        let copy = Swift.min(raw.count, totalBytes)
        for i in 0..<copy { out[i] = raw[i] }
        data.write(GoDData(byteStream: out, byteOrder: byteOrder), atAddress: offset)
    }

    // MARK: - Coercions

    private static func coerceToInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private static func coerceToDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func coerceToBool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    private static func decodingError(_ message: String, _ offset: Int) -> DecodingError {
        DecodingError.dataCorrupted(.init(
            codingPath: [],
            debugDescription: "StructData decode @+\(String(format: "0x%X", offset)): \(message)"
        ))
    }
}

// MARK: - LosslessFloat / LosslessDouble
//
// Wrappers used by the `.lossless_float` / `.lossless_double`
// primitive types to encode / decode floats as JSON *strings*. The
// motivating case is denormal Float32 values (subnormal exponents,
// e.g. `Float(bitPattern: 0x00000010)` ≈ 1.4e-44) that lose bits
// when JSONEncoder serializes them through its number-format path.
// Swift's `Float.description` / `Double.description` produce the
// shortest decimal that round-trips back to the same bit pattern,
// so wrapping the value in a string-only Codable shape gives a
// bit-stable round-trip without changing the JSON shape for
// non-lossless-flagged float fields.

public struct LosslessFloat: Codable, Equatable {
    public let value: Float
    public init(_ value: Float) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)
        guard let parsed = Float(s) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "LosslessFloat: '\(s)' is not a valid Float"
            ))
        }
        self.value = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(describing: value))
    }
}

public struct LosslessDouble: Codable, Equatable {
    public let value: Double
    public init(_ value: Double) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)
        guard let parsed = Double(s) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "LosslessDouble: '\(s)' is not a valid Double"
            ))
        }
        self.value = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(describing: value))
    }
}

// `JSONAny` — escape hatch for the `init(from: Decoder)` path. The
// vanilla `Decoder` API can't walk arbitrary JSON without a schema,
// so we round-trip through `JSONSerialization` to get back a usable
// `[String: Any]` tree. This wrapper exists to thread that
// round-trip through Swift's strongly-typed Codable system.
private struct JSONAny: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CustomCodingKeys.self) {
            var dict: [String: Any] = [:]
            for key in container.allKeys {
                dict[key.stringValue] = try container.decode(JSONAny.self, forKey: key).value
            }
            self.value = dict
        } else if var container = try? decoder.unkeyedContainer() {
            var arr: [Any] = []
            while !container.isAtEnd {
                arr.append(try container.decode(JSONAny.self).value)
            }
            self.value = arr
        } else {
            let single = try decoder.singleValueContainer()
            if let b = try? single.decode(Bool.self) { self.value = b; return }
            if let i = try? single.decode(Int.self) { self.value = i; return }
            if let d = try? single.decode(Double.self) { self.value = d; return }
            if let s = try? single.decode(String.self) { self.value = s; return }
            if single.decodeNil() { self.value = NSNull(); return }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported JSON value"
            ))
        }
    }
}
