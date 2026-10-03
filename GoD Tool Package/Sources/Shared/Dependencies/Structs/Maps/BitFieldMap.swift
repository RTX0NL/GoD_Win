//
//  BitFieldMap.swift
//
//  A bit-field declaration as it is written in an engine folder: the same
//  shape as `BitFieldLayout`, but with enum references still unresolved —
//  exactly the relationship `StructField` has to `StructProperty`.
//
//  Declared as a JSON *object* rather than one of `StructMap.properties`'
//  terse `"<type> <name>"` strings, because a bit layout is a list and a
//  list doesn't fit a line. It is the one property form that can carry a
//  description per field, which the string form drops.
//

import Foundation
import GoDFoundation

public struct BitFieldMap: Equatable {

    /// The integer the bits live in.
    public let storage: IntegerProperties

    /// Named ranges, ascending (most significant first), tiling `storage`
    /// exactly. Validated where the engine resolves it, against the same
    /// rules `BitFieldLayout.issues` lists.
    public let fields: [Field]

    public init(storage: IntegerProperties, fields: [Field]) {
        self.storage = storage
        self.fields = fields
    }

    public struct Field: Equatable {
        public let name: String
        /// MSB-0 indices, inclusive — bit 0 is the most significant.
        public let bits: ClosedRange<Int>
        public let value: Value
        public let description: String?

        public init(
            name: String,
            bits: ClosedRange<Int>,
            value: Value = .unsigned,
            description: String? = nil
        ) {
            self.name = name
            self.bits = bits
            self.value = value
            self.description = description
        }
    }

    public enum Value: Equatable {
        case unsigned
        case signed
        case boolean
        case enumeration(name: String)

        /// The `"type"` spelling, or nil for an enum reference (which is
        /// written under `"enum"` instead).
        var typeName: String? {
            switch self {
            case .unsigned: return "unsigned"
            case .signed: return "signed"
            case .boolean: return "boolean"
            case .enumeration: return nil
            }
        }

        static func named(_ name: String) -> Value? {
            switch name {
            case "unsigned": return .unsigned
            case "signed": return .signed
            case "boolean", "bool": return .boolean
            default: return nil
            }
        }
    }
}

extension BitFieldMap: CustomStringConvertible {
    public var description: String {
        "bits(\(storage.description))"
    }
}

// MARK: - The serialized object

/// One `StructMap.properties` entry in its object form. Carries the
/// property-level name and description alongside the layout, so a bit
/// container is declared in one place.
struct BitFieldPropertyJSON: Codable {

    let name: String
    let description: String?
    let storage: String
    /// Present when the property is an *array* of containers.
    let count: Int?
    let bits: [FieldJSON]

    struct FieldJSON: Codable {
        let name: String
        let range: String
        let type: String?
        let `enum`: String?
        let description: String?
    }

    init(name: String, description: String?, map: BitFieldMap, count: Int?) {
        self.name = name
        self.description = description
        self.storage = map.storage.description
        self.count = count
        self.bits = map.fields.map { field in
            FieldJSON(
                name: field.name,
                range: BitFieldLayout.text(for: field.bits),
                type: field.value.typeName == "unsigned" ? nil : field.value.typeName,
                enum: {
                    if case .enumeration(let enumName) = field.value { return enumName }
                    return nil
                }(),
                description: field.description
            )
        }
    }

    /// The declared layout, or a decoding error naming the token at fault.
    func decodedMap() throws -> BitFieldMap {
        guard let storageType = IntegerProperties.from(name: storage) else {
            throw JSONDecodingError.invalidToken(storage, IntegerProperties.self)
        }
        let fields: [BitFieldMap.Field] = try bits.map { field in
            guard let range = BitFieldLayout.range(from: field.range) else {
                throw JSONDecodingError.invalidToken(field.range, ClosedRange<Int>.self)
            }
            let value: BitFieldMap.Value
            switch (field.type, field.enum) {
            case (let typeName?, nil):
                guard let parsed = BitFieldMap.Value.named(typeName) else {
                    throw JSONDecodingError.invalidToken(typeName, BitFieldMap.Value.self)
                }
                value = parsed
            case (nil, let enumName?):
                value = .enumeration(name: enumName)
            case (nil, nil):
                value = .unsigned
            case (.some, .some):
                // Both would mean two answers to one question; the enum
                // reference *is* the type.
                throw JSONDecodingError.invalidToken(
                    "\(field.name): both \"type\" and \"enum\"", BitFieldMap.Value.self
                )
            }
            return .init(name: field.name, bits: range, value: value, description: field.description)
        }
        return BitFieldMap(storage: storageType, fields: fields)
    }
}

// MARK: - Declaring one in Swift

public extension BitFieldMap.Field {

    /// An unsigned (or, with `signed`, two's-complement) run of bits.
    static func number(
        name: String,
        bits: ClosedRange<Int>,
        signed: Bool = false,
        description: String? = nil
    ) -> BitFieldMap.Field {
        .init(name: name, bits: bits, value: signed ? .signed : .unsigned, description: description)
    }

    /// One bit, read and written as a boolean.
    static func flag(
        name: String,
        bit: Int,
        description: String? = nil
    ) -> BitFieldMap.Field {
        .init(name: name, bits: bit...bit, value: .boolean, description: description)
    }

    /// A run of bits named by an engine enum. The run's width decides the
    /// field's size, so the enum's own `propertyType` is not consulted —
    /// every case has to fit the run instead.
    static func abstraction(
        name: String,
        bits: ClosedRange<Int>,
        typeName: String,
        description: String? = nil
    ) -> BitFieldMap.Field {
        .init(name: name, bits: bits, value: .enumeration(name: typeName), description: description)
    }
}
