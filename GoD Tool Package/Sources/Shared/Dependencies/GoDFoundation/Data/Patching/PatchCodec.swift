//
//  PatchCodec.swift
//
//  The shape every binary patch format has: make a patch from two files,
//  and apply one to a file.
//
//  Here beside the compression codecs rather than in a game engine, for the
//  same reason those are: a patch format is a pure byte-level algorithm with
//  no game knowledge. The operations that use it (`createPatch` /
//  `applyPatch`) name a format and nothing else.
//
//  Both directions deal in `GoDReadable`, never buffers. A patch applies to
//  whole files — the thing this tool holds most of are disc images — so the
//  result of applying one is a view that computes the bytes a reader asks
//  for, and `FileHandleAccess.write` streams it to disk in windows.
//

import Foundation

/// Which way round a patch is being applied.
///
/// Meaningful because some formats are symmetric: a UPS patch stores the XOR
/// of the two files, so the same patch that turns A into B turns B back into
/// A. A format that cannot do that throws `PatchError.directionNotSupported`.
public enum PatchDirection: String, Codable, CaseIterable {
    /// Source → target: the direction the patch was created in.
    case forward
    /// Target → source: undoing the patch.
    case reverse

    public var other: PatchDirection {
        self == .forward ? .reverse : .forward
    }
}

/// What a codec hands back from `apply`: the patched bytes, which way round
/// it went, and what the result is supposed to check out as.
public struct PatchApplication {
    /// The patched file. A view over the input and the patch — reading it is
    /// what applies the patch.
    public let output: GoDReadable

    /// The direction actually used. Worth reporting even when the caller
    /// asked for one, since `nil` means the codec chose.
    public let direction: PatchDirection

    /// The checksum the patch declares for this output, or nil where the
    /// format carries none. CRC-32 is what this family of formats stores;
    /// `PatchCodec.validate(output:of:)` is what interprets it, so a caller
    /// never has to know the algorithm.
    public let expectedOutputChecksum: UInt32?

    /// Anything the caller should be told but that didn't stop the work — an
    /// input checksum mismatch let past by `validateInput: false`, say.
    public let warnings: [String]

    public init(
        output: GoDReadable,
        direction: PatchDirection,
        expectedOutputChecksum: UInt32?,
        warnings: [String] = []
    ) {
        self.output = output
        self.direction = direction
        self.expectedOutputChecksum = expectedOutputChecksum
        self.warnings = warnings
    }
}

public protocol PatchCodec {
    /// The bytes at offset 0 that identify this format's patches.
    static var magic: [UInt8] { get }
    /// The conventional spelling, for logs and errors.
    static var formatName: String { get }

    /// A readable over the patch that turns `source` into `target`.
    func createPatch(source: GoDReadable, target: GoDReadable) throws -> GoDReadable

    /// Apply `patch` to `input`.
    ///
    /// - Parameters:
    ///   - direction: nil lets the codec decide from the patch's own
    ///     checksums and sizes, which is what a caller holding an unknown
    ///     file wants. Naming one pins it.
    ///   - validateInput: when false, an input that doesn't match what the
    ///     patch says it was patched from is reported as a warning instead of
    ///     an error. The *output* check is not optional — see `validate`.
    func apply(
        patch: GoDReadable,
        to input: GoDReadable,
        direction: PatchDirection?,
        validateInput: Bool
    ) throws -> PatchApplication

    /// Check a written output against what the patch said it would be.
    ///
    /// Separate from `apply` because the output has to be read back from
    /// where it landed: a view that was never written is not evidence that
    /// the bytes on disk are right.
    func validate(output: GoDReadable, of application: PatchApplication) throws
}

