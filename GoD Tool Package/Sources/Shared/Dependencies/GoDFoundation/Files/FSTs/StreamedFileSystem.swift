//
//  StreamedFileSystem.swift
//
//  A file system whose reads come back as windows onto a file rather than as
//  bytes in memory.
//
//  This exists for one shape of work: an operation that starts by opening a
//  disc image. A GameCube ISO is 1.4 GB and a Wii ISO 4.7 GB, of which a dump
//  reads the boot header, the FST, and then one member at a time. Reading that
//  through `readFile` costs the whole image in memory before the first byte is
//  parsed.
//
//  It is a separate tree rather than a capability bolted onto `FileSystemTree`
//  deliberately. Streaming is not something every tree can do — an in-memory
//  tree has no file to open, and a `GamecubeISO` is itself a parse of one — so
//  putting it on the shared protocol would mean every conformer claiming an
//  ability most of them can only fake. Here, an operation that needs streaming
//  says so in its signature, and the caller picks the tree that provides it.
//
//  **Why the streamed read is `streamFile` and not `readFile`:**
//  `FileSystemTree.readFile` returns `GoDData`, which is bytes you hold. Swift
//  matches protocol witnesses exactly, so this type cannot narrow that return
//  to a streamed type, and widening the protocol's read to `GoDReadable` would
//  hand all ~245 whole-file call sites a value they can't take `rawBytes` from.
//  A `GoDData` subclass backed by a file would be worse still: `data` is a
//  stored property that `rawBytes`, `length` and every mutation method read
//  directly, so a streamed instance would silently report itself as empty.
//  `readFile` therefore keeps meaning "give me the bytes"; `streamFile` means
//  "open it".
//

import Foundation

public final class StreamedFileSystem: FileSystemTree {

    /// Where writes, metadata and folder operations go.
    private let backing: FileSystemTree

    /// The same tree, when it is really files on disk — the only case that can
    /// be streamed. Nil means `streamFile` falls back to a whole-file read.
    private let disk: FileSystem?

    /// Streams from an on-disk file system.
    public init(_ fileSystem: FileSystem = .shared) {
        self.backing = fileSystem
        self.disk = fileSystem
    }

    /// Wraps a tree with no files behind it — an in-memory tree in a test, or
    /// a pipeline stage. Reads materialise; nothing streams, and nothing
    /// pretends to.
    public init(materialising tree: FileSystemTree) {
        self.backing = tree
        self.disk = nil
    }

    /// Opens `path` for windowed reading.
    ///
    /// The result is a `GoDReadable` because the caller shouldn't care which
    /// it got: a `GoDStreamedData` when the file is really on disk, the
    /// materialised bytes otherwise. Both answer `read(atAddress:length:)`
    /// identically, including returning nil past the end.
    public func streamFile(at path: File) -> GoDReadable? {
        guard let disk else { return backing.readFile(at: path) }
        if let streamed = try? GoDStreamedData(file: disk.extendPath(path)) {
            return streamed
        }
        // The file may not exist, or may not be openable; either way the
        // whole-file read gives the same answer the caller would have got.
        return backing.readFile(at: path)
    }

    /// Moves the backing file system's current directory.
    ///
    /// Only the on-disk tree has such a concept — in-memory trees resolve
    /// every path absolutely — so this is a no-op otherwise. Having it here
    /// spares callers the `as? FileSystem` they used to need to ask.
    public func changeDirectory(_ folder: Folder) {
        disk?.changeDirectory(folder)
    }

    // MARK: - FileSystemTree
    //
    // Everything else is the backing tree's job. Nothing is reinterpreted on
    // the way through: this is the same file system, read differently.

    public func inspectFile(at path: File) -> FileMetaData? {
        backing.inspectFile(at: path)
    }

    public func readFile(at path: File) -> GoDData? {
        backing.readFile(at: path)
    }

    public func moveFile(at path: File, to newPath: File, overwrite: Bool) throws {
        try backing.moveFile(at: path, to: newPath, overwrite: overwrite)
    }

    public func writeFile(_ file: GoDData, at path: File, overwrite: Bool) throws {
        try backing.writeFile(file, at: path, overwrite: overwrite)
    }

    public func deleteFile(at path: File) throws {
        try backing.deleteFile(at: path)
    }

    public func inspectFolder(at path: Folder) -> FolderMetaData? {
        backing.inspectFolder(at: path)
    }

    public func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) throws {
        try backing.moveFolder(at: path, to: newPath, overwrite: overwrite)
    }

    public func createFolder(at path: Folder, overwrite: Bool) throws {
        try backing.createFolder(at: path, overwrite: overwrite)
    }

    public func deleteFolder(at path: Folder) throws {
        try backing.deleteFolder(at: path)
    }

    public func fileSize(at path: File) -> Int? {
        backing.fileSize(at: path)
    }

    public func resizeFile(at path: File, to length: Int) throws {
        try backing.resizeFile(at: path, to: length)
    }
}
