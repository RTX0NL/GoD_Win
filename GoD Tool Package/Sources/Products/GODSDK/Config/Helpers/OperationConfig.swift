//
//  File.swift
//  
//
//  Created by Stars Momodu on 09/06/2024.
//

import GoDFoundation

protocol ConfigType {
    associatedtype OperationType
    var operation: OperationType { get }
    var enabled: Toggle { get }
}

struct OperationConfig<T: Codable>: Codable, ConfigType {
    typealias OperationType = T
    
    let operation: OperationType
    let enabled: Toggle
}

extension Array where Element: ConfigType {
    var enabledEntries: [Element.OperationType] {
        filter(\.enabled).map(\.operation)
    }
}

