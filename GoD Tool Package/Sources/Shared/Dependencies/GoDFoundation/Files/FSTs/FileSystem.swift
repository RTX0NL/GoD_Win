//
//  OnDiscFST.swift
//  
//
//  Created by Stars Momodu on 02/06/2024.
//

import Foundation

public class FileSystem: FileSystemTree {
    
    private(set) var currentDirectory = Folder("/")
    private let fm = FileManager.default
    
    public static let shared = FileSystem()
    private init() {}
    
    public func inspectFile(at path: File) -> FileMetaData? {
        let filePath = extendPath(path).path
        
        let exists = fm.fileExists(atPath: filePath)
        guard exists else { return nil }
        
        let name = path.name
        let type = name.fileExtension
        
        let attributes = try? fm.attributesOfItem(atPath: filePath)
        let size: Int? = attributes?[.size] as? Int
        
        return .init(
            filename: name,
            filetype: type,
            filesize: size,
            notes: nil
        )
    }
    
    public func readFile(at path: File) -> GoDData? {
        let filePath = extendPath(path)
        guard let data = try? Data(contentsOf: filePath.url) else  {
            return nil
        }
        return GoDData(data: data, byteOrder: Environment.byteOrder)
    }
    
    @discardableResult
    public func moveFile(at path: File, to newPath: File, overwrite: Bool) -> Bool {
        let fullPath = extendPath(path)
        let fullNewPath = extendPath(newPath)
        guard let parentFolder = fullNewPath.parentFolder else {
            return false
        }
        do {
            if !itemExists(at: parentFolder) {
                createFolder(at: parentFolder, overwrite: overwrite)
            }
            try fm.moveItem(atPath: fullPath.path, toPath: fullNewPath.path)
            return true
        } catch {
            return false
        }
    }
    
    @discardableResult
    public func writeFile(_ file: GoDData, at path: File, overwrite: Bool) -> Bool {
        let fullPath = extendPath(path)
        guard let parentFolder = fullPath.parentFolder else { return false }
        if !itemExists(at: parentFolder) {
            createFolder(at: parentFolder, overwrite: overwrite)
        }
        guard !itemExists(at: fullPath) || overwrite else { return false }
        do {
            try file.data.write(to: fullPath.url)
            return true
        } catch {
            return false
        }
    }
    
    @discardableResult
    public func deleteFile(at path: File) -> Bool {
        let fullPath = extendPath(path)
        do {
            try fm.removeItem(at: fullPath.url)
            return true
        } catch {
            return false
        }
    }
    
    public func inspectFolder(at path: Folder) -> FolderMetaData? {
        let fullPath = extendPath(path)
        guard let paths = try? fm.contentsOfDirectory(atPath: fullPath.path) else {
            return nil
        }
        let folder = path
        var files = [File]()
        var folders = [Folder]()
        
        paths.forEach { path in
            var isDirectory: ObjCBool = false
            _ = fm.fileExists(atPath: fullPath.file(path).path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                let subFolder = folder.folder(path)
                folders.append(subFolder)
            } else {
                let file = folder.file(path)
                files.append(file)
            }
        }
        
        let attributes = try? fm.attributesOfItem(atPath: fullPath.path)
        let size: Int? = attributes?[.size] as? Int
        
        return .init(
            name: path.folderName,
            size: size,
            notes: nil,
            files: files,
            subFolders: folders
        )
    }
    
    @discardableResult
    public func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) -> Bool {
        let fullPath = extendPath(path)
        let fullNewPath = extendPath(newPath)
        guard let parentFolder = fullNewPath.parentFolder else {
            return false
        }
        do {
            if !itemExists(at: parentFolder) {
                createFolder(at: parentFolder, overwrite: overwrite)
            }
            guard !itemExists(at: fullPath) || overwrite else { return false }
            try fm.moveItem(atPath: fullPath.path, toPath: fullNewPath.path)
            return true
        } catch {
            return false
        }
    }
    
    @discardableResult
    public func createFolder(at path: Folder, overwrite: Bool) -> Bool {
        let fullPath = extendPath(path)
        guard !itemExists(at: fullPath) || overwrite else { return false }
        do {
            try fm.createDirectory(atPath: fullPath.path, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
    
    @discardableResult
    public func deleteFolder(at path: Folder) -> Bool {
        let fullPath = extendPath(path)
        guard itemExists(at: fullPath) else { return true }
        do {
            try fm.removeItem(atPath: fullPath.path)
            return true
        } catch {
            return false
        }
    }
    
    public func pathForResource(_ filename: String, bundle: Bundle) -> File? {
        guard let url = bundle.url(forResource: filename.withoutExtension, withExtension: filename.fileExtension) else {
            return nil
        }
        return File(url.path)
    }
    
    public var documents: Folder {
        Folder(
            NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        )
    }
    
    public func changeDirectory(_ newDirectory: Folder) {
        if newDirectory.path.startsWith("/") {
                currentDirectory = newDirectory
        } else {
            currentDirectory = currentDirectory.folder(newDirectory.path)
        }
    }
    
    public func setExecutable(file: File) {
        let fullPath = currentDirectory.file(file.path)
        guard itemExists(at: fullPath) else { return }
        try? fm.setAttributes([FileAttributeKey.posixPermissions: 0o777], ofItemAtPath: fullPath.path)
    }
    
    private func extendPath(_ file: File) -> File {
        if file.path.startsWith("./") || file.path.startsWith("../") {
            return currentDirectory.file(file.path)
        } else {
            return file
        }
    }

    private func extendPath(_ folder: Folder) -> Folder {
        if folder.path.startsWith("./") || folder.path.startsWith("../") {
            return currentDirectory.folder(folder.path)
        } else {
            return folder
        }
    }
}

public extension FileSystemTree {
    func decodeJSON<T: Decodable>(from file: File) throws -> T {
        guard let data = readFile(at: file) else {
            throw FSTErrors.fileNotFound(file, .init())
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}

public extension FileSystemTree {
    func encodeJSON<Value: Encodable>(_ value: Value, to file: File, overwrite: Bool) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data: GoDData = try encoder.encode(value)
        _ = writeFile(data, at: file, overwrite: overwrite)
    }
}
