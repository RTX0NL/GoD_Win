//
//  JSON.swift
//  
//
//  Created by Stars Momodu on 09/06/2024.
//

import Foundation

public extension JSONDecoder {
    /// Decodes from anything readable.
    ///
    /// JSON has to be complete before it can be parsed, so this is one of the
    /// few places where wanting the whole buffer isn't a compromise. A source
    /// that won't produce one can't be decoded at all, which is a decoding
    /// failure rather than something to paper over.
    func decode<T>(_ type: T.Type, from data: GoDReadable) throws -> T where T : Decodable {
        guard let buffer = data.allData else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "source of \(data.length) bytes cannot provide a whole buffer to decode"
            ))
        }
        return try decode(type, from: buffer.data)
    }
}

public extension JSONEncoder {
    func encode<Value>(_ value: Value) throws -> GoDData where Value : Encodable {
        let data: Data = try encode(value)
        return GoDData(data: data, byteOrder: Environment.byteOrder)
    }
}


public enum JSONDecodingError: Error {
    case invalidToken(String, Any.Type)
    
    var description: String {
        switch self {
        case .invalidToken(let token, let type):
            return "Error: Couldn't decode token '\(token)' as type '\(type.self)'"
        }
    }
}
