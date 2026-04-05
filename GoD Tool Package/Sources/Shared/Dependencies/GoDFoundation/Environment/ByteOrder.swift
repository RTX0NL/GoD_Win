//
//  ByteOrder.swift
//  
//
//  Created by Stars Momodu on 12/06/2022.
//

import Foundation

public enum ByteOrder: String, Equatable, Codable {
    case big
    case little

    public var swapped: ByteOrder {
        switch self {
        case .big: return .little
        case .little: return .big
        }
    }
}
