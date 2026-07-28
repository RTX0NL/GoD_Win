//
//  FST.swift
//  
//
//  Created by Stars Momodu on 04/06/2024.
//

import GoDFoundation
import GoDEngine
import Structs

public class DolphinFST {
    public static let formatName = ".toc"
    
    public var files = [File: (offsetInUserSection: Int, size: Int)]()
    public var folders = [Folder]()
    
    /// - Parameter offsetMultiplier: what an entry's stored file offset is
    ///   multiplied by to get a byte offset. Wii discs store it >> 2, so the
    ///   Wii engine's value (4) has to be passed in — the Dolphin engine's is 1.
    ///   Entry *sizes* are plain byte counts on both platforms.
    public init(
        tocData: GoDData,
        userSectionOffset: Int,
        dolphinEngine: DolphinEngine,
        offsetMultiplier: Int? = nil
    ) throws {
        let offsetMultiplier: Int = max(offsetMultiplier ?? dolphinEngine.data.systemFiles.fstOffsetMultiplier, 1)

        let rootStruct: StructDefinition = dolphinEngine.fstRootEntryStruct
        let fileStruct: StructDefinition = dolphinEngine.fstFileEntryStruct
        let folderStruct: StructDefinition = dolphinEngine.fstDirectoryEntryStruct
        guard let root = tocData.read(struct: rootStruct, atAddress: 0) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        let entryCount: Int = try root.entry_count
        
        let entrySize = 12
        let stringTableOffset = entryCount * entrySize
        
        func getString(_ offset: Int) -> String? {
            tocData.readString(atAddress: stringTableOffset + offset, format: .utf8)
        }
        
        var currentFolder = dolphinEngine.data.userFiles.filesFolder
        var subfolderEndIndexes = [Int]()
        for index in 1 ..< entryCount {
            while let endIndex = subfolderEndIndexes.last, index >= endIndex {
                subfolderEndIndexes.removeLast()
                currentFolder = currentFolder.parentFolder ?? currentFolder
            }
            let entryOffset = index * entrySize
            let isDirectory: Bool = tocData.readSafely(atAddress: entryOffset)
            if isDirectory {
                guard let entry = tocData.read(struct: folderStruct, atAddress: entryOffset) else {
                    throw FileFormatErrors.invalid(format: Self.formatName)
                }
                let nameOffset: Int = try entry.name_offset
                let endIndex: Int = try entry.next_entry
                guard let folderName = getString(nameOffset) else {
                    throw FileFormatErrors.invalid(format: Self.formatName)
                }
                currentFolder = currentFolder.folder(folderName)
                folders.append(currentFolder)
                subfolderEndIndexes.append(endIndex)
                
            } else {
                guard let entry = tocData.read(struct: fileStruct, atAddress: entryOffset) else {
                    throw FileFormatErrors.invalid(format: Self.formatName)
                }
                let nameOffset: Int = try entry.name_offset
                let fileOffset: Int = (try entry.file_offset) * offsetMultiplier
                let fileSize: Int = try entry.file_size
                guard let filename = getString(nameOffset) else {
                    throw FileFormatErrors.invalid(format: Self.formatName)
                }
                let file = currentFolder.file(filename)
                files[file] = (fileOffset - userSectionOffset, fileSize)
                
            }
        }
    }
    
    public init(fileSystem: FileSystemTree, root: Folder = Folder("/")) {
        var currentOffset = 0
        func align() {
            currentOffset = currentOffset.aligned(to: 4)
        }
        func add(_ file: File) {
            guard let data = fileSystem.readFile(at: file) else { return }
            files[file] = (currentOffset, data.length)
            currentOffset += data.length
            align()
        }
        
        func add(_ folder: Folder) {
            guard let contents = fileSystem.inspectFolder(at: folder) else { return }
            if folder != root {
                folders.append(folder)
            }
            add(contents.files)
            add(contents.subFolders)
            
            align()
        }
        
        func add(_ files: [File]) {
            files.forEach(add)
        }

        // Folders are visited in path order so a parent is always registered
        // before its children — `folders` doubles as the creation order when
        // the tree is materialised, and a child can't be created into a
        // folder that doesn't exist yet.
        func add(_ folders: [Folder]) {
            folders
                .sorted { item1, item2 in
                    item1.path < item2.path
                }
                .forEach { item in
                    add(item)
                }
        }
        
        add(root)
    }
    
