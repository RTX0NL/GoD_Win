//
//  FileHandleAccess.swift
//
//  The disk-touching half of `FileSystem`, plus the sizing `GoDStreamedData`
//  needs to open a file.
//
//  Everything here goes through Foundation, not raw syscalls, so it carries
//  Foundation's portability rather than POSIX's: `truncate(atOffset:)` reaches
//  `ftruncate` on Darwin and Linux and `SetEndOfFile` on Windows, and WASI
//  exposes the same operations if Foundation is wired to it. The one thing to
//  watch on swift-corelibs-foundation is `attributesOfItem`, whose value
//  boxing has differed from Darwin — a failed `as? Int` there reads as "file
//  missing" rather than as an error.
//

import Foundation

enum FileHandleAccess {

    static func fileSize(at url: URL) -> Int? {
        guard isRegularFile(url) else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int
    }

    static func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }

    /// `truncate` both grows (zero-filled) and shrinks, in constant memory —
    /// which is what makes padding a disc image to capacity cheap.
    static func resize(_ url: URL, to length: Int) throws {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw FSTErrors.failedToWriteFile(File(nativePath: url.path), .init())
        }
        defer { try? handle.close() }
        do {
            try handle.truncate(atOffset: UInt64(length))
        } catch {
            throw FSTErrors.failedToWriteFile(File(nativePath: url.path), .init())
        }
    }
}

extension FileHandleAccess {

    /// Size of each read/write hop when copying a source to disk. Big enough
    /// that the syscall overhead is noise against a 4.7 GB disc image, small
    /// enough that peak memory doesn't track the file.
    static let copyChunkSize = 8 << 20   // 8 MB

    /// Writes `source` to `url`, a chunk at a time.
    ///
    /// The point is that a `GoDStreamedData` never becomes a buffer: bytes go
    /// window by window from one file to the other, so copying a disc image
    /// into a project costs 8 MB rather than its own size. A `GoDData` source
    /// takes the same path — the slices it hands back are cheap, and one code
    /// path means the streamed case can't rot.
    static func write(_ source: GoDReadable, to url: URL) throws {
        let file = File(nativePath: url.path)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw FSTErrors.failedToWriteFile(file, .init())
        }
        defer { try? handle.close() }
        do {
            try handle.truncate(atOffset: 0)
            var offset = 0
            while offset < source.length {
                let count = min(copyChunkSize, source.length - offset)
                guard let chunk = source.read(atAddress: offset, length: count) else {
                    throw FSTErrors.failedToWriteFile(file, .init())
                }
                try handle.write(contentsOf: chunk.data)
                offset += count
            }
        } catch let error as FSTErrors {
            throw error
        } catch {
            throw FSTErrors.failedToWriteFile(file, .init())
        }
    }
}
