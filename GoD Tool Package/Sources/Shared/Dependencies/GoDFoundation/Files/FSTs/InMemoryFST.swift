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

    public func readFile(at path: File) -> GoDData? {
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

    @discardableResult
    public func moveFile(at path: File, to newPath: File, overwrite: Bool) -> Bool {
        guard !itemExists(at: newPath) || overwrite else { return false }
        guard let node = fst[path.path], case .file = node else { return false }
        fst[newPath.path] = node
        fst[path.path] = nil
        if let parent = parentPath(of: path.path) {
            children[parent]?.remove(path.path)
        }
        registerChild(path: newPath.path)
        return true
    }

    @discardableResult
    public func writeFile(_ file: GoDData, at path: File, overwrite: Bool) -> Bool {
        guard !itemExists(at: path) || overwrite else { return false }
        fst[path.path] = .file(file)
        registerChild(path: path.path)
        return true
    }

    @discardableResult
    public func deleteFile(at path: File) -> Bool {
        fst[path.path] = nil
        if let parent = parentPath(of: path.path) {
            children[parent]?.remove(path.path)
        }
        return true
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
            files: files,
            subFolders: folders
        )
    }

    @discardableResult
    public func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) -> Bool {
        guard !itemExists(at: newPath) || overwrite else { return false }
        guard let node = fst[path.path], case .folder = node else { return false }

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
        return true
    }

    @discardableResult
    public func createFolder(at path: Folder, overwrite: Bool) -> Bool {
        guard !itemExists(at: path) || overwrite else { return false }
        fst[path.path] = .folder
        registerChild(path: path.path)
        return true
    }

    @discardableResult
    public func deleteFolder(at path: Folder) -> Bool {
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
        return true
    }
}
