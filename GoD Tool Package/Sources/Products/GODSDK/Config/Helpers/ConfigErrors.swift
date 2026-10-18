//
//  File.swift
//  
//
//  Created by Stars Momodu on 09/06/2024.
//

import GoDFoundation

enum ConfigErrors: GoDError {
    case settingsFileNotFound(File, ErrorTrace)
    case settingsFileUndecodable(File, underlying: Error, ErrorTrace)

    var description: String {
        switch self {
        case let .settingsFileUndecodable(file, underlying, errorTrace):
            return "Error: Couldn't decode settings file at: \(file): \(underlying)\n\(errorTrace)"
        case let .settingsFileNotFound(file, errorTrace):
            return "Error: Couldn't read settings file at: \(file)\n\(errorTrace)"
        }
    }
}
