//
//  RandomAccessFileSystemTree.swift
//
//  Range-addressed access for trees that can do better than whole-file IO.
//
//  `FileSystemTree` deals in whole files: `readFile` hands back every byte and
//  `writeFile` takes every byte. That is the right shape for the formats — a
//  `.msg` or a `.gtx` is parsed as a unit — but it is the wrong shape for disc
//  images. Padding an ISO to capacity currently reads the whole image into
//  memory, appends zeros and writes it all back; for a Wii disc that is
//  gigabytes of traffic to do what `truncate` does in constant memory.
//
//  This is a *refinement*, not a replacement. Everything keeps working through
//  the whole-file API; callers that can exploit range access check for this
//  protocol and fall back when it isn't available, so no implementation is
//  forced to provide it.
//

import Foundation

public protocol RandomAccessFileSystemTree: FileSystemTree {
    /// Size in bytes, without reading the contents.
    func fileSize(at path: File) -> Int?

    /// Reads `range` of the file. Returns nil if the file is missing; a range
    /// extending past the end is clamped, so a short read is not an error.
    func readFile(at path: File, range: Range<Int>) -> GoDData?

    /// Appends to the end of an existing file, creating it if absent.
    func appendToFile(_ data: GoDData, at path: File) throws

    /// Writes `data` at `offset`, growing the file (zero-filling any gap) if
    /// it ends before `offset`.
    func writeFile(_ data: GoDData, at path: File, offset: Int) throws

    /// Sets the file's length, zero-filling when growing and discarding the
    /// tail when shrinking.
    func resizeFile(at path: File, to length: Int) throws
}

public extension RandomAccessFileSystemTree {
    /// Grows the file to `length` with zeros, leaving it alone if already at
    /// least that long. This is the padding operation disc images want.
    func padFile(at path: File, toAtLeast length: Int) throws {
        guard let current = fileSize(at: path), current < length else { return }
        try resizeFile(at: path, to: length)
    }
}

/// Helpers for callers that want range access when the tree offers it and
/// whole-file IO otherwise, without duplicating the fallback each time.
public extension FileSystemTree {

    /// Pads a file with zeros up to `length`.
    ///
    /// Uses a constant-memory resize when the tree supports random access;
    /// otherwise falls back to read-append-write, which is what every tree
    /// used to do unconditionally.
    func padFile(at path: File, toAtLeast length: Int) throws {
        if let randomAccess = self as? RandomAccessFileSystemTree {
            try randomAccess.padFile(at: path, toAtLeast: length)
            return
        }
        guard let data = readFile(at: path) else {
            throw FSTErrors.fileNotFound(path, .init())
        }
        let remaining = length - data.length
        guard remaining > 0 else { return }
        data.append(GoDData(length: remaining, byteOrder: data.byteOrder))
        try writeFile(data, at: path, overwrite: true)
    }

    /// Reads a byte range, falling back to reading the whole file and slicing.
    func readFile(at path: File, range: Range<Int>) -> GoDData? {
        if let randomAccess = self as? RandomAccessFileSystemTree {
            return randomAccess.readFile(at: path, range: range)
        }
        guard let data = readFile(at: path) else { return nil }
        let clamped = range.clamped(to: 0..<data.length)
        guard !clamped.isEmpty else { return GoDData(byteOrder: data.byteOrder) }
        return data.read(atAddress: clamped.lowerBound, length: clamped.count)
    }

    /// Size of a file without necessarily reading it.
    func fileSize(at path: File) -> Int? {
        if let randomAccess = self as? RandomAccessFileSystemTree {
            return randomAccess.fileSize(at: path)
        }
        return inspectFile(at: path)?.filesize
    }
}
