//
//  ColoXDDumpErrors.swift
//  GoD Tool Package
//
//  Created by Stars Momodu on 31/08/2025.
//

import GoDFoundation

public enum ColoXDDumpErrors: Error, CustomStringConvertible {
    case missingToC(file: File, ErrorTrace)
    
    public var description: String {
        switch self {
        case let .missingToC(file, errorTrace):
            return "Error: Couldn't find toc file at '\(file)'\n\(errorTrace)"
        }
    }
}
