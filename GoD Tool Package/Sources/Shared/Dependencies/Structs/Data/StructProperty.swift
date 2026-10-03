//
//  CProperty.swift
//  
//
//  Created by Stars Momodu on 12/06/2022.
//

import Foundation
import GoDFoundation

public enum IntegerProperties: String, Codable, Equatable, CaseIterable {
    case uint8, int8
    case uint16, int16
    case uint24, int24
    case uint32, int32
    case uint64, int64
    
    public var length: Int {
        switch self {
        case .uint8, .int8:
            return 1
        case .uint16, .int16:
            return 2
        case .uint24, .int24:
            return 3
        case .uint32, .int32:
            return 4
        case .uint64, .int64:
            return 8
        }
    }

    /// Whether the type is a signed (two's-complement) integer.
    /// Drives sign-extension when reading and is byte-order agnostic.
    public var isSigned: Bool {
        switch self {
        case .int8, .int16, .int24, .int32, .int64:
            return true
        case .uint8, .uint16, .uint24, .uint32, .uint64:
            return false
        }
    }
}

public enum StructPrimitives: Equatable, Codable {
    case void
    case integer(IntegerProperties)
    case float, double
    /// Like `.float`, but encoded to JSON as a *string* via the
    /// Swift Float printer's lossless decimal form. Use this for
    /// fields where bit-pattern preservation matters across the
    /// JSON edit cycle — e.g. denormal Float32 values that would
    /// lose precision through JSONEncoder's number-to-string
    /// formatting otherwise. On disk it's still 4 bytes BE / LE
    /// per the surrounding `GoDData.byteOrder`.
    case lossless_float
    /// Same as `.lossless_float`, but for Float64 (`.double`).
    case lossless_double
    case boolean, character(StringFormats)

    public var length: Int {
        switch self {
        case .void:
            return 0
        case .integer(let type):
            return type.length
        case .float, .lossless_float:
            return 4
        case .double, .lossless_double:
            return 8
        case .boolean:
            return 1
        case .character(let format):
            switch format {
            case .utf8:
                return 1
            case .utf16_big, .utf16_little, .ascii_big, .ascii_little, .unicode_big, .unicode_little,
                 .gsColo, .gsXD, .gsPBR, .gs:
                return 2
            }
        }
    }
}

public indirect enum StructProperty: Equatable {
    case primitive(StructPrimitives)
    case array(StructProperty, count: Int)
    case subStruct(StructDefinition)
    case enumeration(Enum)
    case label
    case padding(length: Int)
    /// An integer split into named bit ranges. It occupies its storage
    /// type's bytes, so every offset walk treats it as that integer; the
    /// named ranges inside are addressed as `<property>.<field>`.
    case bits(BitFieldLayout)

    public static func string(format: StringFormats, length: Int) -> StructProperty {
        return .array(.primitive(.character(format)), count: length)
    }

    public var length: Int {
        switch self {
        case .primitive(let type):
            return type.length
        case .array(let type, let count):
            return type.length * count
        case .subStruct(let definition):
            return definition.length
        case .enumeration(let definition):
            return definition.propertyType.length
        case .label:
            return 4
        case .padding(let length):
            return length
        case .bits(let layout):
            return layout.storage.length
        }
    }

    var alignment: Int {
        switch self {
        case .primitive(.integer(.uint24)), .primitive(.integer(.int24)):
            return 1
        case .primitive(let prim):
            return max(prim.length, 1)
        case .array(let property, let count):
            return count > 0 ? property.alignment : 1
        case .subStruct(let definition):
            return definition.longestAlignment
        case .enumeration(let definition):
            return StructProperty.primitive(.integer(definition.propertyType)).alignment
        case .label:
            return 4
        case .padding:
            return 1
        case .bits(let layout):
            return StructProperty.primitive(.integer(layout.storage)).alignment
        }
    }
}

