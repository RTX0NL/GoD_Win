//
//  FST.swift
//  
//
//  Created by Stars Momodu on 17/05/2024.
//

import Foundation

public struct FileMetaData {
    public let filename: String
    public let filetype: String?
    public let filesize: Int?
    public let notes: String?
}

public struct FolderMetaData {
    public let name: String
    public let size: Int?
    public let notes: String?
    
    public let files: [File]
    public let subFolders: [Folder]
}

public protocol FileSystemTree {
    func inspectFile(at path: File) -> FileMetaData?
    func readFile(at path: File) -> GoDData?
    @discardableResult func moveFile(at path: File, to newPath: File, overwrite: Bool) -> Bool
    @discardableResult func writeFile(_ file: GoDData, at path: File, overwrite: Bool) -> Bool
    @discardableResult func deleteFile(at path: File) -> Bool
    
    func inspectFolder(at path: Folder) -> FolderMetaData?
    @discardableResult func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) -> Bool
    @discardableResult func createFolder(at path: Folder, overwrite: Bool) -> Bool
    @discardableResult func deleteFolder(at path: Folder) -> Bool
}

public extension FileSystemTree {
    func itemExists(at path: PathRepresentable) -> Bool {
        if let filePath = path as? File {
            return inspectFile(at: filePath) != nil
        }
        if let folderPath = path as? Folder {
            return inspectFolder(at: folderPath) != nil
        }
        return false
    }
    
    @discardableResult
    func rename(file path: File, to newName: String, overwrite: Bool = false) -> Bool {
        guard let newFile = path.parentFolder?.file(newName) else { return false }
        return moveFile(at: path, to: newFile, overwrite: overwrite)
    }
    
    @discardableResult
    func rename(folder path: Folder, to newName: String, overwrite: Bool = false) -> Bool {
        guard let newFolder = path.parentFolder?.folder(newName) else { return false }
        return moveFolder(at: path, to: newFolder, overwrite: overwrite)
    }
    
    func readFile<T: Decodable>(at path: File) -> T? {
        guard let data: GoDData = readFile(at: path) else { return nil }
        return T.decodeJSON(from: data)
    }
    
    @discardableResult
    func writeFile(_ item: Encodable, at path: File, overwrite: Bool) -> Bool {
        guard let data = item.encodeJSON() else { return false }
        return writeFile(data, at: path, overwrite: overwrite)
    }
    
    var root: FolderMetaData {
        let rootFolder = Folder("/")
        return inspectFolder(at: rootFolder) ?? .init(name: "/", size: nil, notes: nil, files: [], subFolders: [])
    }
    
    func importFST(
        _ fileSystem: FileSystemTree,
        from rootFolder: Folder,
        to targetFolder: Folder,
        overwrite: Bool
    ) {
        func add(_ files: [File]) {
            for file in files {
                guard let data = fileSystem.readFile(at: file) else { return }
                var newFile = file
                if file.path.startsWith(rootFolder.path) {
                    let relativePath = file.path.substring(from: rootFolder.path.count)
                    newFile = targetFolder.file(relativePath)
                }
                writeFile(data, at: newFile, overwrite: overwrite)
            }
        }
        
        func add(_ folders: [Folder]) {
            for folder in folders {
                guard let contents = fileSystem.inspectFolder(at: folder) else { return }
                var newFolder = folder
                if folder.path.startsWith(rootFolder.path) {
                    let relativePath = folder.path.substring(from: rootFolder.path.count)
                    newFolder = targetFolder.folder(relativePath)
                }
                createFolder(at: newFolder, overwrite: overwrite)
                
                add(contents.files)
                add(contents.subFolders)
            }
        }
        
        guard let rootContents = fileSystem.inspectFolder(at: rootFolder) else {
            return
        }
        add(rootContents.files)
        add(rootContents.subFolders)
    }
}
