//
//  ValidatedSet.swift
//  
//
//  Created by Stars Momodu on 10/02/2025.
//

import Foundation

public enum ValidatedSetError: GoDError {
    case missingElements(String, [String], ErrorTrace)
    
    public var description: String {
        switch self {
        case let .missingElements(setName, elements, errorTrace):
            return "Error: Couldn't create set: \(setName)\nMissing elements: \(elements.joined(separator: ", "))\n\(errorTrace)"
        }
    }
}

public protocol Nameable {
    var name: String { get }
}

public protocol ValidatedSet {
    associatedtype Item: Nameable
    static var allItems: [Item] { get }
    init(unchecked items: [Item])
}

public extension ValidatedSet {
    init() {
        self.init(unchecked: Self.allItems)
    }
    
    init(validated items: [Item]) throws {
        let expectedNames = Self.allItems.map(\.name)
        let itemNames = items.map(\.name)
        let missingNames = expectedNames.filter { name in
            !itemNames.contains(where: { $0 == name })
        }
        guard missingNames.isEmpty else {
            throw ValidatedSetError.missingElements(String(reflecting: Self.self), missingNames, .init())
        }
        self.init(unchecked: items)
    }
}
