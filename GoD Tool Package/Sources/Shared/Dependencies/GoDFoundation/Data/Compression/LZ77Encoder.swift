//
//  LZ77Encoder.swift
//
//  The shared LZ77 layer behind Nintendo's compressed stream formats.
//
//  Yaz0 and Yay0 make identical compression *decisions* — same 0x1000-byte
//  window, same 3...0x111 match lengths — and differ only in how the
//  resulting operations are packed into a file. So the search lives here
//  once, emitting a format-neutral `[LZ77Token]`, and each codec is reduced
//  to serializing that list its own way. The CX family (`0x10`/`0x11`) uses
//  the same shape with different bounds, so it can reuse this too.
//
//  This file holds the vocabulary the LZ77-based codecs share: the token,
//  the encoder, and the stream errors their decoders throw.
//

import Foundation

/// One compression decision: emit a byte verbatim, or repeat bytes already
/// produced.
///
/// `distance` counts backwards from the current output position, so 1 is
/// "the byte just written". A match may reach past the current position —
/// `distance: 1, length: 20` is a 20-byte run — because every decoder in
/// this family copies one byte at a time.
public enum LZ77Token: Equatable {
    case literal(UInt8)
    case match(distance: Int, length: Int)
}

/// Errors thrown while decoding an LZ77-family stream. Shared because the
/// failure modes are the same for every codec in the family; `format` says
/// which one was reading.
public enum LZ77StreamError: Error, CustomStringConvertible {
    case wrongMagic(format: String, found: [UInt8])
    case headerTruncated(format: String, length: Int)
    case unexpectedEndOfInput(format: String, position: Int, length: Int)
    case backReferenceOutOfRange(format: String, distance: Int, outputPosition: Int)
    case truncatedOutput(format: String, produced: Int, expected: Int)

    public var description: String {
        switch self {
        case let .wrongMagic(format, found):
            let hex = found.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "\(format): wrong magic — expected the format's signature, found bytes \(hex)"
        case let .headerTruncated(format, length):
            return "\(format): stream is \(length) bytes, too short to hold a header"
        case let .unexpectedEndOfInput(format, position, length):
            return "\(format): unexpected end of input — tried to read byte \(position) of a \(length)-byte stream"
        case let .backReferenceOutOfRange(format, distance, outputPosition):
            return "\(format): back-reference of \(distance) bytes at output position \(outputPosition) points before the start of the output"
        case let .truncatedOutput(format, produced, expected):
            return "\(format): decompressed \(produced) bytes but the header declared \(expected) — stream is truncated or corrupt"
        }
    }
}

/// Reads a big-endian 32-bit word out of a raw byte buffer.
///
/// These stream formats are fixed big-endian regardless of what byte order
/// the surrounding `GoDData` was tagged with, so their headers are assembled
/// by hand rather than through the byte-order-sensitive read helpers.
/// The caller guarantees `offset + 4 <= bytes.count`.
internal func bigEndianUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    UInt32(bytes[offset]) << 24
        | UInt32(bytes[offset + 1]) << 16
        | UInt32(bytes[offset + 2]) << 8
        | UInt32(bytes[offset + 3])
}

/// Appends `value` as a big-endian 32-bit word.
internal func appendBigEndianUInt32(_ value: UInt32, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
}

/// Decode-side helpers shared by the LZ77-family codecs.
internal enum LZ77Decoder {

    /// Replays a back-reference onto the end of `output`.
    ///
    /// Copies one byte at a time on purpose: a match is allowed to reach
    /// past the current position (`distance: 1` is a run), so each copied
    /// byte may be one this same call just produced.
    static func appendBackReference(
        distance: Int,
        length: Int,
        to output: inout [UInt8],
        format: String
    ) throws {
        guard distance > 0, distance <= output.count else {
            throw LZ77StreamError.backReferenceOutOfRange(
                format: format,
                distance: distance,
                outputPosition: output.count
            )
        }
        let start = output.count - distance
        for offset in 0 ..< length {
            let byte = output[start + offset]
            output.append(byte)
        }
    }
}

