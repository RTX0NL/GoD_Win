//
//  OnDiscFST.swift
//  
//
//  Created by Stars Momodu on 02/06/2024.
//

import Foundation

public class FileSystem: FileSystemTree {

    /// Base for resolving `./`-and-`../`-prefixed paths (see `extendPath`).
    /// Seeded from the process working directory so relative paths behave
    /// the way a shell user expects; `changeDirectory` then re-points it at
    /// the running config's `rootFolder`.
    private(set) var currentDirectory: Folder
    private let fm = FileManager.default

    public static let shared = FileSystem()
    private init() {
        // argv-adjacent input: a native path, converted on the way in.
        let cwd = PlatformPath.logical(from: FileManager.default.currentDirectoryPath)
        currentDirectory = Folder(cwd.hasPrefix("/") ? cwd : "/")
    }
    
    /// Answers "is anything here?" with one `stat`.
    ///
    /// The protocol's default asks `inspectFolder`, which lists the whole
    /// directory and builds a `File` or `Folder` for every entry in it — and
    /// `writeFile` asks this twice per write, so writing *n* files into one
    /// folder costs O(n²) directory listings. That is invisible on a folder
    /// of ten files and crippling on one of thousands: a Colosseum DOL
    /// disassembly with a symbol map loaded went from seconds to minutes,
    /// which is what put a `sample` of the "stall" on this line.
    public func itemExists(at path: PathRepresentable) -> Bool {
        // `extendPath` only resolves a `./` prefix and `nativePath` is the
        // same conversion for either kind of path, so which one this borrows
        // doesn't matter — `fileExists` answers for files and folders alike.
        fm.fileExists(atPath: extendPath(File(path.path)).nativePath)
    }

    public func inspectFile(at path: File) -> FileMetaData? {
        let filePath = extendPath(path).nativePath

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
    
    public func readFile(at path: File) -> GoDReadable? {
        let filePath = extendPath(path)
        guard let data = try? Data(contentsOf: filePath.url) else  {
            return nil
        }
        return GoDData(data: data, byteOrder: Environment.byteOrder)
    }
    
    public func moveFile(at path: File, to newPath: File, overwrite: Bool) throws {
        let fullPath = extendPath(path)
        let fullNewPath = extendPath(newPath)
        guard let parentFolder = fullNewPath.parentFolder else {
            throw FSTErrors.invalidPath(fullNewPath.path, .init())
        }
        if !itemExists(at: parentFolder) {
            try createFolder(at: parentFolder, overwrite: overwrite)
        }
        do {
            try fm.moveItem(atPath: fullPath.nativePath, toPath: fullNewPath.nativePath)
        } catch {
            throw FSTErrors.failedToMoveFile(fullPath, fullNewPath, .init())
        }
    }

    public func writeFile(_ file: GoDReadable, at path: File, overwrite: Bool) throws {
        let fullPath = extendPath(path)
        guard let parentFolder = fullPath.parentFolder else {
            throw FSTErrors.invalidPath(fullPath.path, .init())
        }
        if !itemExists(at: parentFolder) {
            try createFolder(at: parentFolder, overwrite: overwrite)
        }
        guard !itemExists(at: fullPath) || overwrite else {
            throw FSTErrors.itemExists(fullPath.path, .init())
        }
        do {
            try FileHandleAccess.write(file, to: fullPath.url)
        } catch let error as FSTErrors {
            throw error
        } catch {
            throw FSTErrors.failedToWriteFile(fullPath, .init())
        }
    }

    public func deleteFile(at path: File) throws {
        let fullPath = extendPath(path)
        do {
            try fm.removeItem(at: fullPath.url)
        } catch {
            throw FSTErrors.failedToDeleteFile(fullPath, .init())
        }
    }
    
    public func inspectFolder(at path: Folder) -> FolderMetaData? {
        let fullPath = extendPath(path)
        guard let paths = try? fm.contentsOfDirectory(atPath: fullPath.nativePath) else {
            return nil
        }
        let folder = path
        var files = [File]()
        var folders = [Folder]()
        
        paths.forEach { path in
            var isDirectory: ObjCBool = false
            _ = fm.fileExists(atPath: fullPath.file(path).nativePath, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                let subFolder = folder.folder(path)
                folders.append(subFolder)
            } else {
                let file = folder.file(path)
                files.append(file)
            }
        }
        
        let attributes = try? fm.attributesOfItem(atPath: fullPath.nativePath)
        let size: Int? = attributes?[.size] as? Int
        
        return .init(
            name: path.folderName,
            size: size,
            notes: nil,
            files: files,
            subFolders: folders
        )
    }
    
    public func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) throws {
        let fullPath = extendPath(path)
        let fullNewPath = extendPath(newPath)
        guard let parentFolder = fullNewPath.parentFolder else {
            throw FSTErrors.invalidPath(fullNewPath.path, .init())
        }
        if !itemExists(at: parentFolder) {
            try createFolder(at: parentFolder, overwrite: overwrite)
        }
        guard !itemExists(at: fullPath) || overwrite else {
            throw FSTErrors.itemExists(fullPath.path, .init())
        }
        do {
            try fm.moveItem(atPath: fullPath.nativePath, toPath: fullNewPath.nativePath)
        } catch {
            throw FSTErrors.failedToMoveFolder(fullPath, fullNewPath, .init())
        }
    }

