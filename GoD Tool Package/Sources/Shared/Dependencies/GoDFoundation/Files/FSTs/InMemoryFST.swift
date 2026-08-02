//
//  InMemoryFST.swift
//  
//
//  Created by Stars Momodu on 02/06/2024.
//

import Foundation

public class InMemoryFST: FileSystemTree {
    private enum Node {
        case file(GoDData)
        case folder
    }

    private var fst = [String: Node]()
    private var children = [String: Set<String>]() // folder path → direct child paths

    public init() {}

    private func registerChild(path: String) {
        guard path != "/" else { return }
        // Walk up from the path and register each segment as a child of its parent
        var current = path
        while let slashIndex = current.lastIndex(of: "/") {
            if slashIndex == current.startIndex {
                // Parent is root "/"
                children["/", default: []].insert(current)
                break
            }
            let parentPath = String(current[current.startIndex..<slashIndex])
            children[parentPath, default: []].insert(current)
            current = parentPath
        }
    }

    public func inspectFile(at path: File) -> FileMetaData? {
        guard let node = fst[path.path],
              case .file(let data) = node else {
            return nil
        }
        return .init(
            filename: path.fileName,
            filetype: path.fileType,
            filesize: data.length,
            notes: nil
        )
    }

    public func readFile(at path: File) -> GoDReadable? {
        guard let node = fst[path.path],
              case .file(let data) = node else {
            return nil
        }
        return data
    }

    private func parentPath(of path: String) -> String? {
        guard let slashIndex = path.lastIndex(of: "/"), slashIndex != path.startIndex else {
            return path == "/" ? nil : "/"
        }
        return String(path[path.startIndex..<slashIndex])
    }

    public func moveFile(at path: File, to newPath: File, overwrite: Bool) throws {
        guard !itemExists(at: newPath) || overwrite else {
            throw FSTErrors.itemExists(newPath.path, .init())
        }
        guard let node = fst[path.path], case .file = node else {
            throw FSTErrors.fileNotFound(path, .init())
        }
        fst[newPath.path] = node
        fst[path.path] = nil
        if let parent = parentPath(of: path.path) {
            children[parent]?.remove(path.path)
        }
        registerChild(path: newPath.path)
    }

    public func writeFile(_ file: GoDData, at path: File, overwrite: Bool) throws {
        guard !itemExists(at: path) || overwrite else {
            throw FSTErrors.itemExists(path.path, .init())
        }
        fst[path.path] = .file(file)
        registerChild(path: path.path)
    }

    /// Deleting a file that isn't there is a no-op, not an error.
    public func deleteFile(at path: File) throws {
        fst[path.path] = nil
        if let parent = parentPath(of: path.path) {
            children[parent]?.remove(path.path)
        }
    }

    public func inspectFolder(at path: Folder) -> FolderMetaData? {
        guard let directChildren = children[path.path], !directChildren.isEmpty else {
            // Fall back: folder exists as explicit node but has no children
            if case .folder = fst[path.path] {
                return .init(name: path.folderName, size: 0, notes: nil, files: [], subFolders: [])
            }
            return nil
        }

        var totalSize = 0
        var files = [File]()
        var folders = [Folder]()

        for childPath in directChildren {
            if let node = fst[childPath] {
                switch node {
                case .file(let data):
                    totalSize += data.length
                    files.append(File(childPath))
                case .folder:
                    folders.append(Folder(childPath))
                }
            } else if children[childPath] != nil {
                // Implicit folder (not explicitly created but has children)
                folders.append(Folder(childPath))
            }
        }

        // Also compute deep size for files in subfolders
        func deepSize(_ folderPath: String) -> Int {
            guard let kids = children[folderPath] else { return 0 }
            var size = 0
            for kid in kids {
                if let node = fst[kid], case .file(let data) = node {
                    size += data.length
                } else {
                    size += deepSize(kid)
                }
            }
            return size
        }
        let deepTotal = totalSize + folders.reduce(0) { $0 + deepSize($1.path) }

        return .init(
            name: path.folderName,
            size: deepTotal,
            notes: nil,
            // Sorted: `children` is a Set, so iteration order varies between
            // process runs (Swift seeds hashing per-process). An operation
            // that builds output from a listing would otherwise differ run to
            // run, and this tree has to agree with the on-disk ones, which
            // sort too.
            files: files.sorted(),
            subFolders: folders.sorted()
        )
    }

