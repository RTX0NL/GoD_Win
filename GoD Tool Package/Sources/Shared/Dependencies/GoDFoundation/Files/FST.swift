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
/// **Thread safety:** implementations are *not* synchronized. Concurrent
/// reads of an otherwise-idle tree are safe; any concurrent write — or a
/// read racing a write — is undefined. Callers that fan out (e.g. the FSYS
/// pack/unpack passes) must confine all mutation to a single thread.
///
/// **A read hands back a `GoDReadable`, not a buffer.** Whether those bytes
/// are already in memory, streamed off disk, or decrypted on demand is the
/// tree's business, not the caller's — `StreamedFileSystem` returns a source
/// that never materializes unless asked, and nothing downstream has to know.
/// Callers that genuinely need the whole file say so with `.allData`. Writes
/// take a `GoDReadable` for the same reason, so copying a disc image from one
/// tree to another never has to hold it.
/// Sizing and resizing stay here: they are file-system operations rather than
/// ways of interpreting bytes, and padding a disc image to capacity through
/// `readFile`/`writeFile` would move gigabytes to append zeros where
/// `resizeFile` is a single truncation.
public protocol FileSystemTree {
    func inspectFile(at path: File) -> FileMetaData?
    func readFile(at path: File) -> GoDReadable?
    func moveFile(at path: File, to newPath: File, overwrite: Bool) throws
    func writeFile(_ file: GoDReadable, at path: File, overwrite: Bool) throws
    func deleteFile(at path: File) throws

    func inspectFolder(at path: Folder) -> FolderMetaData?
    func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) throws
    func createFolder(at path: Folder, overwrite: Bool) throws
    func deleteFolder(at path: Folder) throws

    /// Size in bytes, without reading the contents.
    func fileSize(at path: File) -> Int?

    /// Sets the file's length, zero-filling when growing and discarding the
    /// tail when shrinking.
    func resizeFile(at path: File, to length: Int) throws

    /// Marks the file executable where the tree has a notion of permissions.
    func setExecutable(file: File)

    /// The path this tree will really read or write: a `./`- or `../`-
    /// prefixed path resolved against the tree's current directory.
    ///
    /// Only meaningful to a caller that has to hand the path to something
    /// outside the tree — launching a program is the case that needs it,
    /// since the child resolves a relative path against *its* working
    /// directory rather than the running config's `rootFolder`.
    func resolvedPath(of file: File) -> File
    func resolvedPath(of folder: Folder) -> Folder

    /// Files under `folder`, all the way down, and their bytes; nil if
    /// there is no such folder. See `FolderTally.swift`.
    func tally(of folder: Folder) -> FolderTally?
}

public extension FileSystemTree {
    /// Nothing to set on a tree without permissions — an in-memory file has
    /// no mode bits, and a file inside a disc image isn't run by the host.
    /// On the protocol rather than behind an `as? FileSystem` at the one call
    /// site that needs it, so asking is not a runtime type question.
    func setExecutable(file: File) {}

    /// A tree with no current directory resolves every path absolutely
    /// already, so there is nothing to extend.
    func resolvedPath(of file: File) -> File { file }
    func resolvedPath(of folder: Folder) -> Folder { folder }

    /// Grows the file to `length` with zeros, leaving it alone if already at
    /// least that long — the padding operation disc images want.
    func padFile(at path: File, toAtLeast length: Int) throws {
        guard let current = fileSize(at: path), current < length else { return }
        try resizeFile(at: path, to: length)
    }
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

    /// Encodes `item` as JSON and writes it.
    ///
    /// Named apart from `writeFile` on purpose. As an overload it sat next to
    /// the `GoDData` write and quietly won whenever the argument was a
    /// `GoDData?` — `Optional` is `Encodable`, so a forgotten unwrap compiled
    /// and wrote base64 into what should have been raw bytes.
    func writeJSON(_ item: Encodable, at path: File, overwrite: Bool) throws {
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
                guard let bytes = data.allData else { continue }
                try writeFile(bytes, at: newFile, overwrite: overwrite)

                if shouldTrackProgress {
                    sizeProcessed += bytes.length
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