    /// Creating a folder that already exists is a no-op, not an error —
    /// callers routinely ensure a folder exists before writing into it.
    public func createFolder(at path: Folder, overwrite: Bool) throws {
        let fullPath = extendPath(path)
        do {
            try fm.createDirectory(atPath: fullPath.nativePath, withIntermediateDirectories: true)
        } catch {
            throw FSTErrors.failedToCreateFolder(fullPath, .init())
        }
    }

    /// Deleting a folder that isn't there is a no-op, not an error.
    public func deleteFolder(at path: Folder) throws {
        let fullPath = extendPath(path)
        guard itemExists(at: fullPath) else { return }
        do {
            try fm.removeItem(atPath: fullPath.nativePath)
        } catch {
            throw FSTErrors.failedToDeleteFolder(fullPath, .init())
        }
    }
    
    public func pathForResource(_ filename: String, bundle: Bundle) -> File? {
        guard let url = bundle.url(forResource: filename.withoutExtension, withExtension: filename.fileExtension) else {
            return nil
        }
        return File(nativePath: url.path)
    }
    
    public var documents: Folder {
        Folder(
            nativePath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
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
        try? fm.setAttributes([FileAttributeKey.posixPermissions: 0o777], ofItemAtPath: fullPath.nativePath)
    }
    
    /// `FileSystemTree`'s path resolution: on disk that is `extendPath`,
    /// which is what every read and write here already goes through.
    public func resolvedPath(of file: File) -> File { extendPath(file) }
    public func resolvedPath(of folder: Folder) -> Folder { extendPath(folder) }

    public func extendPath(_ file: File) -> File {
        if Self.isRelative(file.path) {
            return currentDirectory.file(file.path)
        } else {
            return file
        }
    }

    public func extendPath(_ folder: Folder) -> Folder {
        if Self.isRelative(folder.path) {
            return currentDirectory.folder(folder.path)
        } else {
            return folder
        }
    }

    /// The spellings `File`/`Folder` accept for a path that isn't absolute.
    ///
    /// Bare `.` and `..` count. `Folder.init` strips a trailing separator,
    /// so `"./"` — which is plainly relative — *becomes* `"."`; leaving that
    /// out meant the same folder resolved against the running config's
    /// `rootFolder` when spelled `./x` and against the process's own working
    /// directory when spelled `.`.
    private static func isRelative(_ path: String) -> Bool {
        path == "." || path == ".." || path.startsWith("./") || path.startsWith("../")
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
        try writeFile(data, at: file, overwrite: overwrite)
    }
}

// MARK: - Sizing and readers

public extension FileSystem {

    func fileSize(at path: File) -> Int? {
        FileHandleAccess.fileSize(at: extendPath(path).url)
    }

    func resizeFile(at path: File, to length: Int) throws {
        guard length >= 0 else { throw FSTErrors.invalidPath(path.path, .init()) }
        // `resize` needs something to open, and growing a file that isn't
        // there yet is a reasonable way to ask for one.
        if !FileHandleAccess.isRegularFile(extendPath(path).url) {
            try writeFile(GoDData(byteOrder: .big), at: path, overwrite: false)
        }
        try FileHandleAccess.resize(extendPath(path).url, to: length)
    }
}
