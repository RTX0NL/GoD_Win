//
//  GamecubeISO.swift
//  
//
//  Created by Stars Momodu on 17/05/2024.
//

import GoDFoundation
import GoDEngine
import Dolphin
import Structs

public final class GamecubeISO: FileSystemTree, FileFormat {
    public static let formatName = "Gamecube.iso"
    
    private let dolphinEngine: DolphinEngine
    private let gamecubeEngine: GamecubeEngine
    private let fst = InMemoryFST()
    
    public var fstManifest: DolphinFST {
        DolphinFST(fileSystem: self, root: filesFolder)
    }
    
    public func inspectFile(at path: File) -> FileMetaData? {
        fst.inspectFile(at: path)
    }
    
    public func readFile(at path: File) -> GoDData? {
        fst.readFile(at: path)
    }
    
    public func moveFile(at path: File, to newPath: File, overwrite: Bool) -> Bool {
        fst.moveFile(at: path, to: newPath, overwrite: overwrite)
    }
    
    public func writeFile(_ file: GoDData, at path: File, overwrite: Bool) -> Bool {
        file.setByteOrder(.big)
        return fst.writeFile(file, at: path, overwrite: overwrite)
    }
    
    public func deleteFile(at path: File) -> Bool {
        fst.deleteFile(at: path)
    }
    
    public func inspectFolder(at path: Folder) -> FolderMetaData? {
        fst.inspectFolder(at: path)
    }
    
