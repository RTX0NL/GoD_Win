//
//  File.swift
//  
//
//  Created by Stars Momodu on 07/03/2025.
//

import Foundation

public protocol GoDError: Error, CustomStringConvertible {}

public struct ErrorTrace: CustomStringConvertible {
    public let fileName: String
    public let functionName: String
    public let lineNumer: Int
    
    public init(
        fileName: String = #file,
        functionName: String = #function,
        lineNumer: Int = #line
    ) {
        self.fileName = fileName
        self.functionName = functionName
        self.lineNumer = lineNumer
    }
    
    public var description: String {
        "in \(functionName) of \(fileName) at line #\(lineNumer)"
    }
}
