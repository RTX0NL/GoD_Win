//
//  GoDCompositeData.swift
//
//  A readable assembled from pieces placed at offsets, with the gaps between
//  them reading as zeroes.
//
//  This is the lazy form of the pattern that recurs wherever this codebase
//  builds a container: make a `GoDData(length: 0)`, `write` each part at its
//  offset, and let the buffer grow. That is fine for a save file and ruinous
//  for a disc — a Wii rebuild composes a partition out of a ticket, a TMD, a
//  cert chain, an H3 table and four gigabytes of encrypted data, and the
//  imperative version holds every byte of it.
//
//  Composing readables instead means the whole thing costs its pieces'
//  overheads, and `FileHandleAccess.write` — which pulls a `GoDReadable` in
//  8 MB windows — streams it straight to disk.
//
//  Pieces must not overlap. The imperative code this replaces never wrote
//  one part over another; requiring it means a read can binary-search for the
//  piece it needs instead of replaying every write in order, and a caller
//  that did want to overlay something finds out at construction.
//

import Foundation

public final class GoDCompositeData: GoDReadable {

    /// One placed part of the whole.
    public struct Piece {
        public let offset: Int
        public let source: GoDReadable
        /// A label used only in errors, so an overlap names the parts that
        /// collided rather than their offsets alone.
        public let name: String

        public init(offset: Int, source: GoDReadable, name: String = "piece") {
            self.offset = offset
            self.source = source
            self.name = name
        }

        /// Place a small computed part — a header, a table of scalars — without
        /// the caller wrapping it first.
        public init(offset: Int, bytes: [UInt8], byteOrder: ByteOrder = .big, name: String = "piece") {
            self.init(
                offset: offset,
                source: GoDData(byteStream: bytes, byteOrder: byteOrder),
                name: name
            )
        }

        var range: Range<Int> { offset..<(offset + source.length) }
    }

    public enum CompositeError: Error, CustomStringConvertible {
        case overlappingPieces(String, String, at: Int)
        case negativeOffset(String, Int)
        case declaredLengthTooSmall(declared: Int, needed: Int)

        public var description: String {
            switch self {
            case let .overlappingPieces(first, second, offset):
                return "Composite pieces \"\(first)\" and \"\(second)\" overlap at offset \(offset)"
            case let .negativeOffset(name, offset):
                return "Composite piece \"\(name)\" is placed at negative offset \(offset)"
            case let .declaredLengthTooSmall(declared, needed):
                return "Composite declares \(declared) bytes but its pieces reach \(needed)"
            }
        }
    }

    public let byteOrder: ByteOrder
    public let length: Int

    /// Sorted by offset, so a read can binary-search to its first piece.
    private let pieces: [Piece]

    /// - Parameters:
    ///   - length: total size. Defaults to where the last piece ends; pass a
    ///     larger value to leave a zero-filled tail, which is how a disc
    ///     image reserves space past its content.
    public init(pieces: [Piece], length: Int? = nil, byteOrder: ByteOrder = .big) throws {
        for piece in pieces where piece.offset < 0 {
            throw CompositeError.negativeOffset(piece.name, piece.offset)
        }
        let sorted = pieces.filter { $0.source.length > 0 }.sorted { $0.offset < $1.offset }
        for (previous, next) in zip(sorted, sorted.dropFirst()) where previous.range.upperBound > next.offset {
            throw CompositeError.overlappingPieces(previous.name, next.name, at: next.offset)
        }
        let needed = sorted.last?.range.upperBound ?? 0
        if let length {
            guard length >= needed else {
                throw CompositeError.declaredLengthTooSmall(declared: length, needed: needed)
            }
            self.length = length
        } else {
            self.length = needed
        }
        self.pieces = sorted
        self.byteOrder = byteOrder
    }

    public func read(atAddress address: UInt, length readLength: UInt) -> GoDData? {
        let start = Int(address)
        let end = start + Int(readLength)
        guard start >= 0, end <= self.length, readLength > 0 else { return nil }

        // Starts zeroed: the gaps between pieces, and any declared tail past
        // the last one, read as zeroes.
        var out = [UInt8](repeating: 0, count: Int(readLength))
        var index = firstPieceIndex(reaching: start)
        while index < pieces.count, pieces[index].offset < end {
            let piece = pieces[index]
            let copyStart = max(piece.offset, start)
            let copyEnd = min(piece.range.upperBound, end)
            if copyEnd > copyStart {
                guard let chunk = piece.source.read(
                    atAddress: copyStart - piece.offset,
                    length: copyEnd - copyStart
                ) else {
                    return nil
                }
                out.replaceSubrange((copyStart - start)..<(copyEnd - start), with: chunk.rawBytes)
            }
            index += 1
        }
        return GoDData(byteStream: out, byteOrder: byteOrder)
    }

    /// Index of the first piece whose end is past `offset`.
    private func firstPieceIndex(reaching offset: Int) -> Int {
        var low = 0
        var high = pieces.count
        while low < high {
            let middle = (low + high) / 2
            if pieces[middle].range.upperBound <= offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
