//
//  StructMap.swift
//  
//
//  Created by Stars Momodu on 21/06/2024.
//

import GoDFoundation

public final class StructMap: Nameable {
    
    public struct Property: Equatable {
        public let name: String
        public let description: String?
        public let type: StructField

        public init(name: String, type: StructField, description: String? = nil) {
            self.name = name.replacingOccurrences(of: " ", with: "")
            self.description = description
            self.type = type
        }
    }

    public let name: String
    public let wordSize: Int
    public let alignmentStyle: StructAlignmentStyles
    public let properties: [Property]
    public let description: String?

    public init(
        name: String,
        wordSize: Int,
        alignmentStyle: StructAlignmentStyles,
        properties: [Property],
        description: String? = nil
    ) {
        self.name = name
        self.wordSize = wordSize
        self.alignmentStyle = alignmentStyle
        self.properties = properties
        self.description = description
    }
}

extension StructMap: Encodable {
    public enum CodingKeys: String, CodingKey {
        case name, description, properties, alignmentStyle, wordSize
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(wordSize, forKey: .wordSize)
        try container.encode(alignmentStyle, forKey: .alignmentStyle)
        
        // Names round-trip verbatim. `snakeCased` used to lowercase them
        // here, so `fileDataPointer` came back as `filedatapointer` — which
        // only worked because lookup folded case away. Lookup is exact now,
        // so a serialized engine must reload with the names it was given.
        //
        // Everything but a bit container is one terse `"<type> <name>"`
        // string. A bit container is an object: its layout is a list, and
        // it is the one form that carries a description per field.
        try container.encode(properties.map(PropertyEntry.init), forKey: .properties)
    }
}

extension StructMap: Decodable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let description = try container.decode(String?.self, forKey: .description)
        let wordSize = try container.decode(Int.self, forKey: .wordSize)
        let alignmentStyle = try container.decode(StructAlignmentStyles.self, forKey: .alignmentStyle)
        let propertyList = try container.decode([PropertyEntry].self, forKey: .properties)

        let properties: [StructMap.Property] = try propertyList.map { entry in
            switch entry {
            case .bitField(let object):
                let map = try object.decodedMap()
                let type: StructField = object.count.map { .array(.bits(map), count: $0) } ?? .bits(map)
                return .init(name: object.name, type: type, description: object.description)
            case .text(let text):
                return try Self.decodeTextProperty(text)
            }
        }
        self.init(
            name: name,
            wordSize: wordSize,
            alignmentStyle: alignmentStyle,
            properties: properties,
            description: description
        )
    }

    /// One `"<type> <name>"` entry.
    private static func decodeTextProperty(_ text: String) throws -> StructMap.Property {
        func getType(_ token: String) throws -> StructField {
            if token == "label" {
                return .label
            } else if let primitive = StructPrimitives.from(name: token) {
                return .primitive(primitive)
            } else if token.startsWith("void["),
                   let count = token.substring(from: 5, to: -1).integerValue {
                return .padding(length: count)
            } else if token.last == "]",
                  let lastOpenIndex = token.lastIndex(of: "["),
                  let lastCloseIndex = token.lastIndex(of: "]") {

                let countString = token.substring(from: lastOpenIndex, to: lastCloseIndex).substring(from: 1)
                if let count = countString.integerValue {
                    let prefix = String(token.prefix(upTo: lastOpenIndex))
                    return .array(try getType(prefix), count: count)
                }
            } else if token.startsWith("enum ") {
                let suffix = token.substring(from: 5)
                return .enumeration(name: suffix)
            } else if token.startsWith("struct ") {
                let suffix = token.substring(from: 7)
                return .subStruct(name: suffix)
            }
            throw JSONDecodingError.invalidToken(token, StructField.self)
        }
        guard let lastSpace = text.lastIndex(of: " ") else {
            throw JSONDecodingError.invalidToken(text, StructMap.Property.self)
        }
        let typeToken = String(text.prefix(upTo: lastSpace))
        let nameToken =  String(text.suffix(from: lastSpace)).substring(from: 1)
        let type = try getType(typeToken)
        return .init(name: nameToken, type: type)
    }
}

