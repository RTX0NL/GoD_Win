//
//  Error.swift
//  
//
//  Created by Stars Momodu on 05/06/2024.
//

import GoDFoundation

public enum StructError: GoDError {
    case MissingKey(key: String, struct: StructData, ErrorTrace)
    case TypeMismatch(key: String, propertyType:StructProperty, type: Any.Type, struct: StructData, ErrorTrace)
    
    public var description: String {
        switch self {
        case let .MissingKey(key, structData, errorTrace):
            let keys = structData.properties.map(\.name).joined(separator: "\n")
            return "Error: Couldn't find key '\(key)' in struct '\(structData.name)'\nKeys:\n" + keys + "\n\(errorTrace)"
        case let .TypeMismatch(key, propertyType, type, structData, errorTrace):
            return "Error: Couldn't convert key '\(key)' of type '\(propertyType)' to type: `\(type)` in struct '\(structData.name)'" + "\n\(errorTrace)"
        }
    }
}
