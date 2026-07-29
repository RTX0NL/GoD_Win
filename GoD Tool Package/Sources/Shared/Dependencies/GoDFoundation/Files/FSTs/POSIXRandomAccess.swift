//
//  POSIXRandomAccess.swift
//
//  The random-access half of `FileSystemTree`, for trees whose files are real
//  files on disk.
//
//  `FileSystem` and `DiskBackedFST` differ only in how a logical path becomes
//  a URL — the singleton resolves against its current directory, the scratch
//  tree rebases onto its root. Everything after that is the same `FileHandle`
//  work, so it lives here once and both pass in their resolved URL.
//

import Foundation

enum POSIXRandomAccess {

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

    /// Reads `range`, clamped to the file's length. Nil only when the file
    /// isn't there — a range past the end yields a short (possibly empty)
    /// read rather than a failure.
    static func read(at url: URL, range: Range<Int>) -> GoDData? {
        guard let size = fileSize(at: url) else { return nil }
        let clamped = range.clamped(to: 0..<size)
        guard !clamped.isEmpty else { return GoDData(byteOrder: .big) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(clamped.lowerBound))
            return GoDData(data: try handle.read(upToCount: clamped.count) ?? Data(), byteOrder: .big)
        } catch {
            return nil
        }
    }

    static func append(_ data: GoDData, to url: URL) throws {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw FSTErrors.failedToWriteFile(File(url.path), .init())
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data.data)
        } catch {
            throw FSTErrors.failedToWriteFile(File(url.path), .init())
        }
    }

    static func write(_ data: GoDData, to url: URL, offset: Int) throws {
        // Seeking past the end and writing would leave a sparse hole. POSIX
        // says a hole reads back as zeros, so this isn't about correctness of
        // the bytes: resizing first makes the file's length deterministic even
        // if the write fails partway, and avoids handing a disc image sparse
        // extents where the caller wants the blocks actually allocated.
        if let size = fileSize(at: url), size < offset {
            try resize(url, to: offset)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw FSTErrors.failedToWriteFile(File(url.path), .init())
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: data.data)
        } catch {
            throw FSTErrors.failedToWriteFile(File(url.path), .init())
        }
    }

    /// `truncate` both grows (zero-filled) and shrinks, in constant memory —
    /// the reason random access is worth having on the protocol at all.
    static func resize(_ url: URL, to length: Int) throws {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw FSTErrors.failedToWriteFile(File(url.path), .init())
        }
        defer { try? handle.close() }
        do {
            try handle.truncate(atOffset: UInt64(length))
        } catch {
            throw FSTErrors.failedToWriteFile(File(url.path), .init())
        }
    }
}
