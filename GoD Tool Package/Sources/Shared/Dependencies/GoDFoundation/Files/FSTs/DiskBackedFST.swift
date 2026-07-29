//
//  DiskBackedFST.swift
//
//  A `FileSystemTree` whose contents live in a directory on disk instead of in
//  memory, and which supports range-addressed reads and writes.
//
//  `InMemoryFST` is the scratch tree the dump operations build up before
//  importing into the project: every extracted file is held as a `GoDData` for
//  the whole run. That is fine for a handful of archives and untenable for a
//  disc — unpacking a GameCube ISO holds the entire user section in RAM, and a
//  Wii disc is several times larger again.
//
//  This is a drop-in for that role: same protocol, same semantics, but each
//  logical path is a real file under a scratch root, so memory stays flat and
//  the operating system's page cache does the work. Its range-addressed reads
//  and writes — part of the `FileSystemTree` contract — also let whole-disc
//  operations (padding to capacity, reading one file out of an image) stop
//  materialising everything.
//
//  The scratch directory is deliberately a plain mirror of the logical tree
//  rather than an opaque store, so a failed run can be inspected by hand.
//

import Foundation

public final class DiskBackedFST: FileSystemTree {

    /// Directory every logical path is resolved inside.
    public let root: Folder

    /// Whether `deinit` should delete `root`. True for `temporary()` trees,
    /// false when the caller supplied a directory it wants to keep.
    private let ownsRoot: Bool
    private let fm = FileManager.default

    /// Uses `root` as the backing directory, creating it if needed. The
    /// directory is left in place when this tree goes away.
    public init(root: Folder) throws {
        self.root = root
        self.ownsRoot = false
        try fm.createDirectory(atPath: root.nativePath, withIntermediateDirectories: true)
    }

    private init(temporaryRoot: Folder) {
        self.root = temporaryRoot
        self.ownsRoot = true
    }

    /// A tree in a fresh directory under the system temporary directory,
    /// deleted when the tree is released.
    public static func temporary(name: String = "GODDESS") throws -> DiskBackedFST {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return DiskBackedFST(temporaryRoot: Folder(nativePath: base.path))
    }

    deinit {
        if ownsRoot {
            try? fm.removeItem(atPath: root.nativePath)
        }
    }

    /// Deletes the backing directory. Safe to call more than once.
    public func removeBackingStore() throws {
        guard fm.fileExists(atPath: root.nativePath) else { return }
        do {
            try fm.removeItem(atPath: root.nativePath)
        } catch {
            throw FSTErrors.failedToDeleteFolder(root, .init())
        }
    }

    // MARK: - Path resolution

