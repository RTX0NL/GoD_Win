//
//  FileHandleAccess.swift
//
//  The disk-touching half of `FileSystem`, plus the sizing `GoDStreamedData`
//  needs to open a file.
//
//  Everything here goes through Foundation, not raw syscalls, so it carries
//  Foundation's portability rather than POSIX's: `truncate(atOffset:)` reaches
//  `ftruncate` on Darwin and Linux and `SetEndOfFile` on Windows, and WASI
//  exposes the same operations if Foundation is wired to it.
//
//  The one place that isn't uniform is measuring a file, so `fileSize` has two
//  implementations — see it for why.
//

import Foundation

enum FileHandleAccess {

    /// Size of the file in bytes, or nil if there isn't a regular file there.
    ///
    /// Two implementations because the portable-looking one isn't.
    /// `attributesOfItem` returns `[FileAttributeKey: Any]`, and Darwin and
    /// swift-corelibs-foundation have not always boxed the `.size` value the
    /// same way; where the `as? Int` fails, this returns nil, and every caller
    /// reads nil as "no file". `GoDStreamedData.init` would then throw
    /// *file not found* for a file that plainly exists — a wrong answer
    /// wearing the wrong error.
    ///
    /// Seeking to the end asks the file itself and returns a `UInt64`, so
    /// there is no boxing to disagree about. It costs an open, which is why
    /// Darwin — where the attribute lookup is known-good — keeps it.
    static func fileSize(at url: URL) -> Int? {
        // `attributesOfItem` describes a symlink itself — 75 bytes of path —
        // where `fileExists` and `FileHandle` both follow it. Resolve first so
        // an image reached through a link is measured as the image; without
        // this, setup on a linked `.wbfs` "succeeded" around the link text.
        let url = url.resolvingSymlinksInPath()
        guard isRegularFile(url) else { return nil }
        #if canImport(Darwin)
        return attributeFileSize(at: url)
        #else
        return seekFileSize(at: url)
        #endif
    }

    /// Cheap: no file descriptor. Depends on how Foundation boxes the value.
    /// Not `private` so the tests can hold it against `seekFileSize`.
    static func attributeFileSize(at url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int
    }

    /// Costs an open, answers in a concrete type. `Int(exactly:)` rather than
    /// `Int(_:)` so a file larger than `Int.max` — impossible on a 64-bit
    /// host, reachable on wasm32 where `Int` is 32 bits — reports "can't
    /// measure this" instead of trapping.
    static func seekFileSize(at url: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        return Int(exactly: end)
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
                // Each window is a fresh `Data` (and, through a view, whatever
                // it read to produce it). Without a pool those live until the
                // loop ends, so the "streamed" write peaks at the file's size
                // rather than at one window — measured at 613 MB for a 199 MB
                // patch-and-verify, 228 MB with pools.
                try autoreleasepool {
                    guard let chunk = source.read(atAddress: offset, length: count) else {
                        throw FSTErrors.failedToWriteFile(file, .init())
                    }
                    try handle.write(contentsOf: chunk.data)
                }
                offset += count
            }
        } catch let error as FSTErrors {
            throw error
        } catch {
            throw FSTErrors.failedToWriteFile(file, .init())
        }
    }
}