/// Finds the back-references a Nintendo LZ77 stream is built from.
///
/// The search reproduces the semantics of the widely-mirrored reference
/// encoder (`simpleEnc`/`nintendoEnc`): longest match wins, the furthest
/// back wins a tie, and a two-byte match is not worth encoding so it
/// degrades to a literal. Two deliberate departures, both for speed:
///
/// - Candidates come from a 3-byte hash chain rather than a linear scan of
///   the whole window. Since a match shorter than three bytes is never
///   emitted, the candidate set is the same one the linear scan would have
///   found a winner in.
/// - Match length is measured up to `maxMatchLength` instead of to the end
///   of the input. The reference compares *unclamped* lengths and only
///   clamps when writing, so where several candidates all run past the
///   maximum it may pick a different one than we do. Both streams decode to
///   the same bytes and are the same size; only the distance bytes differ.
///   This is the one place output can diverge from that encoder, and it is
///   what keeps long runs from costing O(n²).
public struct LZ77Encoder {

    public struct Configuration {
        /// Furthest back a match may reach.
        public let windowSize: Int
        /// Shortest match worth encoding. Must be at least 3 — the match
        /// finder hashes three bytes to pick candidates.
        public let minMatchLength: Int
        /// Longest match the container can express.
        public let maxMatchLength: Int
        /// Whether to try Nintendo's one-byte deferral: if emitting a
        /// literal here lets the *next* position take a match at least two
        /// bytes longer, take the literal.
        public let usesDeferredMatching: Bool
        /// Ceiling on candidates examined per position. Bounds the worst
        /// case on pathological input; the default matches the window, so
        /// no candidate in range is skipped.
        public let maxChainLength: Int

        public init(
            windowSize: Int = 0x1000,
            minMatchLength: Int = 3,
            maxMatchLength: Int = 0x111,
            usesDeferredMatching: Bool = true,
            maxChainLength: Int = 0x1000
        ) {
            if minMatchLength < 3 {
                assertionFailure("LZ77 match finder hashes 3 bytes; a minimum match below 3 would miss candidates")
            }
            if windowSize < 1 || maxMatchLength < minMatchLength || maxChainLength < 1 {
                assertionFailure("LZ77 encoder configuration is invalid")
            }
            self.windowSize = windowSize
            self.minMatchLength = minMatchLength
            self.maxMatchLength = maxMatchLength
            self.usesDeferredMatching = usesDeferredMatching
            self.maxChainLength = maxChainLength
        }

        /// The bounds Yaz0 and Yay0 share: a 4 KB window and matches of
        /// 3...273 bytes, with the deferral heuristic enabled.
        public static let nintendo = Configuration()
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .nintendo) {
        self.configuration = configuration
    }

    /// Reduces `bytes` to the ordered operations that reproduce it.
    public func tokenize(_ bytes: [UInt8]) -> [LZ77Token] {
        let count = bytes.count
        guard count > 0 else { return [] }
        guard count > configuration.minMatchLength else {
            return bytes.map { .literal($0) }
        }

        var finder = LZ77MatchFinder(bytes: bytes, configuration: configuration)
        var tokens: [LZ77Token] = []
        tokens.reserveCapacity(count / 2 + 1)

        var position = 0
        // Set when the deferral heuristic has already decided what the next
        // position emits, so that position doesn't search again.
        var deferredMatch: (distance: Int, length: Int)?

        while position < count {
            if let match = deferredMatch {
                tokens.append(.match(distance: match.distance, length: match.length))
                position += match.length
                deferredMatch = nil
                continue
            }

            // Every position below the search point has to be in the chains,
            // including ones stepped over by a match — the reference scans
            // the whole window, not just the positions it stopped on.
            finder.index(upTo: position)
            let best = finder.longestMatch(at: position)

            if best.length < configuration.minMatchLength {
                tokens.append(.literal(bytes[position]))
                position += 1
                continue
            }

            if configuration.usesDeferredMatching, position + 1 < count {
                finder.index(upTo: position + 1)
                let next = finder.longestMatch(at: position + 1)
                if next.length >= best.length + 2 {
                    tokens.append(.literal(bytes[position]))
                    deferredMatch = next
                    position += 1
                    continue
                }
            }

            tokens.append(.match(distance: best.distance, length: best.length))
            position += best.length
        }

        return tokens
    }
}

