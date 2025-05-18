//
//  File.swift
//  
//
//  Created by Stars Momodu on 09/06/2024.
//

import Foundation

public enum FSTErrors: GoDError {
    case fileNotFound(File, ErrorTrace)
    case folderNotFound(Folder, ErrorTrace)
    case failedToWriteFile(File, ErrorTrace)
    
    public var description: String {
        switch self {
        case let .fileNotFound(file, errorTrace):
            return "Error: file not found: \(file)\n\(errorTrace)"
        case let .folderNotFound(folder, errorTrace):
            return "Error: folder not found: \(folder)\n\(errorTrace)"
        case let .failedToWriteFile(file, errorTrace):
            return "Error: failed to write file: \(file)\n\(errorTrace)\nPlease check free space and write permissions"
        }
    }
}
