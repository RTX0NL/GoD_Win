//
//  File.swift
//  
//
//  Created by Stars Momodu on 14/02/2025.
//

import Foundation

public extension DolphinEngine {
    struct Data: Codable {
        public private(set) var userFiles = UserFiles()
        public private(set) var systemFiles = SystemFiles()
    }
}