    public func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) throws {
        guard !itemExists(at: newPath) || overwrite else {
            throw FSTErrors.itemExists(newPath.path, .init())
        }
        guard let node = fst[path.path], case .folder = node else {
            throw FSTErrors.folderNotFound(path, .init())
        }

        let oldPrefix = path.path
        let newPrefix = newPath.path

        // Rekey a descendant path from the old folder prefix to the new one.
        // Handles the folder itself (suffix == "") and every nested entry.
        func rekey(_ old: String) -> String {
            newPrefix + String(old.dropFirst(oldPrefix.count))
        }

        // Detach the moved folder from its old parent.
        if let parent = parentPath(of: oldPrefix) {
            children[parent]?.remove(oldPrefix)
        }

        // Move the folder node itself.
        fst[newPrefix] = node
        fst[oldPrefix] = nil

        // Rekey every descendant file/folder node so its stored path reflects
        // the new location (a shallow rename left stale old-prefixed keys).
        let descendantNodeKeys = fst.keys.filter { $0.hasPrefix(oldPrefix + "/") }
        for key in descendantNodeKeys {
            fst[rekey(key)] = fst[key]
            fst[key] = nil
        }

        // Rekey the children index: the folder's own entry plus every nested
        // folder, remapping both the keys and the child paths they contain.
        let childIndexKeys = children.keys.filter { $0 == oldPrefix || $0.hasPrefix(oldPrefix + "/") }
        for key in childIndexKeys {
            if let set = children[key] {
                children[rekey(key)] = Set(set.map(rekey))
            }
            children[key] = nil
        }

        // Re-register the moved folder under its new parent.
        registerChild(path: newPrefix)
    }

    /// Creating a folder that already exists is a no-op, not an error —
    /// callers routinely ensure a folder exists before writing into it.
    /// A *file* already occupying the path is an error, not something to
    /// silently replace.
    public func createFolder(at path: Folder, overwrite: Bool) throws {
        if case .file = fst[path.path] {
            throw FSTErrors.itemExists(path.path, .init())
        }
        fst[path.path] = .folder
        registerChild(path: path.path)
    }

    /// Deleting a folder that isn't there is a no-op, not an error.
    public func deleteFolder(at path: Folder) throws {
        // Remove all descendants
        func removeRecursive(_ folderPath: String) {
            if let kids = children[folderPath] {
                for kid in kids {
                    fst[kid] = nil
                    removeRecursive(kid)
                }
                children[folderPath] = nil
            }
        }
        fst[path.path] = nil
        removeRecursive(path.path)
        if let parent = parentPath(of: path.path) {
            children[parent]?.remove(path.path)
        }
    }
}

// MARK: - Sizing
//
// Held in memory already, so these are direct edits rather than real IO. Note
// they rely on `GoDData` being a reference type: the object a read hands back
// *is* the stored one, so mutating it is what makes a resize take effect.
//
// `reader(at:)` is inherited from the protocol extension — a whole-file read
// is already the cheapest thing this tree can do.

public extension InMemoryFST {

    func fileSize(at path: File) -> Int? {
        readFile(at: path)?.length
    }

    func resizeFile(at path: File, to length: Int) throws {
        guard length >= 0 else {
            throw FSTErrors.invalidPath(path.path, .init())
        }
        // The stored object, not a copy: an in-place pad/delete is what makes
        // the resize visible to the next reader.
        guard let existing = readFile(at: path)?.allData else {
            try writeFile(GoDData(length: length, byteOrder: .big), at: path, overwrite: false)
            return
        }
        if existing.length < length {
            existing.pad(by: length - existing.length)
        } else if existing.length > length {
            existing.delete(start: length, count: existing.length - length)
        }
    }
}