    public var tocDataEntryCount: Int {
        files.keys.count + folders.count + 1
    }
    
    public var tocDataLength: Int {
            let entrySize = 12
            return tocDataEntryCount * entrySize + stringTableLength
    }
    
    /// - Parameter offsetMultiplier: see the parsing initialiser. Pass the Wii
    ///   engine's value (4) when writing a Wii FST.
    public func tocData(
        userOffset: Int,
        dolphinEngine: DolphinEngine,
        offsetMultiplier: Int? = nil
    ) throws -> GoDData {
        let offsetMultiplier = max(offsetMultiplier ?? dolphinEngine.data.systemFiles.fstOffsetMultiplier, 1)

        let tocData = GoDData(length: tocDataLength, byteOrder: .big)
        
        let entrySize = 12
        let rootStruct = dolphinEngine.fstRootEntryStruct
        let fileStruct = dolphinEngine.fstFileEntryStruct
        let folderStruct = dolphinEngine.fstDirectoryEntryStruct
        
        let rootData = StructData(definition: rootStruct, byteOrder: .big)
        rootData.is_directory = true
        rootData.entry_count = tocDataEntryCount
        tocData.write(struct: rootData, atAddress: 0)
        
        let stringTable = GoDData(byteOrder: .big)
        
        var currentIndex = 1
        let entryPaths = ["/"] + (files.keys.map(\.path) + folders.map(\.path)).sorted(by: {
            $0.uppercased() < $1.uppercased()
        })
        var folderIndexes = [Folder: Int]()
        while currentIndex < tocDataEntryCount {
            let currentOffset = currentIndex * entrySize
            let currentPath = entryPaths[currentIndex]
            let isFile = files[File(currentPath)] != nil
            if isFile {
                let file = File(currentPath)
                let nameOffset = stringTable.length
                stringTable.appendString(file.fileName, format: .utf8, includeTerminator: true)
                guard let (offset, size) = files[file] else {
                    throw FileFormatErrors.failedToEncode(format: Self.formatName, target: ".iso")
                }
                let fullOffset = offset + userOffset
                
                let fileData = StructData(definition: fileStruct, byteOrder: .big)
                fileData.is_directory = false
                fileData.name_offset = nameOffset
                fileData.file_offset = fullOffset / offsetMultiplier
                fileData.file_size = size
                tocData.write(struct: fileData, atAddress: currentOffset)
            } else {
                let folder = Folder(currentPath)
                let nameOffset = stringTable.length
                stringTable.appendString(folder.folderName, format: .utf8, includeTerminator: true)
                let parentFolder = folder.parentFolder ?? Folder("/")
                let parentIndex = folderIndexes[parentFolder] ?? 0
                
                let folderData = StructData(definition: folderStruct, byteOrder: .big)
                folderData.is_directory = true
                folderData.name_offset = nameOffset
                folderData.parent_entry = parentIndex
                folderData.next_entry = currentIndex + entryCount(for: folder) + 1
                tocData.write(struct: folderData, atAddress: currentOffset)
                folderIndexes[folder] = currentIndex
            }
            currentIndex += 1
        }
        
        let stringTableOffset = tocDataEntryCount * entrySize
        tocData.write(stringTable, atAddress: stringTableOffset)
        
        return tocData
    }
    
    private func entryCount(for folder: Folder) -> Int {
        let searchPath = folder.path + (folder.path.last == "/" ? "" : "/")
        let fileCount = files.keys
            .filter { $0.path.startsWith(searchPath) }
            .count
        let folderCount = folders
            .filter { $0.path.startsWith(searchPath) }
            .count
        return fileCount + folderCount
    }
    
    private var stringTableLength: Int {
        (files.keys.map(\.fileName) + folders.map(\.folderName))
            .map { $0.count + 1 } // +1 for null terminator
            .reduce(0, +) // sum
    }
}

extension DolphinFST: CustomStringConvertible {
    public var description: String {
        let paths = files.keys.map(\.path) + folders.map(\.path)
        var result = ""
        paths
            .sorted()
            .forEach { result += $0 + "\n" }
        if result.last == "\n" {
            result.removeLast()
        }
        return result
    }
}
