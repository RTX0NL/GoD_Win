//
//  File.swift
//  
//
//  Created by Stars Momodu on 09/06/2024.
//

import GoDFoundation

struct GoddessSettings: Codable {
    var verbose = false
    var wiiCommonKeyFile: File? = nil

    static var `default`: GoddessSettings {
        GoddessSettings()
    }
}
