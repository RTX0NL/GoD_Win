//
//  File.swift
//  
//
//  Created by Stars Momodu on 31/07/2022.
//

#if canImport(CoreFoundation)
import CoreFoundation
#endif

public struct Environment {

    public static let byteOrder: ByteOrder = {
        #if os(WASI)
        return .little
        #elseif !canImport(CoreFoundation)
        // Swift 6's Foundation on Windows doesn't expose CoreFoundation, so
        // ask the integer representation directly.
        return 1.littleEndian == 1 ? .little : .big
        #else
        switch CFByteOrderGetCurrent() {
        case CFByteOrderBigEndian.rawValue.asInt: return .big
        case CFByteOrderLittleEndian.rawValue.asInt: return .little
        default: fatalError("Unsupported architecture: unknown byte order")
        }
        #endif
    }()

    public static let wordSize: Int = {
        return Int.bitWidth / 8
    }()

    #if os(macOS)
    public static let platform: Platforms = .macOS
    #elseif os(iOS)
    public static let platform: Platforms = .iOS
    #elseif os(Windows)
    public static let platform: Platforms = .Windows
    #elseif os(Linux)
    public static let platform: Platforms = .Linux
    #elseif os(WASI)
    public static let platform: Platforms = .WebAssembly
    #else
    public static let platform: Platforms = .unknown
    #endif
}
