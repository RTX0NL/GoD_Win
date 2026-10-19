//
//  FolderTally.swift
//
//  How many files a folder holds, all the way down, and how many bytes.
//
//  A tree can always work this out from `inspectFolder` and `fileSize`, and
//  that is the default. On a Windows disk it is far too slow: Foundation
//  asks about each file on its own, so a 22,000-file project took 45 s.
//  Windows hands out every entry's size in the directory listing itself, so
//  `FileSystem` reads it from there (0.3 s for the same project).
//

#if os(Windows)
import WinSDK
#endif

public struct FolderTally: Equatable {
    public var files: Int
    public var bytes: Int

    public init(files: Int, bytes: Int) {
        self.files = files
        self.bytes = bytes
    }

    /// The tally by `inspectFolder` and `fileSize`, which every tree has.
    static func walk(_ folder: Folder, in tree: FileSystemTree) -> FolderTally? {
        guard let contents = tree.inspectFolder(at: folder) else { return nil }
        let own = FolderTally(
            files: contents.files.count,
            bytes: contents.files.reduce(0) { $0 + (tree.fileSize(at: $1) ?? 0) }
        )
        return contents.subFolders.reduce(own) { total, subFolder in
            guard let sub = walk(subFolder, in: tree) else { return total }
            return FolderTally(files: total.files + sub.files, bytes: total.bytes + sub.bytes)
        }
    }
}

public extension FileSystemTree {
    func tally(of folder: Folder) -> FolderTally? {
        FolderTally.walk(folder, in: self)
    }
}

extension FileSystem {
    public func tally(of folder: Folder) -> FolderTally? {
        #if os(Windows)
        return Self.windowsTally(extendPath(folder).nativePath)
        #else
        return FolderTally.walk(folder, in: self)
        #endif
    }

    #if os(Windows)
    /// One `FindFirstFileExW` listing per folder; sizes come with the
    /// entries. Reparse points (junctions, symlinked folders) are counted as
    /// nothing rather than followed, so a link can't loop the walk.
    private static func windowsTally(_ nativePath: String) -> FolderTally? {
        var entry = WIN32_FIND_DATAW()
        let handle = (nativePath + "\\*").withCString(encodedAs: UTF16.self) { pattern in
            FindFirstFileExW(pattern, FindExInfoBasic, &entry, FindExSearchNameMatch, nil, DWORD(FIND_FIRST_EX_LARGE_FETCH))
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        defer { FindClose(handle) }

        var tally = FolderTally(files: 0, bytes: 0)
        repeat {
            let name = withUnsafeBytes(of: entry.cFileName) { raw in
                String(decodingCString: raw.baseAddress!.assumingMemoryBound(to: WCHAR.self), as: UTF16.self)
            }
            let attributes = entry.dwFileAttributes
            if attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0 {
                guard name != ".", name != "..", attributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) == 0,
                      let sub = windowsTally(nativePath + "\\" + name) else { continue }
                tally.files += sub.files
                tally.bytes += sub.bytes
            } else {
                tally.files += 1
                tally.bytes += Int(entry.nFileSizeHigh) << 32 | Int(entry.nFileSizeLow)
            }
        } while FindNextFileW(handle, &entry)
        return tally
    }
    #endif
}
