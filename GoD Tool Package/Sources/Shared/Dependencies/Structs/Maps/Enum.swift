//
//  EnumDefinition.swift
//  
//
//  Created by Stars Momodu on 09/08/2022.
//

import Foundation
import GoDFoundation

@dynamicMemberLookup
public struct Enum: Codable, Equatable, Nameable {
    public enum Errors: Error, CustomStringConvertible {
        case InvalidEnumIndex(index: Int, enumeration: Enum, ErrorTrace)
        case InvalidEnumCase(caseName: String, enumeration: Enum, ErrorTrace)
        case InvalidEnumCaseDefinition(input: String, ErrorTrace)
        
        public var description: String {
            switch self {
            case .InvalidEnumIndex(let index, let enumeration, let errorTrace):
                return "Invalid index '\(index)' in enum '\(enumeration.name)'\n\(errorTrace)"
            case .InvalidEnumCase(let caseName, let enumeration, let errorTrace):
                return "Invalid case '\(caseName)' in enum '\(enumeration.name)'\n\(errorTrace)"
            case .InvalidEnumCaseDefinition(let input, let errorTrace):
                return "Couldn't decode enum case: '\(input)'\nExpected format: \"case_name = raw_value\" e.g. \"Monday = 1\"\n\(errorTrace)"
            }
        }
    }
    
    public struct Case: Codable, Equatable {
        public let name: String
        public let rawValue: Int
        
        public init(
            name: String,
            rawValue: Int
        ) {
            self.name = name
            self.rawValue = rawValue
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode("\(name) = \(rawValue)")
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let parts = string.split(separator: " = ").map(String.init)
            guard parts.count == 2, let rawValue = parts[1].integerValue else {
                throw Errors.InvalidEnumCaseDefinition(input: string, .init())
            }
            self.name = parts[0]
            self.rawValue = rawValue
        }
    }

    public let name: String
    public let allowUnknownCases: Bool
    public let values: [Case]
    public let propertyType: IntegerProperties
    
    public init(
        name: String,
        allowUnknownCases: Bool,
        values: [Case],
        propertyType: IntegerProperties
    ) {
        self.name = name
        self.allowUnknownCases = allowUnknownCases
        self.values = values
        self.propertyType = propertyType
    }

    public subscript(dynamicMember caseName: String) -> Case {
        get throws {
            try get(caseName)
        }
    }

    public subscript(index: Int) -> Case {
        get throws {
            try get(index)
        }
    }
    
    public func get(_ caseName: String) throws -> Case {
        if let value = values.first(where: { $0.name.lowercased() == caseName.lowercased() }) {
            return value
        }
        // `allowUnknownCases` enums render unnamed raw values as
        // `<Enum_Name>_<raw>` (see `unknown(_:)`). Parse that shape back so a
        // synthesized name survives a name → raw → name round trip; without
        // it, anything the enum doesn't name could be read but never written.
        if allowUnknownCases,
           caseName.hasPrefix(unknownCasePrefix),
           let raw = Int(caseName.dropFirst(unknownCasePrefix.count)) {
            return unknown(raw)
        }
        throw Errors.InvalidEnumCase(caseName: caseName, enumeration: self, .init())
    }

    public func get(_ index: Int) throws -> Case {
        guard let value = values.first(where: { $0.rawValue == index }) else {
            guard allowUnknownCases else {
                throw Errors.InvalidEnumIndex(index: index, enumeration: self, .init())
            }
            return unknown(index)
        }
        return value
    }
    
    /// Prefix of the synthesized name given to a raw value the enum doesn't
    /// name, e.g. `FileTypes_22` for raw 22 of `FileTypes`.
    public var unknownCasePrefix: String {
        name.replacingOccurrences(of: " ", with: "_") + "_"
    }

    private func unknown(_ index: Int) -> Case {
        .init(name: "\(unknownCasePrefix)\(index)", rawValue: index)
    }
}