public extension StructProperty {
    static var void: StructProperty { .primitive(.void)}
    static var boolean: StructProperty { .primitive(.boolean)}
    static var uint8: StructProperty { .primitive(.integer(.uint8))}
    static var int8: StructProperty { .primitive(.integer(.int8))}
    static var uint16: StructProperty { .primitive(.integer(.uint16))}
    static var int24: StructProperty { .primitive(.integer(.int24))}
    static var uint24: StructProperty { .primitive(.integer(.uint24))}
    static var int16: StructProperty { .primitive(.integer(.int16))}
    static var uint32: StructProperty { .primitive(.integer(.uint32))}
    static var int32: StructProperty { .primitive(.integer(.int32))}
    static var uint64: StructProperty { .primitive(.integer(.uint64))}
    static var int64: StructProperty { .primitive(.integer(.int64))}
    static var float: StructProperty { .primitive(.float)}
    static var double: StructProperty { .primitive(.double)}
    static var losslessFloat: StructProperty { .primitive(.lossless_float)}
    static var losslessDouble: StructProperty { .primitive(.lossless_double)}
    static var labelPointer: StructProperty { .label }
}

extension IntegerProperties: CustomStringConvertible {
    public var description: String {
        switch self {
        case .uint8: return "uint8"
        case .int8: return "int8"
        case .uint16: return "uint16"
        case .int16: return "int16"
        case .uint24: return "uint24"
        case .int24: return "int24"
        case .uint32: return "uint32"
        case .int32: return "int32"
        case .uint64: return "uint64"
        case .int64: return "int64"
        }
    }
    
    public static func from(name: String) -> IntegerProperties? {
        switch name {
        case "uint8": return .uint8
        case "int8": return .int8
        case "uint16": return .uint16
        case "int16": return .int16
        case "uint24": return .uint24
        case "int24": return .int24
        case "uint32": return .uint32
        case "int32": return .int32
        case "uint64": return .uint64
        case "int64": return .int64
        default: return nil
        }
    }
}

extension StructPrimitives: CustomStringConvertible {
    public var description: String {
        switch self {
        case .void: return "void"
        case .integer(let type): return type.description
        case .float: return "float"
        case .double: return "double"
        case .lossless_float: return "lossless_float"
        case .lossless_double: return "lossless_double"
        case .boolean: return "boolean"
        case .character(let format):
            switch format {
            case .utf8: return "char_utf8"
            case .utf16_big: return "char_utf16_big"
            case .ascii_big: return "char_ascii_big"
            case .unicode_big: return "char_unicode_big"
            case .utf16_little: return "char_utf16_little"
            case .ascii_little: return "char_ascii_little"
            case .unicode_little: return "char_unicode_little"
            case .gsColo: return "char_gsColo"
            case .gsXD: return "char_gsXD"
            case .gsPBR: return "char_gsPBR"
            case .gs: return "char_gs"
            }
        }
    }
    
    public static func from(name: String) -> StructPrimitives? {
        if let integer = IntegerProperties.from(name: name) {
            return .integer(integer)
        }
        switch name {
        case "void": return .void
        case "char": return .integer(.uint8)
        case "float": return .float
        case "double": return .double
        case "lossless_float": return .lossless_float
        case "lossless_double": return .lossless_double
        case "boolean": return .boolean
        case "char_utf8": return .character(.utf8)
        case "char_utf16_big": return .character(.utf16_big)
        case "char_ascii_big": return .character(.ascii_big)
        case "char_unicode_big": return .character(.unicode_big)
        case "char_utf16_little": return .character(.utf16_little)
        case "char_ascii_little": return .character(.ascii_little)
        case "char_unicode_little": return .character(.unicode_little)
        case "char_gsColo": return .character(.gsColo)
        case "char_gsXD": return .character(.gsXD)
        case "char_gsPBR": return .character(.gsPBR)
        case "char_gs": return .character(.gs)
        default: return nil
        }
    }
}

extension StructProperty: CustomStringConvertible {
    public var description: String {
        switch self {
        case .primitive(let type): return type.description
        case .array(let type, let count): return "\(type.description)[\(count)]"
        case .subStruct(let defintion): return "struct " + defintion.name
        case .enumeration(let definition): return "enum " + definition.name
        case .label: return "label"
        case .padding(let length): return "void[\(length)]"
        case .bits(let layout): return layout.description
        }
    }
}
