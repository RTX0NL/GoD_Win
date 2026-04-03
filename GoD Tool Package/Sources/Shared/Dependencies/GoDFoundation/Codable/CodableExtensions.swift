//
//  CodableExtensions.swift
//  
//
//  Created by Stars Momodu on 13/06/2022.
//

import Foundation

public extension Encodable {
    func encodeJSON() -> GoDData? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(self)
    }
    
    func encodeJSONString() -> String? {
        return encodeJSON()?.string(format: .utf8)
    }
}

public extension Decodable {
    static func decodeJSON(from data: GoDData) -> Self? {
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    
    static func decodeJSON(from string: String) -> Self? {
        return decodeJSON(from: string.data(format: .utf8))
    }
}

public struct CustomCodingKeys: CodingKey, ExpressibleByStringLiteral {
    public var stringValue: String
    public var intValue: Int?
    
    public init(stringLiteral value: String) {
        stringValue = value
    }
    
    public init(_ stringValue: String) {
        self.stringValue = stringValue
    }
    
    public init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    public init?(intValue: Int) {
        return nil
    }
}
