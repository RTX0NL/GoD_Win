//
//  Dol.swift
//  
//
//  Created by Stars Momodu on 04/06/2024.
//

import GoDFoundation
import GoDEngine
import Structs

public final class Dol {
    public static let formatName = ".dol"
    
    private let dolphinEngine: DolphinEngine
    
    public var bssSize: UInt32
    public var bssRAMAddress: UInt32
    public var entryPoint: UInt32
    public var textSections: [TextSection]
    public var dataSections: [DataSection]
    
    public init(
        dolphinEngine: DolphinEngine,
        textSections: [TextSection],
        dataSections: [DataSection],
        bssRAMAddress: UInt32,
        bssSize: UInt32,
        entryPoint: UInt32
    ) {
        self.dolphinEngine = dolphinEngine
        self.textSections = textSections
        self.dataSections = dataSections
        self.bssRAMAddress = bssRAMAddress
        self.bssSize = bssSize
        self.entryPoint = entryPoint
    }

    public init(data: GoDData, dolphinEngine: DolphinEngine) throws {
        self.dolphinEngine = dolphinEngine

        data.setByteOrder(.big)
        let dolHeaderStruct = dolphinEngine.dolHeaderStruct
        guard let dolHeader = data.read(struct: dolHeaderStruct, atAddress: 0) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        let entryPoint: UInt32 = try dolHeader.entry_point
        let bssSize: UInt32 = try dolHeader.BSS_size
        let bssRAMAddress: UInt32 = try dolHeader.BSS_RAM_address
        
        self.bssSize = bssSize
        self.bssRAMAddress = bssRAMAddress
        self.entryPoint = entryPoint
        
        let textSectionsOffsets: [UInt32] = try dolHeader.text_sections_offsets
        let textSectionsSizes: [UInt32] = try dolHeader.text_sections_sizes
        let textSectionsRAMAddresses: [UInt32] = try dolHeader.text_sections_RAM_addresses
        let dataSectionsOffsets: [UInt32] = try dolHeader.data_sections_offsets
        let dataSectionsSizes: [UInt32] = try dolHeader.data_sections_sizes
        let dataSectionsRAMAddresses: [UInt32] = try dolHeader.data_sections_RAM_addresses
        
        var textSections = [TextSection]()
        for (offset, size, RAMAddress) in zip3(textSectionsOffsets, textSectionsSizes, textSectionsRAMAddresses) {
            if size > 0, let sectionData = data.read(atAddress: UInt(offset), length: UInt(size)) {
                textSections.append(.init(RAMAddress: RAMAddress, assembly: sectionData))
            } else {
                textSections.append(.init(RAMAddress: RAMAddress, assembly: .none))
            }
        }
        self.textSections = textSections
        
        var dataSections = [DataSection]()
        for (offset, size, RAMAddress) in zip3(dataSectionsOffsets, dataSectionsSizes, dataSectionsRAMAddresses) {
            if size > 0, let sectionData = data.read(atAddress: UInt(offset), length: UInt(size)) {
                dataSections.append(.init(RAMAddress: RAMAddress, data: sectionData))
            } else {
                dataSections.append(.init(RAMAddress: RAMAddress, data: .none))
            }
        }
        self.dataSections = dataSections
    }
    
    public var data: GoDData {
        get throws {
            let dolHeaderStruct = dolphinEngine.dolHeaderStruct
            let header = StructData(definition: dolHeaderStruct, byteOrder: .big)
            
            header.BSS_size = bssSize
            header.BSS_RAM_address = bssRAMAddress
            header.entry_point = entryPoint
            
            var textSectionOffsets = [UInt32]()
            var textSectionRAMAddresses = [UInt32]()
            var textSectionSizes = [UInt32]()
            var dataSectionOffsets = [UInt32]()
            var dataSectionRAMAddresses = [UInt32]()
            var dataSectionSizes = [UInt32]()
            
            var currentOffset = dolHeaderStruct.length
            
            for i in 0 ... 6 {
                if i < textSections.count {
                    let section = textSections[i]
                    textSectionOffsets.append(currentOffset.unsigned)
                    textSectionRAMAddresses.append(section.RAMAddress)
                    textSectionSizes.append(section.assembly.length.unsigned)
                    currentOffset += section.assembly.length
                } else {
                    textSectionOffsets.append(0)
                    textSectionRAMAddresses.append(0)
                    textSectionSizes.append(0)
                }
            }
            
            for i in 0 ... 10 {
                if i < dataSections.count {
                    let section = dataSections[i]
                    dataSectionOffsets.append(currentOffset.unsigned)
                    dataSectionRAMAddresses.append(section.RAMAddress)
                    dataSectionSizes.append(section.data.length.unsigned)
                    currentOffset += section.data.length
                } else {
                    dataSectionOffsets.append(0)
                    dataSectionRAMAddresses.append(0)
                    dataSectionSizes.append(0)
                }
            }
            
            header.text_sections_offsets = textSectionOffsets
            header.text_sections_RAM_addresses = textSectionRAMAddresses
            header.text_sections_sizes = textSectionSizes
            header.data_sections_offsets = dataSectionOffsets
            header.data_sections_RAM_addresses = dataSectionRAMAddresses
            header.data_sections_sizes = dataSectionSizes
            
            let result = header.data
            textSections.forEach {
                result.append($0.assembly)
            }
            dataSections.forEach {
                result.append($0.data)
            }
            return result
        }
    }
}

public extension Dol {
    class TextSection {
        public var RAMAddress: UInt32
        public var assembly: GoDData
        
        public init(RAMAddress: UInt32, assembly: GoDData) {
            self.RAMAddress = RAMAddress
            self.assembly = assembly
        }
    }
    
    class DataSection {
        public var RAMAddress: UInt32
        public var data: GoDData
        
        public init(RAMAddress: UInt32, data: GoDData) {
            self.RAMAddress = RAMAddress
            self.data = data
        }
    }
}
