//
//  Apploader.swift
//  
//
//  Created by Stars Momodu on 03/06/2024.
//

import GoDFoundation
import GoDEngine
import Structs

public final class Apploader {
    public static let formatName = "Apploader.img"
    
    private let dolphinEngine: DolphinEngine
    
    public let date: String
    public let entryPoint: UInt32
    public let appCode: GoDData
    public let trailerCode: GoDData
    
    public init(data: GoDData, engine: DolphinEngine) throws {
        self.dolphinEngine = engine
        let apploaderHeaderStruct = dolphinEngine.apploaderHeaderStruct
        guard let apploaderHeader = data.read(struct: apploaderHeaderStruct, atAddress: 0) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        let date: GoDData = try apploaderHeader.date
        let entryPoint: UInt32 = try apploaderHeader.entry_point
        let appSize: Int = try apploaderHeader.size
        let trailerSize: Int = try apploaderHeader.trailer_size
        
        self.date = date.string(format: .ascii_big)
        self.entryPoint = entryPoint
        self.appCode = data.read(atAddress: apploaderHeader.length, length: appSize) ?? .none
        self.trailerCode = data.read(atAddress: apploaderHeader.length + appSize, length: trailerSize) ?? .none
    }
    
    public var data: GoDData {
        get throws {
            let apploaderHeaderStruct = dolphinEngine.apploaderHeaderStruct
            let header = StructData(definition: apploaderHeaderStruct, data: GoDData(length: apploaderHeaderStruct.length, byteOrder: .big))
            
            header.date = date.data(format: .ascii_big)
            header.entry_point = entryPoint
            header.size = appCode.length
            header.trailer_size = trailerCode.length
            
            let result = header.data
            result.append(appCode)
            result.append(trailerCode)
            return result
        }
    }
}
