//
//  RunModes.swift
//  
//
//  Created by Stars Momodu on 10/06/2024.
//

import Foundation

enum RunModes {
    case commandLine
    case development(args: [String])
    
    var arguments: [String] {
        switch self {
        case .commandLine:
            return CommandLine.arguments
        case .development(let args):
            return args
        }
    }
}
