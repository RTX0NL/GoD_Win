//
//  CStructDefiniton.swift
//  
//
//  Created by Stars Momodu on 12/06/2022.
//

import Foundation
import GoDFoundation

public enum StructAlignmentStyles: String, Equatable, Codable {
    case none
    case cStyle
}

public struct StructDefinition: Equatable, Nameable {

    public struct Property: Equatable {
        public let name: String
        public let description: String?
        public let type: StructProperty

        public init(name: String, type: StructProperty, description: String? = nil) {
            self.name = name
            self.description = description
            self.type = type
        }
    }

    public let name: String
    public let wordSize: Int
    public let alignmentStyle: StructAlignmentStyles
    public let properties: [Property]
    public let description: String?

    public var length: Int {
        var sum: Int = 0
        for property in properties {
            switch alignmentStyle {
            case .none: break
            case .cStyle:
                let alignmentOffset = sum % property.type.alignment
                if alignmentOffset > 0 {
                    sum += property.type.alignment - alignmentOffset
                }
            }

            sum += property.type.length
        }
        switch alignmentStyle {
        case .none: break
        case .cStyle:
            let alignmentOffset = sum % longestAlignment
            if alignmentOffset > 0 {
                sum += longestAlignment - alignmentOffset
            }
        }
        return sum
    }

    public var longestAlignment: Int {
        var longest: Int = 0
        for property in properties {
            switch property.type {
            case .primitive(let prim):
                longest = max(longest, prim.length)
            case .array(let property, _):
                longest = max(longest, property.alignment)
            case .subStruct(let substruct):
                longest = max(longest, substruct.longestAlignment)
            case .enumeration(let definition):
                longest = max(longest, StructProperty.primitive(.integer(definition.propertyType)).alignment)
            case .label:
                longest = max(longest, 4)
            case .padding:
                longest = max(longest, 1)
            }
        }
        return longest
    }

    /// Returns a copy with all `.label` properties replaced by `.uint32`.
    /// Used for reading/writing raw binary data where label fields occupy 4 bytes as pointer addresses.
    public func uint32SubstitutedDefinition() -> StructDefinition {
        func substituteProperty(_ type: StructProperty) -> StructProperty {
            switch type {
            case .label:
                return .uint32
            case .subStruct(let def):
                return .subStruct(def.uint32SubstitutedDefinition())
            case .array(let element, let count):
                return .array(substituteProperty(element), count: count)
            default:
                return type
            }
        }

        return StructDefinition(
            name: name,
            wordSize: wordSize,
            alignmentStyle: alignmentStyle,
            properties: properties.map { prop in
                .init(name: prop.name, type: substituteProperty(prop.type), description: prop.description)
            },
            description: description
        )
    }

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

    /// Index of the property a keypath segment names, or nil if it names none.
    ///
    /// Matching is **exact**. Property names are the schema — they're what
    /// engine JSON declares, what dumped struct JSON keys are, and what
    /// `@dynamicMemberLookup` reads — so `file_data_pointer` is addressed as
    /// `file_data_pointer` and nothing else. An earlier version folded away
    /// underscores, spaces and case, which quietly made `maxHP`, `max_hp` and
    /// `maxhp` the same field and let a write land on the wrong offset.
    private func indexOfProperty(named key: String) -> Int? {
        properties.firstIndex(where: { $0.name == key })
    }

    /// Properties declared more than once. Non-empty means the definition
    /// can't be addressed unambiguously.
    ///
    /// Padding is exempt: `.padding(length:)` names every run `"padding"` by
    /// design, and padding is only ever addressed positionally (the
    /// encoder/decoder index it as `padding_<i>`), never by name.
    public var duplicatePropertyNames: [String] {
        let addressable = properties.map(\.name).filter { $0 != Self.paddingPropertyName }
        return Dictionary(grouping: addressable, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
    }

    /// Property names that aren't valid identifiers. A name must start with a
    /// letter or `_` and contain only letters, digits and `_` — the same
    /// shape Swift's `@dynamicMemberLookup` and JSON keys can both express.
    public var invalidPropertyNames: [String] {
        properties.map(\.name).filter { !Self.isValidPropertyName($0) }.sorted()
    }

    /// Whether `name` is usable as a property name (see `invalidPropertyNames`).
    public static func isValidPropertyName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else { return false }
        guard first == "_" || CharacterSet.letters.contains(first) else { return false }
        return name.unicodeScalars.allSatisfy {
            $0 == "_" || CharacterSet.alphanumerics.contains($0)
        }
    }

