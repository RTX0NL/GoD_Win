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
    
    /// Case names that aren't usable (see `isValidCaseName`). Non-empty means
    /// the enum can't be serialized unambiguously.
    public var invalidCaseNames: [String] {
        values.map(\.name).filter { !Self.isValidCaseName($0) }.sorted()
    }

    /// Whether `name` is usable as a case name.
    ///
    /// A case name must start with a letter or `_` and contain no whitespace.
    /// That's deliberately looser than `StructDefinition.isValidPropertyName`:
    /// a property name is a JSON key and a `@dynamicMemberLookup` member, so it
    /// has to be an identifier, whereas a case name is only ever a *value*.
    /// Punctuation is therefore fine, and real enums depend on it —
    /// `FsysGroupIDs` names its cases after archive filenames (`B1_1.fsys`).
    ///
    /// The two restrictions each close a concrete ambiguity:
    ///   * a leading digit or sign would make the name indistinguishable from
    ///     the raw value it stands for, wherever a serialized field accepts
    ///     either form — which is everywhere, since an unnamed value falls
    ///     back to its integer;
    ///   * whitespace would break `Case`'s `"<name> = <rawValue>"` codec,
    ///     which splits on `" = "`.
    public static func isValidCaseName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else { return false }
        guard first == "_" || CharacterSet.letters.contains(first) else { return false }
        return !name.unicodeScalars.contains(where: {
            CharacterSet.whitespacesAndNewlines.contains($0)
        })
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