public enum PatchError: Error, CustomStringConvertible {
    case patchTooShort(format: String, length: Int, minimum: Int)
    case wrongMagic(format: String, found: [UInt8])
    case malformedPatch(format: String, reason: String, offset: Int)
    case patchChecksumMismatch(format: String, stored: UInt32, computed: UInt32)
    case inputChecksumMismatch(format: String, direction: PatchDirection, stored: UInt32, computed: UInt32)
    case inputSizeMismatch(format: String, direction: PatchDirection, expected: Int, found: Int)
    case inputMatchesNeitherSide(format: String, inputSize: Int, sourceSize: Int, targetSize: Int)
    case ambiguousDirection(format: String, size: Int)
    case directionNotSupported(format: String, direction: PatchDirection)
    case outputChecksumMismatch(format: String, expected: UInt32, computed: UInt32)
    case readFailed(format: String, offset: Int, length: Int)
    case offsetBeyondFormatLimit(format: String, offset: Int, limit: Int)
    case unsupportedFeature(format: String, feature: String)
    case windowChecksumMismatch(format: String, window: Int, expected: UInt32, computed: UInt32)

    public var description: String {
        switch self {
        case let .patchTooShort(format, length, minimum):
            return "\(format): a patch is at least \(minimum) bytes (magic, two sizes and the footer); this one is \(length)"
        case let .wrongMagic(format, found):
            let hex = found.map { String(format: "%02X", $0) }.joined(separator: " ")
            let text = String(decoding: found)
            return "\(format): expected the magic at offset 0, found [\(hex)]\(text.map { " (\"\($0)\")" } ?? "")"
        case let .malformedPatch(format, reason, offset):
            return "\(format): malformed patch at offset \(offset) — \(reason)"
        case let .patchChecksumMismatch(format, stored, computed):
            return String(
                format: "%@: the patch file is corrupt — its footer says its own CRC-32 is %08X, but the bytes compute to %08X",
                format, stored, computed
            )
        case let .inputChecksumMismatch(format, direction, stored, computed):
            let side = direction == .forward ? "source" : "target"
            return String(
                format: "%@: the input is not the %@ this patch was made from — the patch says CRC-32 %08X, the input is %08X. "
                + "Use the file the patch was made against, or set ignoreChecksums to patch it anyway.",
                format, side, stored, computed
            )
        case let .inputSizeMismatch(format, direction, expected, found):
            let side = direction == .forward ? "source" : "target"
            return "\(format): applying \(direction.rawValue) needs a \(expected)-byte \(side) file; the input is \(found) bytes"
        case let .inputMatchesNeitherSide(format, inputSize, sourceSize, targetSize):
            return "\(format): the input is \(inputSize) bytes, and this patch runs between a \(sourceSize)-byte "
            + "source and a \(targetSize)-byte target — it is neither, so there is no direction to apply it in"
        case let .ambiguousDirection(format, size):
            return "\(format): the patch's source and target are both \(size) bytes and the input matches neither "
            + "checksum, so which way round to apply it cannot be derived — name `direction` explicitly"
        case let .directionNotSupported(format, direction):
            return "\(format): patches cannot be applied \(direction.rawValue)"
        case let .outputChecksumMismatch(format, expected, computed):
            return String(
                format: "%@: the patched file is wrong — the patch says the result should be CRC-32 %08X, what was written is %08X",
                format, expected, computed
            )
        case let .readFailed(format, offset, length):
            return "\(format): failed to read \(length) bytes at offset \(offset)"
        case let .windowChecksumMismatch(format, window, expected, computed):
            return String(
                format: "%@: the window of the output at offset %d decoded to Adler-32 %08X, but the patch says "
                + "%08X — this patch was made from a different file, or is corrupt",
                format, window, computed, expected
            )
        case let .unsupportedFeature(format, feature):
            return "\(format): this patch uses \(feature), which GODDESS does not implement"
        case let .offsetBeyondFormatLimit(format, offset, limit):
            return "\(format): the files differ at offset \(offset), past the \(limit) this format can address — "
            + "it cannot express this patch; use a format with wider offsets"
        }
    }
}

private extension String {
    /// The magic as text, when it is printable — a wrong magic is nearly
    /// always another format's, and `"BPS1"` says more than four hex bytes.
    init?(decoding bytes: [UInt8]) {
        guard !bytes.isEmpty, bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return nil }
        self = String(bytes.map { Character(UnicodeScalar($0)) })
    }
}
