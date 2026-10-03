//
//  PatchTestReadables.swift
//
//  Readables the patch tests need and the production types deliberately do
//  not provide.
//

import Foundation
@testable import GoDFoundation

/// A readable that will only ever hand out windows — `allData` stays nil, as it
/// does for a disc image or a decrypted partition view. Anything built on this
/// is proved not to have quietly asked for a whole buffer.
final class WindowOnlyReadable: GoDReadable {
    let bytes: [UInt8]
    let byteOrder: ByteOrder = .big

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var length: Int { bytes.count }

    func read(atAddress address: UInt, length readLength: UInt) -> GoDData? {
        let start = Int(address)
        let count = Int(readLength)
        guard start >= 0, count >= 0, start + count <= bytes.count else { return nil }
        return GoDData(byteStream: Array(bytes[start ..< start + count]), byteOrder: byteOrder)
    }
}

/// A readable whose bytes are computed, so a test can span offsets no test
/// should allocate — IPS's 16 MiB ceiling is 16 MiB of nothing in particular.
final class GeneratedReadable: GoDReadable {
    let length: Int
    let byteOrder: ByteOrder = .big
    private let byte: (Int) -> UInt8

    init(length: Int, byte: @escaping (Int) -> UInt8) {
        self.length = length
        self.byte = byte
    }

    /// Constant `fill`, with `overrides` at the offsets given.
    convenience init(length: Int, fill: UInt8, overrides: [Int: UInt8] = [:]) {
        self.init(length: length) { overrides[$0] ?? fill }
    }

    func read(atAddress address: UInt, length readLength: UInt) -> GoDData? {
        let start = Int(address)
        let count = Int(readLength)
        guard start >= 0, count >= 0, start + count <= length else { return nil }
        return GoDData(byteStream: (start ..< start + count).map(byte), byteOrder: byteOrder)
    }
}

extension GoDReadable {
    /// Every byte of a readable, a window at a time.
    ///
    /// The tests' own rather than the production helper of the same shape, and
    /// deliberately so: these files are committed alongside the codecs they
    /// exercise, and a test that reaches for a method added somewhere else
    /// cannot be compiled from the commit that needs it. Named apart from
    /// anything on `GoDReadable` so that neither shadows the other.
    func allBytes(windowSize: Int = 1 << 20) throws -> GoDData {
        let out = GoDData(data: Data(count: length), byteOrder: byteOrder)
        var offset = 0
        while offset < length {
            let count = min(max(1, windowSize), length - offset)
            guard let window = read(atAddress: offset, length: count), window.length == count else {
                throw PatchTestReadError.readFailed(offset: offset, length: count, total: length)
            }
            out.write(window, atAddress: UInt(offset))
            offset += count
        }
        return out
    }
}

/// The tests' own, for the same reason `allBytes` is: an error type that lives
/// elsewhere is an error type this file cannot be compiled without.
enum PatchTestReadError: Error, CustomStringConvertible {
    case readFailed(offset: Int, length: Int, total: Int)

    var description: String {
        switch self {
        case let .readFailed(offset, length, total):
            return "failed to read \(length) bytes at \(offset) of a \(total)-byte source"
        }
    }
}