    /// Maps a logical path onto the backing directory.
    ///
    /// Components are normalised and `..` is resolved *before* joining, so a
    /// logical path can never address anything outside `root` — the tree is a
    /// sandbox, and a path assembled from engine config or archive metadata
    /// shouldn't be able to escape it.
    private func resolve(_ path: String) -> URL {
        var components: [String] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(String(component))
            }
        }
        var url = URL(fileURLWithPath: root.nativePath, isDirectory: true)
        for component in components {
            url.appendPathComponent(component)
        }
        return url
    }

    fileprivate func url(_ file: File) -> URL { resolve(file.path) }
    private func url(_ folder: Folder) -> URL { resolve(folder.path) }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return isDir.boolValue
    }

    private func isRegularFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return !isDir.boolValue
    }

    /// Creates the parent directory of a file that's about to be written.
    private func ensureParentDirectory(of url: URL) throws {
        let parent = url.deletingLastPathComponent()
        guard !fm.fileExists(atPath: parent.path) else { return }
        do {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw FSTErrors.failedToCreateFolder(Folder(parent.path), .init())
        }
    }

    // MARK: - Files

    public func inspectFile(at path: File) -> FileMetaData? {
        let url = url(path)
        guard isRegularFile(url) else { return nil }
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? Int
        return .init(
            filename: path.fileName,
            filetype: path.fileType,
            filesize: size,
            notes: nil
        )
    }

    public func readFile(at path: File) -> GoDData? {
        let url = url(path)
        guard isRegularFile(url), let data = try? Data(contentsOf: url) else { return nil }
        return GoDData(data: data, byteOrder: .big)
    }

    public func writeFile(_ file: GoDData, at path: File, overwrite: Bool) throws {
        let url = url(path)
        if isDirectory(url) {
            throw FSTErrors.itemExists(path.path, .init())
        }
        guard !isRegularFile(url) || overwrite else {
            throw FSTErrors.itemExists(path.path, .init())
        }
        try ensureParentDirectory(of: url)
        do {
            try file.data.write(to: url)
        } catch {
            throw FSTErrors.failedToWriteFile(path, .init())
        }
    }

    public func moveFile(at path: File, to newPath: File, overwrite: Bool) throws {
        let from = url(path)
        let to = url(newPath)
        guard isRegularFile(from) else {
            throw FSTErrors.fileNotFound(path, .init())
        }
        if fm.fileExists(atPath: to.path) {
            guard overwrite else { throw FSTErrors.itemExists(newPath.path, .init()) }
            try? fm.removeItem(at: to)
        }
        try ensureParentDirectory(of: to)
        do {
            try fm.moveItem(at: from, to: to)
        } catch {
            throw FSTErrors.failedToMoveFile(path, newPath, .init())
        }
    }

    /// Deleting a file that isn't there is a no-op, matching `InMemoryFST`.
    public func deleteFile(at path: File) throws {
        let url = url(path)
        guard isRegularFile(url) else { return }
        do {
            try fm.removeItem(at: url)
        } catch {
            throw FSTErrors.failedToDeleteFile(path, .init())
        }
    }

    // MARK: - Folders

    public func inspectFolder(at path: Folder) -> FolderMetaData? {
        let url = url(path)
        guard isDirectory(url) else { return nil }
        guard let names = try? fm.contentsOfDirectory(atPath: url.path) else { return nil }

        var files = [File]()
        var folders = [Folder]()
        var size = 0
        // Sorted so a listing is stable across runs and platforms;
        // `contentsOfDirectory` makes no ordering promise, and callers that
        // build output from a listing would otherwise vary run to run.
        for name in names.sorted() {
            let child = url.appendingPathComponent(name)
            if isDirectory(child) {
                folders.append(path.folder(name))
            } else {
                files.append(path.file(name))
                size += ((try? fm.attributesOfItem(atPath: child.path)[.size]) as? Int) ?? 0
            }
        }

        // Deep size, to match `InMemoryFST`, which reports the whole subtree.
        for folder in folders {
            size += inspectFolder(at: folder)?.size ?? 0
        }

        return .init(
            name: path.folderName,
            size: size,
            notes: nil,
            files: files,
            subFolders: folders
        )
    }

    /// Creating a folder that already exists is a no-op; a *file* occupying
    /// the path is an error rather than something to silently replace.
    public func createFolder(at path: Folder, overwrite: Bool) throws {
        let url = url(path)
        if isRegularFile(url) {
            throw FSTErrors.itemExists(path.path, .init())
        }
        guard !isDirectory(url) else { return }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw FSTErrors.failedToCreateFolder(path, .init())
        }
    }

    public func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) throws {
        let from = url(path)
        let to = url(newPath)
        guard isDirectory(from) else {
            throw FSTErrors.folderNotFound(path, .init())
        }
        if fm.fileExists(atPath: to.path) {
            guard overwrite else { throw FSTErrors.itemExists(newPath.path, .init()) }
            try? fm.removeItem(at: to)
        }
        try ensureParentDirectory(of: to)
        do {
            try fm.moveItem(at: from, to: to)
        } catch {
            throw FSTErrors.failedToMoveFolder(path, newPath, .init())
        }
    }

    /// Deleting a folder that isn't there is a no-op, matching `InMemoryFST`.
    public func deleteFolder(at path: Folder) throws {
        let url = url(path)
        guard isDirectory(url) else { return }
        do {
            try fm.removeItem(at: url)
        } catch {
            throw FSTErrors.failedToDeleteFolder(path, .init())
        }
    }
}

// MARK: - Random access
//
// Resolution is the only part that differs from any other on-disk tree, so the
// FileHandle work is shared with `FileSystem` via `FileHandleAccess`.

public extension DiskBackedFST {

    func fileSize(at path: File) -> Int? {
        FileHandleAccess.fileSize(at: url(path))
    }

    func readFile(at path: File, range: Range<Int>) -> GoDData? {
        FileHandleAccess.read(at: url(path), range: range)
    }

    func appendToFile(_ data: GoDData, at path: File) throws {
        let target = url(path)
        guard FileHandleAccess.isRegularFile(target) else {
            return try writeFile(data, at: path, overwrite: false)
        }
        try FileHandleAccess.append(data, to: target)
    }

    func writeFile(_ data: GoDData, at path: File, offset: Int) throws {
        guard offset >= 0 else { throw FSTErrors.invalidPath(path.path, .init()) }
        try ensureFileExists(at: path)
        try FileHandleAccess.write(data, to: url(path), offset: offset)
    }

    func resizeFile(at path: File, to length: Int) throws {
        guard length >= 0 else { throw FSTErrors.invalidPath(path.path, .init()) }
        try ensureFileExists(at: path)
        try FileHandleAccess.resize(url(path), to: length)
    }

    /// Range writes address a file that may not exist yet; create an empty one
    /// so the offset/resize below has something to act on.
    private func ensureFileExists(at path: File) throws {
        guard !FileHandleAccess.isRegularFile(url(path)) else { return }
        try writeFile(GoDData(byteOrder: .big), at: path, overwrite: false)
    }
}
