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

public final class GamecubeISO: FileSystemTree {
    public static let formatName = "Gamecube.iso"
    
    private let dolphinEngine: DolphinEngine
    private let gamecubeEngine: GamecubeEngine
    fileprivate let fst = InMemoryFST()
    
    public var fstManifest: DolphinFST {
        DolphinFST(fileSystem: self, root: filesFolder)
    }
    
    public func inspectFile(at path: File) -> FileMetaData? {
        fst.inspectFile(at: path)
    }
    
    public func readFile(at path: File) -> GoDData? {
        fst.readFile(at: path)
    }
    
    public func moveFile(at path: File, to newPath: File, overwrite: Bool) throws {
        try fst.moveFile(at: path, to: newPath, overwrite: overwrite)
    }
    
    public func writeFile(_ file: GoDData, at path: File, overwrite: Bool) throws {
        file.setByteOrder(.big)
        try fst.writeFile(file, at: path, overwrite: overwrite)
    }
    
    public func deleteFile(at path: File) throws {
        try fst.deleteFile(at: path)
    }
    
    public func inspectFolder(at path: Folder) -> FolderMetaData? {
        fst.inspectFolder(at: path)
    }
    
    public func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) throws {
        try fst.moveFolder(at: path, to: newPath, overwrite: overwrite)
    }
    
    public func createFolder(at path: Folder, overwrite: Bool) throws {
        try fst.createFolder(at: path, overwrite: overwrite)
    }
    
    public func deleteFolder(at path: Folder) throws {
        try fst.deleteFolder(at: path)
    }
    
    /// Reads a disc image.
    ///
    /// `data` is a `GoDReadable`, not a `GoDData`, because this only ever
    /// reads windows of the image — the boot header, the FST, then one member
    /// file at a time. Taking the narrower type would force a caller to hold
    /// a 1.4 GB image in memory to extract a few megabytes of it; pass a
    /// `GoDStreamedData` and peak memory is the largest single member instead.
    ///
    /// The image must be big-endian, which is the only thing a GameCube disc
    /// ever is. A little-endian source would read every offset byte-swapped
    /// and fail somewhere less obvious than here.
    public init(
        data: GoDReadable,
        dolphinEngine: DolphinEngine,
        gamecubeEngine: GamecubeEngine
    ) throws {
        self.dolphinEngine = dolphinEngine
        self.gamecubeEngine = gamecubeEngine
        guard data.byteOrder == .big else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }

        // Create root folders
        try fst.createFolder(at: systemFolder, overwrite: true)
        try fst.createFolder(at: filesFolder, overwrite: true)
        
        // Get boot.bin
        let bootDataStruct = dolphinEngine.bootDataStruct
        let bootDataOffset = dolphinEngine.data.systemFiles.bootDataOffset
        let bootFile = dolphinEngine.data.systemFiles.bootFile
        guard let bootData = data.read(struct: bootDataStruct, atAddress: bootDataOffset) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        
        try fst.writeFile(bootData.data, at: bootFile, overwrite: true)
        
        // Get fst.bin
        let fstOffset: Int = try bootData.fst_offset
        let fstSize: Int = try bootData.fst_size
        let fstFile = dolphinEngine.data.systemFiles.fstFile
        guard let fstData = data.read(atAddress: fstOffset, length: fstSize) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        
        try fst.writeFile(fstData, at: fstFile, overwrite: true)
        
        // Get main.dol
        let dolOffset: Int = try bootData.main_executable_offset
        let dolHeaderStruct = dolphinEngine.dolHeaderStruct
        guard let dolHeader = data.read(struct: dolHeaderStruct, atAddress: dolOffset) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        let textSectionsSizes: [UInt32] = try dolHeader.text_sections_sizes
        let dataSectionsSizes: [UInt32] = try dolHeader.data_sections_sizes
        
        let textSizes = textSectionsSizes.map { $0.asInt }
        let dataSizes = dataSectionsSizes.map { $0.asInt }
        let dolSize = dolHeader.length + textSizes.reduce(0, +) + dataSizes.reduce(0, +)
        
        guard let dolData = data.read(atAddress: dolOffset, length: dolSize) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        let dolFile = dolphinEngine.data.systemFiles.executableFile
        
        try fst.writeFile(dolData, at: dolFile, overwrite: true)
        
        // Get bi2.bin
        let bi2DataStruct = dolphinEngine.bi2Struct
        let bi2DataOffset = dolphinEngine.data.systemFiles.bi2DataOffset
        let bi2File = dolphinEngine.data.systemFiles.bi2File
        guard let bi2Data = data.read(struct: bi2DataStruct, atAddress: bi2DataOffset) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        
        try fst.writeFile(bi2Data.data, at: bi2File, overwrite: true)
        
        // Get apploader.img
        let apploaderHeaderStruct = dolphinEngine.apploaderHeaderStruct
        let apploaderOffset = dolphinEngine.data.systemFiles.apploaderOffset
        guard let apploaderHeader = data.read(struct: apploaderHeaderStruct, atAddress: apploaderOffset) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        let appSize: Int = try apploaderHeader.size
        let trailerSize: Int = try apploaderHeader.trailer_size
        let apploaderFile = dolphinEngine.data.systemFiles.apploaderFile
        
        let apploaderSize = apploaderHeader.length + appSize + trailerSize
        guard let apploader = data.read(atAddress: apploaderOffset, length: apploaderSize) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        
        try fst.writeFile(apploader, at: apploaderFile, overwrite: true)
        
        let userSectionOffset: Int = try bootData.user_data_offset
        
        let shouldPreserveJunkData = dolphinEngine.data.systemFiles.preserveJunkData
        if shouldPreserveJunkData, fstOffset > dolOffset {
            let fstEnd = fstOffset + fstData.length
            let junkLength = userSectionOffset - fstEnd
            if junkLength > 0 {
                guard let junkData = data.read(atAddress: fstEnd, length: junkLength) else {
                    throw FileFormatErrors.invalid(format: Self.formatName)
                }
                if !junkData.isNull {
                    let junkFile = dolphinEngine.data.systemFiles.junkFile
                    try fst.writeFile(junkData, at: junkFile, overwrite: true)
                }
            }
        }
        
        let fstManifest = try DolphinFST(tocData: fstData, userSectionOffset: userSectionOffset, dolphinEngine: dolphinEngine)
        
        try fstManifest.folders.sorted().forEach { folder in
            try fst.createFolder(at: folder, overwrite: true)
        }
        try fstManifest.files.keys.sorted().forEach { file in
            guard let (offset, size) = fstManifest.files[file],
                  let fileData = data.read(atAddress: offset + userSectionOffset, length: size)  else { return }
            try fst.writeFile(fileData, at: file, overwrite: true)
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
        try? importFST(fst, from: rootFolder, to: Folder("/"), overwrite: true)
    }
    
    public var data: GoDData {
        get throws {
            let isoData = GoDData(length: 0, byteOrder: .big)
            
            // Get boot.bin
            let bootFile = dolphinEngine.data.systemFiles.bootFile
            let bootDataStruct = dolphinEngine.bootDataStruct
            guard let bootData = readFile(at: bootFile),
                  let bootStruct = bootData.read(struct: bootDataStruct, atAddress: 0) else {
                throw FileFormatErrors.failedToEncode(format: Self.formatName, target: ".iso")
            }
            
            // Set bi2.bin
            let bi2DataStruct = dolphinEngine.bi2Struct
            let bi2File = dolphinEngine.data.systemFiles.bi2File
            guard let bi2Data = readFile(at: bi2File),
                  let bi2Struct = bi2Data.read(struct: bi2DataStruct, atAddress: 0) else {
                throw FileFormatErrors.failedToEncode(format: Self.formatName, target: ".iso")
            }
            
            let bi2DataOffset = dolphinEngine.data.systemFiles.bi2DataOffset
            isoData.write(struct: bi2Struct, atAddress: bi2DataOffset)
            
            // Set apploader.img
            let apploaderFile = dolphinEngine.data.systemFiles.apploaderFile
            guard let apploaderData = readFile(at: apploaderFile) else {
                throw FileFormatErrors.failedToEncode(format: Self.formatName, target: ".iso")
            }
            
            let apploaderOffset = dolphinEngine.data.systemFiles.apploaderOffset
            isoData.write(apploaderData, atAddress: apploaderOffset)
            
            // Set main.dol
            let dolAlignment = max(dolphinEngine.data.systemFiles.dolOffsetAlignment, 1)
            let dolOffset = (apploaderOffset + apploaderData.length).aligned(to: dolAlignment)
            bootStruct.main_executable_offset = dolOffset
            
            let dolFile = dolphinEngine.data.systemFiles.executableFile
            guard let dolData = readFile(at: dolFile) else {
                throw FileFormatErrors.failedToEncode(format: Self.formatName, target: ".iso")
            }
            isoData.write(dolData, atAddress: dolOffset)
            
            // Set fst.bin
            let fstAlignment = max(dolphinEngine.data.systemFiles.fstOffsetMultiplier, 1)
            let fstOffset = (dolOffset + dolData.length).aligned(to: fstAlignment)
            bootStruct.fst_offset = fstOffset
            
            // Build the manifest exactly once. It is a computed property, so
            // each access re-walks the whole tree and re-assigns every file's
            // user-section offset — reading it three times did the work three
            // times and, worse, meant the offsets baked into the FST came from
            // a different object than the ones used to place the bytes.
            let manifest = fstManifest

            let fstSize = manifest.tocDataLength
            bootStruct.fst_size = fstSize
            bootStruct.max_fst_size = fstSize
            
            var junkData = GoDData(length: 0, byteOrder: .big)
            if dolphinEngine.data.systemFiles.preserveJunkData {
                let junkFile = dolphinEngine.data.systemFiles.junkFile
                if let preservedJunkData = readFile(at: junkFile) {
                    junkData = preservedJunkData
                }
            }
            
            let userAlignment = dolphinEngine.data.userFiles.userOffsetAlignment
            let userOffset = (fstOffset + fstSize + junkData.length).aligned(to: userAlignment)
            bootStruct.user_data_offset = userOffset
            
            let fstData = try manifest.tocData(userOffset: userOffset, dolphinEngine: dolphinEngine)
            
            isoData.write(fstData, atAddress: fstOffset)
            isoData.write(junkData, atAddress: fstOffset + fstData.length)
            
            // Set user files
            let userData = GoDData(byteOrder: .big)
            try manifest.files
                .sorted(by: { item1, item2 in
                    item1.value.offsetInUserSection < item2.value.offsetInUserSection
                })
                .forEach { (file, value) in
                    let offset = value.offsetInUserSection
                    guard let fileData = fst.readFile(at: file) else {
                        throw FileFormatErrors.failedToEncode(format: Self.formatName, target: ".iso")
                    }
                    userData.write(fileData, atAddress: offset)
                }
            
            userData.align(to: 0x10)
            bootStruct.user_data_length = userData.length
            
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

// MARK: - Sizing and readers
//
// A pass-through to the backing tree, like the whole-file operations above.

public extension GamecubeISO {
    func fileSize(at path: File) -> Int? { fst.fileSize(at: path) }

    func reader(at path: File) -> GoDReadable? { fst.reader(at: path) }

    func resizeFile(at path: File, to length: Int) throws {
        try fst.resizeFile(at: path, to: length)
    }
}
