//
//  File.swift
//  
//
//  Created by Stars Momodu on 10/02/2025.
//

import GoDFoundation
import GoDEngine
import Structs

public extension GamecubeEngine {
    struct Enums: EngineEnums {
        public private(set) var entries: [Enum] = Enums.allItems
        
        public init(unchecked items: [Enum]) {
            self.entries = items
        }
        
        static public var allItems: [Enum] {
            [
            ]
        }
    }
}