    public func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) -> Bool {
        fst.moveFolder(at: path, to: newPath, overwrite: overwrite)
    }
    
    public func createFolder(at path: Folder, overwrite: Bool) -> Bool {
        fst.createFolder(at: path, overwrite: overwrite)
    }
    
    public func deleteFolder(at path: Folder) -> Bool {
        fst.deleteFolder(at: path)
    }
    
    public init(
        data: GoDData,
        dolphinEngine: DolphinEngine,
        gamecubeEngine: GamecubeEngine
    ) throws {
        self.dolphinEngine = dolphinEngine
        self.gamecubeEngine = gamecubeEngine
        data.setByteOrder(.big)
        
        // Create root folders
        fst.createFolder(at: systemFolder, overwrite: true)
        fst.createFolder(at: filesFolder, overwrite: true)
        
        // Get boot.bin
        let bootDataStruct = dolphinEngine.bootDataStruct
        let bootDataOffset = dolphinEngine.data.systemFiles.bootDataOffset
        let bootFile = dolphinEngine.data.systemFiles.bootFile
        guard let bootData = data.read(struct: bootDataStruct, atAddress: bootDataOffset) else {
            throw Self.invalidFileError
        }
        
        fst.writeFile(bootData.data, at: bootFile, overwrite: true)
        
        // Get fst.bin
        let fstOffset: Int = try bootData.fstOffset
        let fstSize: Int = try bootData.fstSize
        let fstFile = dolphinEngine.data.systemFiles.fstFile
        guard let fstData = data.read(atAddress: fstOffset, length: fstSize) else {
            throw Self.invalidFileError
        }
        
        fst.writeFile(fstData, at: fstFile, overwrite: true)
        
        // Get main.dol
        let dolOffset: Int = try bootData.mainExecutableOffset
        let dolHeaderStruct = dolphinEngine.dolHeaderStruct
        guard let dolHeader = data.read(struct: dolHeaderStruct, atAddress: dolOffset) else {
            throw Self.invalidFileError
        }
        let textSectionsSizes: [UInt32] = try dolHeader.textSectionsSizes
        let dataSectionsSizes: [UInt32] = try dolHeader.dataSectionsSizes
        
        let textSizes = textSectionsSizes.map { $0.asInt }
        let dataSizes = dataSectionsSizes.map { $0.asInt }
        let dolSize = dolHeader.length + textSizes.reduce(0, +) + dataSizes.reduce(0, +)
        
        guard let dolData = data.read(atAddress: dolOffset, length: dolSize) else {
            throw Self.invalidFileError
        }
        let dolFile = dolphinEngine.data.systemFiles.executableFile
        
        fst.writeFile(dolData, at: dolFile, overwrite: true)
        
        // Get bi2.bin
        let bi2DataStruct = dolphinEngine.bi2Struct
        let bi2DataOffset = dolphinEngine.data.systemFiles.bi2DataOffset
        let bi2File = dolphinEngine.data.systemFiles.bi2File
        guard let bi2Data = data.read(struct: bi2DataStruct, atAddress: bi2DataOffset) else {
            throw Self.invalidFileError
        }
        
        fst.writeFile(bi2Data.data, at: bi2File, overwrite: true)
        
        // Get apploader.img
        let apploaderHeaderStruct = dolphinEngine.apploaderHeaderStruct
        let apploaderOffset = dolphinEngine.data.systemFiles.apploaderOffset
        guard let apploaderHeader = data.read(struct: apploaderHeaderStruct, atAddress: apploaderOffset) else {
            throw Self.invalidFileError
        }
        let appSize: Int = try apploaderHeader.size
        let trailerSize: Int = try apploaderHeader.trailerSize
        let apploaderFile = dolphinEngine.data.systemFiles.apploaderFile
        
        let apploaderSize = apploaderHeader.length + appSize + trailerSize
        guard let apploader = data.read(atAddress: apploaderOffset, length: apploaderSize) else {
            throw Self.invalidFileError
        }
        
        fst.writeFile(apploader, at: apploaderFile, overwrite: true)
        
        let userSectionOffset: Int = try bootData.userDataOffset
        
        let shouldPreserveJunkData = dolphinEngine.data.systemFiles.preserveJunkData
        if shouldPreserveJunkData, fstOffset > dolOffset {
            let fstEnd = fstOffset + fstData.length
            let junkLength = userSectionOffset - fstEnd
            if junkLength > 0 {
                guard let junkData = data.read(atAddress: fstEnd, length: junkLength) else {
                    throw Self.invalidFileError
                }
                if !junkData.isNull {
                    let junkFile = dolphinEngine.data.systemFiles.junkFile
                    fst.writeFile(junkData, at: junkFile, overwrite: true)
                }
            }
        }
        
        let fstManifest = try DolphinFST(tocData: fstData, userSectionOffset: userSectionOffset, dolphinEngine: dolphinEngine)
        
        fstManifest.folders.sorted().forEach { folder in
            fst.createFolder(at: folder, overwrite: true)
        }
        fstManifest.files.keys.sorted().forEach { file in
            guard let (offset, size) = fstManifest.files[file],
                  let fileData = data.read(atAddress: offset + userSectionOffset, length: size)  else { return }
            fst.writeFile(fileData, at: file, overwrite: true)
        }
    }
    
    public init(
        fst: FileSystemTree,
        rootFolder: Folder,
        dolphinEngine: DolphinEngine,
        gamecubeEngine: GamecubeEngine
    ) {
        self.dolphinEngine = dolphinEngine
        self.gamecubeEngine = gamecubeEngine
        importFST(fst, from: rootFolder, to: Folder("/"), overwrite: true)
    }
    
    public var data: GoDData {
        get throws {
            let isoData = GoDData(length: 0, byteOrder: .big)
            
            // Get boot.bin
            let bootFile = dolphinEngine.data.systemFiles.bootFile
            let bootDataStruct = dolphinEngine.bootDataStruct
            guard let bootData = readFile(at: bootFile),
                  let bootStruct = bootData.read(struct: bootDataStruct, atAddress: 0) else {
                throw Self.failedToEncodeError(target: ".iso")
            }
            
            // Set bi2.bin
            let bi2DataStruct = dolphinEngine.bi2Struct
            let bi2File = dolphinEngine.data.systemFiles.bi2File
            guard let bi2Data = readFile(at: bi2File),
                  let bi2Struct = bi2Data.read(struct: bi2DataStruct, atAddress: 0) else {
                throw Self.failedToEncodeError(target: ".iso")
            }
            
            let bi2DataOffset = dolphinEngine.data.systemFiles.bi2DataOffset
            isoData.write(struct: bi2Struct, atAddress: bi2DataOffset)
            
            // Set apploader.img
            let apploaderFile = dolphinEngine.data.systemFiles.apploaderFile
            guard let apploaderData = readFile(at: apploaderFile) else {
                throw Self.failedToEncodeError(target: ".iso")
            }
            
            let apploaderOffset = dolphinEngine.data.systemFiles.apploaderOffset
            isoData.write(apploaderData, atAddress: apploaderOffset)
            
            // Set main.dol
            let dolAlignment = max(dolphinEngine.data.systemFiles.dolOffsetAlignment, 1)
            let dolOffset = (apploaderOffset + apploaderData.length).aligned(to: dolAlignment)
            bootStruct.mainExecutableOffset = dolOffset
            
            let dolFile = dolphinEngine.data.systemFiles.executableFile
            guard let dolData = readFile(at: dolFile) else {
                throw Self.failedToEncodeError(target: ".iso")
            }
            isoData.write(dolData, atAddress: dolOffset)
            
            // Set fst.bin
            let fstAlignment = max(dolphinEngine.data.systemFiles.fstOffsetMultiplier, 1)
            let fstOffset = (dolOffset + dolData.length).aligned(to: fstAlignment)
            bootStruct.fstOffset = fstOffset
            
            let fstSize = fstManifest.tocDataLength
            bootStruct.fstSize = fstSize
            bootStruct.maxFstSize = fstSize
            
            var junkData = GoDData(length: 0, byteOrder: .big)
            if dolphinEngine.data.systemFiles.preserveJunkData {
                let junkFile = dolphinEngine.data.systemFiles.junkFile
                if let preservedJunkData = readFile(at: junkFile) {
                    junkData = preservedJunkData
                }
            }
            
            let userAlignment = dolphinEngine.data.userFiles.userOffsetAlignment
            let userOffset = (fstOffset + fstSize + junkData.length).aligned(to: userAlignment)
            bootStruct.userDataOffset = userOffset
            
            let fstData = try fstManifest.tocData(userOffset: userOffset, dolphinEngine: dolphinEngine)
            
            isoData.write(fstData, atAddress: fstOffset)
            isoData.write(junkData, atAddress: fstOffset + fstData.length)
            
            // Set user files
            let userData = GoDData(byteOrder: .big)
            try fstManifest.files
                .sorted(by: { item1, item2 in
                    item1.value.offsetInUserSection < item2.value.offsetInUserSection
                })
                .forEach { (file, value) in
                    let offset = value.offsetInUserSection
                    guard let fileData = fst.readFile(at: file) else {
                        throw Self.failedToEncodeError(target: ".iso")
                    }
                    userData.write(fileData, atAddress: offset)
                }
            
            userData.align(to: 0x10)
            bootStruct.userDataLength = userData.length
            
            isoData.write(userData, atAddress: userOffset)
            
            // Write boot.bin
            let bootDataOffset = dolphinEngine.data.systemFiles.bootDataOffset
            isoData.write(struct: bootStruct, atAddress: bootDataOffset)
            
            return isoData
        }
    }
    
    public var filesFolder: Folder {
        dolphinEngine.data.userFiles.filesFolder
    }
    
    public var systemFolder: Folder {
        dolphinEngine.data.systemFiles.systemFolder
    }
}