// MARK: - Match finder

/// Hash-chain match search over a byte buffer.
///
/// `head` maps a 3-byte hash to the most recent position carrying it and
/// `prev` chains each position to the previous one with the same hash, so a
/// search walks candidates newest-first. Kept as a `struct` with stored
/// arrays rather than closures over local state so the hot loop indexes
/// arrays directly.
private struct LZ77MatchFinder {

    private static let hashBits = 16

    private let bytes: [UInt8]
    private let windowSize: Int
    private let minMatchLength: Int
    private let maxMatchLength: Int
    private let maxChainLength: Int

    private var head: [Int32]
    private var prev: [Int32]
    /// Positions below this are in the chains.
    private var indexedUpTo = 0

    init(bytes: [UInt8], configuration: LZ77Encoder.Configuration) {
        self.bytes = bytes
        self.windowSize = configuration.windowSize
        self.minMatchLength = configuration.minMatchLength
        self.maxMatchLength = configuration.maxMatchLength
        self.maxChainLength = configuration.maxChainLength
        self.head = [Int32](repeating: -1, count: 1 << Self.hashBits)
        self.prev = [Int32](repeating: -1, count: max(bytes.count, 1))
    }

    private func hash(at position: Int) -> Int {
        let key = UInt32(bytes[position]) << 16
            | UInt32(bytes[position + 1]) << 8
            | UInt32(bytes[position + 2])
        return Int((key &* 2_654_435_761) >> UInt32(32 - Self.hashBits))
    }

    /// Adds every position below `limit` to the chains. Monotonic — calling
    /// it with a limit already passed does nothing.
    mutating func index(upTo limit: Int) {
        let last = min(limit, bytes.count - 2)
        while indexedUpTo < last {
            let bucket = hash(at: indexedUpTo)
            prev[indexedUpTo] = head[bucket]
            head[bucket] = Int32(indexedUpTo)
            indexedUpTo += 1
        }
    }

    /// The best back-reference for `position`, or length 0 if none is worth
    /// encoding. Requires every position below `position` to be indexed.
    func longestMatch(at position: Int) -> (distance: Int, length: Int) {
        let count = bytes.count
        let remaining = count - position
        guard remaining >= minMatchLength, position + 2 < count else {
            return (0, 0)
        }

        let limit = min(maxMatchLength, remaining)
        let windowStart = max(0, position - windowSize)

        var bestLength = 0
        var bestDistance = 0
        var candidate = Int(head[hash(at: position)])
        var chainLeft = maxChainLength

        while candidate >= windowStart, chainLeft > 0 {
            chainLeft -= 1

            // To even tie the incumbent a candidate has to match the byte
            // sitting at the end of it — cheaper to check than to start
            // comparing from the front.
            if bestLength > 0,
               bytes[candidate + bestLength - 1] != bytes[position + bestLength - 1] {
                candidate = Int(prev[candidate])
                continue
            }

            var length = 0
            while length < limit, bytes[candidate + length] == bytes[position + length] {
                length += 1
            }

            // `>=` rather than `>`: the chain runs newest-first, so letting
            // equal-length candidates overwrite leaves the furthest back
            // holding the slot, which is what the reference encoder picks.
            if length >= minMatchLength, length >= bestLength {
                bestLength = length
                bestDistance = position - candidate
            }

            // Stop only at the container's ceiling, where nothing longer
            // can be encoded anyway. Near the end of the input `limit` is
            // the bytes remaining instead, and there the walk continues so
            // the furthest-back tie-break still applies.
            if bestLength == maxMatchLength { break }
            candidate = Int(prev[candidate])
        }

        return (bestDistance, bestLength)
    }
}
