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
