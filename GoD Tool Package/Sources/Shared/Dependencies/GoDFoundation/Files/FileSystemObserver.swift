//
//  FileSystemObserver.swift
//
//  A way to watch, and to stop, the changes a `StreamedFileSystem` makes.
//
//  Operations are long synchronous loops that know nothing of the caller
//  that started them, but nearly all of them change the disk through the
//  tree they are handed. So the tree is the one place a caller can see what
//  a run writes, and can refuse its next change once the run should stop —
//  without threading a callback through every operation.
//

/// One change to a tree, named after the `FileSystemTree` call that makes
/// it, with paths as the tree resolves them.
public enum FileSystemChange: Equatable {
    case writeFile(File)
    case moveFile(from: File, to: File)
    case resizeFile(File)
    case deleteFile(File)
    case createFolder(Folder)
    case moveFolder(from: Folder, to: Folder)
    case deleteFolder(Folder)

    /// The file this change leaves new contents in, if any.
    public var writtenFile: File? {
        switch self {
        case .writeFile(let file), .resizeFile(let file): return file
        case .moveFile(_, let destination): return destination
        case .deleteFile, .createFolder, .moveFolder, .deleteFolder: return nil
        }
    }
}

extension FileSystemChange {
    /// `path` with its `.` components dropped and its `..` components
    /// applied. A tree resolves `./out.bin` to `<current>/./out.bin`, and an
    /// observer listing a run's files should see the same path however an
    /// operation spelled it. Relative paths are left alone: there is nothing
    /// to resolve them against.
    static func normalized(_ path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        var components: [Substring] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".": continue
            case "..": _ = components.popLast()
            default: components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }
}

public protocol FileSystemObserver {
    /// Called before each change. Throwing stops the change from being
    /// made, and the error is what the change throws.
    func willChange(_ change: FileSystemChange) throws
}
