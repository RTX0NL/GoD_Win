//
//  File.swift
//  
//
//  Created by Stars Momodu on 09/06/2024.
//

import GoDFoundation

enum ConfigErrors: GoDError {
    case settingsFileNotFound(File, ErrorTrace)
    
    var description: String {
        switch self {
        case let .settingsFileNotFound(file, errorTrace):
            return "Error: Couldn't read settings file at: \(file)\n\(errorTrace)"
        }
    }
}
