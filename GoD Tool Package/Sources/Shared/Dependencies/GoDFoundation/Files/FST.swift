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

    public init(filename: String, filetype: String?, filesize: Int?, notes: String?) {
        self.filename = filename
        self.filetype = filetype
        self.filesize = filesize
        self.notes = notes
    }
}

public struct FolderMetaData {
    public let name: String
    public let size: Int?
    public let notes: String?

    public let files: [File]
    public let subFolders: [Folder]

    public init(name: String, size: Int?, notes: String?, files: [File], subFolders: [Folder]) {
        self.name = name
        self.size = size
        self.notes = notes
        self.files = files
        self.subFolders = subFolders
    }
}

/// A tree of files and folders — either on disk (`FileSystem`) or in memory
/// (`InMemoryFST`, `GamecubeISO`).
///
/// **Reads** return optionals: a missing file is an ordinary, expected
/// answer that callers routinely branch on.
///
/// **Writes throw.** A failed write means bytes the user asked for are not
/// where they asked for them, which must never pass silently — an operation
/// that reports success while having dropped output is worse than one that
/// stops. Callers that genuinely don't care can opt out explicitly with
/// `try?`.
///
/// **Thread safety:** implementations are *not* synchronised. Concurrent
/// reads of an otherwise-idle tree are safe; any concurrent write — or a
/// read racing a write — is undefined. Callers that fan out (e.g. the FSYS
/// pack/unpack passes) must confine all mutation to a single thread.
public protocol FileSystemTree {
    func inspectFile(at path: File) -> FileMetaData?
    func readFile(at path: File) -> GoDData?
    func moveFile(at path: File, to newPath: File, overwrite: Bool) throws
    func writeFile(_ file: GoDData, at path: File, overwrite: Bool) throws
    func deleteFile(at path: File) throws

    func inspectFolder(at path: Folder) -> FolderMetaData?
    func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) throws
    func createFolder(at path: Folder, overwrite: Bool) throws
    func deleteFolder(at path: Folder) throws
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
    
    func rename(file path: File, to newName: String, overwrite: Bool = false) throws {
        guard let newFile = path.parentFolder?.file(newName) else {
            throw FSTErrors.invalidPath(path.path, .init())
        }
        try moveFile(at: path, to: newFile, overwrite: overwrite)
    }

    func rename(folder path: Folder, to newName: String, overwrite: Bool = false) throws {
        guard let newFolder = path.parentFolder?.folder(newName) else {
            throw FSTErrors.invalidPath(path.path, .init())
        }
        try moveFolder(at: path, to: newFolder, overwrite: overwrite)
    }

    func readFile<T: Decodable>(at path: File) -> T? {
        guard let data: GoDData = readFile(at: path) else { return nil }
        return T.decodeJSON(from: data)
    }

    func writeFile(_ item: Encodable, at path: File, overwrite: Bool) throws {
        guard let data = item.encodeJSON() else {
            throw FSTErrors.failedToWriteFile(path, .init())
        }
        try writeFile(data, at: path, overwrite: overwrite)
    }
    
    var root: FolderMetaData {
        let rootFolder = Folder("/")
        return inspectFolder(at: rootFolder) ?? .init(
            name: "/",
            size: nil,
            notes: nil,
            files: [],
            subFolders: []
        )
    }
    
    func importFST(
        _ fileSystem: FileSystemTree,
        from rootFolder: Folder,
        to targetFolder: Folder,
        overwrite: Bool,
        logger: Logger? = nil
    ) throws {

        guard let rootContents = fileSystem.inspectFolder(at: rootFolder) else {
            return
        }

        let totalSize = rootContents.size ?? 0
        var sizeProcessed = 0
        let shouldTrackProgress = totalSize > 0 && logger != nil

        func add(_ files: [File]) throws {
            for file in files {
                guard let data = fileSystem.readFile(at: file) else { continue }
                var newFile = file
                if file.path.startsWith(rootFolder.path) {
                    let relativePath = file.path.substring(from: rootFolder.path.count)
                    newFile = targetFolder.file(relativePath)
                }
                try writeFile(data, at: newFile, overwrite: overwrite)

                if shouldTrackProgress {
                    sizeProcessed += data.length
                    let percentage = Percentage(min(Double(sizeProcessed) / Double(totalSize) * 100, 100))
                    logger?.log(.taskStatus(taskName: "Import FST", status: .progress(percentage)))
                }
            }
        }

        func add(_ folders: [Folder]) throws {
            for folder in folders {
                guard let contents = fileSystem.inspectFolder(at: folder) else { continue }
                var newFolder = folder
                if folder.path.startsWith(rootFolder.path) {
                    let relativePath = folder.path.substring(from: rootFolder.path.count)
                    newFolder = targetFolder.folder(relativePath)
                }
                try createFolder(at: newFolder, overwrite: overwrite)

                try add(contents.files)
                try add(contents.subFolders)
            }
        }

        logger?.log(.info("Importing \(rootFolder.path) to \(targetFolder.path)"))
        logger?.log(.taskStatus(taskName: "Import FST", status: .started))

        try add(rootContents.files)
        try add(rootContents.subFolders)

        logger?.log(.taskStatus(taskName: "Import FST", status: .completed(true)))
    }
}