    /// The reserved name `.padding(length:)` assigns to every padding run.
    public static let paddingPropertyName = "padding"

    /// A declared property that `keypath`'s first segment probably meant, for
    /// "did you mean" diagnostics. Matching is exact, so a near miss —
    /// `fileDataPointer` for `file_data_pointer` — otherwise just resolves to
    /// nothing with no hint as to why.
    public func closestPropertyName(to keypath: String) -> String? {
        guard let key = keypath.split(separator: ".").first.map(String.init),
              indexOfProperty(named: key) == nil else { return nil }
        func folded(_ s: String) -> String {
            s.replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "").lowercased()
        }
        let target = folded(key)
        return properties.first { folded($0.name) == target }?.name
    }

    public func offset(for keypath: String) -> Int? {
        let keypathParts = keypath.split(separator: ".").map(String.init)
        guard let currentKey = keypathParts.first else { return nil }
        let remainingKeyPath = keypathParts.count == 1 ? nil : keypathParts[1...].joined(separator: ".")

        guard let targetIndex = indexOfProperty(named: currentKey) else { return nil }

        var offset: Int = 0
        for (index, property) in properties.enumerated() {
            switch alignmentStyle {
            case .none: break
            case .cStyle:
                let alignmentOffset = offset % property.type.alignment
                if alignmentOffset > 0 {
                    offset += property.type.alignment - alignmentOffset
                }
            }

            if index == targetIndex {
                if let keypath = remainingKeyPath {
                    guard case .subStruct(let substruct) = property.type,
                          let subOffset = substruct.offset(for: keypath) else {
                        return nil
                    }
                    return offset + subOffset
                }
                return offset
            }
            offset += property.type.length
        }

        return nil
    }

    public func property(for keypath: String) -> StructProperty? {
        let keypathParts = keypath.split(separator: ".").map(String.init)
        guard let currentKey = keypathParts.first,
              let index = indexOfProperty(named: currentKey) else { return nil }
        let remainingKeyPath = keypathParts.count == 1 ? nil : keypathParts[1...].joined(separator: ".")

        let property = properties[index]
        if let keypath = remainingKeyPath {
            guard case .subStruct(let substruct) = property.type else { return nil }
            return substruct.property(for: keypath)
        }
        return property.type
    }

}

public extension StructDefinition.Property {

    static func uint8(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .uint8, description: description)
    }

    static func int8(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .int8, description: description)
    }


    static func uint16(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .uint16, description: description)
    }

    static func int16(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .int16, description: description)
    }
    
    
    static func uint24(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .uint24, description: description)
    }

    static func int24(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .int24, description: description)
    }


    static func uint32(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .uint32, description: description)
    }

    static func int32(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .int32, description: description)
    }


    static func uint64(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .uint64, description: description)
    }

    static func int64(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .int64, description: description)
    }


    static func float(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .float, description: description)
    }

    static func double(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .double, description: description)
    }

    static func losslessFloat(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .losslessFloat, description: description)
    }

    static func losslessDouble(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .losslessDouble, description: description)
    }
    
    
    static func boolean(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .boolean, description: description)
    }


    static func character(name: String, format: StringFormats, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .primitive(.character(format)), description: description)
    }
    
    static func string(name: String, format: StringFormats, length: Int, description: String? = nil) -> StructDefinition.Property {
        array(name: name, count: length, of: .primitive(.character(format)))
    }

    static func array(name: String, count: Int, of subProperty: StructProperty, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .array(subProperty, count: count), description: description)
    }

    static func subStruct(name: String, defintion: StructDefinition, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .subStruct(defintion), description: description)
    }

    static func abstraction(name: String, enumeration: Enum, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .enumeration(enumeration), description: description)
    }
    
    static func label(name: String, description: String? = nil) -> StructDefinition.Property {
        StructDefinition.Property(name: name, type: .label, description: description)
    }

    static func padding(length: Int) -> StructDefinition.Property {
        StructDefinition.Property(name: StructDefinition.paddingPropertyName, type: .array(.uint8, count: length))
    }
}

