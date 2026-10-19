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

    /// Told about every change before it is made, and able to refuse it.
    private let observer: FileSystemObserver?

    /// Streams from an on-disk file system.
    public init(_ fileSystem: FileSystem = .shared, observer: FileSystemObserver? = nil) {
        self.backing = fileSystem
        self.disk = fileSystem
        self.observer = observer
    }

    /// Wraps a tree with no files behind it — an in-memory tree in a test, or
    /// a pipeline stage. Reads materialize; nothing streams, and nothing
    /// pretends to.
    public init(materializing tree: FileSystemTree, observer: FileSystemObserver? = nil) {
        self.backing = tree
        self.disk = nil
        self.observer = observer
    }

    /// Moves the backing file system's current directory.
    ///
    /// Only the on-disk tree has such a concept — in-memory trees resolve
    /// every path absolutely — so this is a no-op otherwise. Having it here
    /// spares callers the `as? FileSystem` they used to need to ask.
    public func changeDirectory(_ folder: Folder) {
        disk?.changeDirectory(folder)
    }

    /// Runs `body` with the backing file system's current directory at
    /// `folder` — or, with no folder, at the directory the process started
    /// in — and restores the previous one afterwards. A relative `folder`
    /// resolves against the launch directory too, never against whatever an
    /// earlier caller left behind. A no-op wrapper for in-memory trees.
    public func withCurrentDirectory<T>(_ folder: Folder?, _ body: () throws -> T) rethrows -> T {
        guard let disk else { return try body() }
        let target: Folder
        if let folder, folder.path.hasPrefix("/") {
            target = folder
        } else if let folder {
            target = disk.launchDirectory.folder(folder.path)
        } else {
            target = disk.launchDirectory
        }
        return try disk.withCurrentDirectory(target, body)
    }

    /// Resolution is the backing tree's, not this wrapper's — the same
    /// current directory `changeDirectory` above moves.
    public func resolvedPath(of file: File) -> File { backing.resolvedPath(of: file) }
    public func resolvedPath(of folder: Folder) -> Folder { backing.resolvedPath(of: folder) }

    /// A path as the observer is told it: resolved, with `.` and `..` gone.
    private func observed(_ file: File) -> File {
        File(FileSystemChange.normalized(resolvedPath(of: file).path))
    }

    private func observed(_ folder: Folder) -> Folder {
        Folder(FileSystemChange.normalized(resolvedPath(of: folder).path))
    }

    // MARK: - FileSystemTree
    //
    // Everything else is the backing tree's job. Nothing is reinterpreted on
    // the way through: this is the same file system, read differently. Each
    // change is put to the observer first, with its paths resolved, so a
    // refused change never reaches the backing tree.

    public func inspectFile(at path: File) -> FileMetaData? {
        backing.inspectFile(at: path)
    }

    /// Opens the file rather than reading it.
    ///
    /// This is the whole type: a caller writes `readFile` and gets back
    /// something that reads windows off disk instead of a buffer, without
    /// asking for it or knowing it happened. A tree with no real file behind
    /// it falls back to the backing read, which is the same answer by a more
    /// expensive route.
    public func readFile(at path: File) -> GoDReadable? {
        guard let disk else { return backing.readFile(at: path) }
        if let streamed = try? GoDStreamedData(file: disk.extendPath(path)) {
            return streamed
        }
        return backing.readFile(at: path)
    }

    public func moveFile(at path: File, to newPath: File, overwrite: Bool) throws {
        try observer?.willChange(.moveFile(from: observed(path), to: observed(newPath)))
        try backing.moveFile(at: path, to: newPath, overwrite: overwrite)
    }

    public func writeFile(_ file: GoDReadable, at path: File, overwrite: Bool) throws {
        try observer?.willChange(.writeFile(observed(path)))
        try backing.writeFile(file, at: path, overwrite: overwrite)
    }

    public func deleteFile(at path: File) throws {
        try observer?.willChange(.deleteFile(observed(path)))
        try backing.deleteFile(at: path)
    }

    public func inspectFolder(at path: Folder) -> FolderMetaData? {
        backing.inspectFolder(at: path)
    }

    public func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) throws {
        try observer?.willChange(.moveFolder(from: observed(path), to: observed(newPath)))
        try backing.moveFolder(at: path, to: newPath, overwrite: overwrite)
    }

    public func createFolder(at path: Folder, overwrite: Bool) throws {
        try observer?.willChange(.createFolder(observed(path)))
        try backing.createFolder(at: path, overwrite: overwrite)
    }

    public func deleteFolder(at path: Folder) throws {
        try observer?.willChange(.deleteFolder(observed(path)))
        try backing.deleteFolder(at: path)
    }

    public func fileSize(at path: File) -> Int? {
        backing.fileSize(at: path)
    }

    public func resizeFile(at path: File, to length: Int) throws {
        try observer?.willChange(.resizeFile(observed(path)))
        try backing.resizeFile(at: path, to: length)
    }

    public func setExecutable(file: File) {
        backing.setExecutable(file: file)
    }

    public func tally(of folder: Folder) -> FolderTally? {
        backing.tally(of: folder)
    }
}