/// A `properties` entry: a type string, or a bit container's object.
enum PropertyEntry: Codable {
    case text(String)
    case bitField(BitFieldPropertyJSON)

    init(_ property: StructMap.Property) {
        func bitField(_ map: BitFieldMap, count: Int?) -> PropertyEntry {
            .bitField(.init(
                name: property.name,
                description: property.description,
                map: map,
                count: count
            ))
        }
        switch property.type {
        case .bits(let map):
            self = bitField(map, count: nil)
        case .array(.bits(let map), let count):
            self = bitField(map, count: count)
        default:
            self = .text("\(property.type) \(property.name)")
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = .bitField(try container.decode(BitFieldPropertyJSON.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .bitField(let object): try container.encode(object)
        }
    }
}

public extension StructMap.Property {

    static func uint8(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .uint8, description: description)
    }

    static func int8(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .int8, description: description)
    }


    static func uint16(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .uint16, description: description)
    }

    static func int16(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .int16, description: description)
    }
    
    
    static func uint24(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .uint24, description: description)
    }

    static func int24(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .int24, description: description)
    }


    static func uint32(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .uint32, description: description)
    }

    static func int32(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .int32, description: description)
    }


    static func uint64(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .uint64, description: description)
    }

    static func int64(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .int64, description: description)
    }


    static func float(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .float, description: description)
    }

    static func double(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .double, description: description)
    }

    /// `lossless_float` — JSON-encoded as a string for bit-pattern-
    /// stable round-trip across float ↔ JSON ↔ float. See
    /// `StructPrimitives.lossless_float` for rationale (denormals,
    /// JSON-number-precision).
    static func losslessFloat(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .primitive(.lossless_float), description: description)
    }

    static func losslessDouble(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .primitive(.lossless_double), description: description)
    }
    
    
    static func boolean(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .boolean, description: description)
    }


    static func character(name: String, format: StringFormats, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .primitive(.character(format)), description: description)
    }
    
    static func string(name: String, format: StringFormats, length: Int, description: String? = nil) -> StructMap.Property {
        array(name: name, count: length, of: .primitive(.character(format)))
    }

    static func array(name: String, count: Int, of subProperty: StructField, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .array(subProperty, count: count), description: description)
    }

    static func subStruct(name: String, typeName: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .subStruct(name: typeName), description: description)
    }

    static func abstraction(name: String, typeName: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .enumeration(name: typeName), description: description)
    }
    
    static func label(name: String, description: String? = nil) -> StructMap.Property {
        StructMap.Property(name: name, type: .label, description: description)
    }

    static func padding(length: Int) -> StructMap.Property {
        StructMap.Property(name: "padding", type: .array(.uint8, count: length))
    }

    /// An integer split into named bit ranges. Bit 0 is the **most**
    /// significant bit of `storage`, and the ranges must tile it exactly,
    /// most significant first — a run nothing reads is still a value, so
    /// it is named rather than left out.
    static func bits(
        name: String,
        storage: IntegerProperties = .uint8,
        description: String? = nil,
        fields: [BitFieldMap.Field]
    ) -> StructMap.Property {
        StructMap.Property(
            name: name,
            type: .bits(BitFieldMap(storage: storage, fields: fields)),
            description: description
        )
    }

    /// An array of bit containers, all sharing one layout.
    static func bitsArray(
        name: String,
        count: Int,
        storage: IntegerProperties = .uint8,
        description: String? = nil,
        fields: [BitFieldMap.Field]
    ) -> StructMap.Property {
        StructMap.Property(
            name: name,
            type: .array(.bits(BitFieldMap(storage: storage, fields: fields)), count: count),
            description: description
        )
    }
}
