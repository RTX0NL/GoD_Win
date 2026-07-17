//
//  NKitGCConverter.swift
//
//  Minimal GameCube-only NKit decoder. Handles the common case where
//  an NKit file preserves the entire disc layout at original offsets
//  and only omits the trailing empty disc area (from the last file's
//  end to the full 1.4 GB disc size).
//
//  Validated on: Kirby Air Ride (Europe) .nkit.iso — 645 MB → 1.4 GB.
//
//  Limitation: doesn't handle NKit files with inline junk compaction
//  (where gap markers sit between files in the .nkit.iso body).
//  Detection logic: if every FST file fits at its declared disc offset
//  within the NKit file's byte range, we're in the simple-truncation
//  case. Otherwise we fail with `.inlineGapsNotSupported` and leave
//  the user to convert via NKit v1 for now.
//
//  What's restored:
//    - Bytes 0x00-0x1FF (disc header) verbatim from NKit file
//    - Bytes 0x200-0x21F (NKit metadata region) zeroed — the original
//      disc title string lived there and is lost on encode; restoring
//      it byte-identically would require a side-channel we don't have
//      yet. The resulting ISO still boots in Dolphin.
//    - Everything from 0x220 up to the NKit file's end copied verbatim
//    - From NKit-file-end to originalImageSize filled with PRNG junk
//      (or zeros if the junk stream can't be set up)
//
//  Reference:
//    Documentation/File Formats/Shared/NKIT - Lossless Shrunk ISO.md
//    Nanook/NKitv1 source
//

import Foundation
import GoDFoundation

public enum NKitGCConverter {

    public enum Error: Swift.Error, CustomStringConvertible {
        case notAnNKitGCImage
        case invalidFSTOffsets
        case inlineGapsNotSupported(firstOffendingDiscOffset: UInt64)

        public var description: String {
            switch self {
            case .notAnNKitGCImage:
                return "Input isn't an NKit GameCube image (missing NKIT magic or wrong disc magic)"
            case .invalidFSTOffsets:
                return "NKit file's FST pointers are invalid"
            case .inlineGapsNotSupported(let off):
                return "NKit file uses inline junk compaction; decoder only supports trailing-truncation images (first file past end-of-file at disc offset \(String(format: "0x%llX", off)))"
            }
        }
    }

    /// Decode an NKit GC image to a raw GameCube ISO.
    ///
    /// Returns a `GoDData` of length `originalImageSize` (from the
    /// NKit header). The output is not guaranteed to be byte-identical
    /// to the original Redump ISO — bytes 0x200-0x21F are zeroed
    /// (NKit overwrote them with its metadata) and the trailing junk
    /// is regenerated from the PRNG, which may differ if the original
    /// disc's junk didn't match the PRNG output for any reason. The
    /// resulting ISO is bootable and FST-parseable.
    public static func dump(nkit: GoDData) throws -> GoDData {
        nkit.setByteOrder(.big)
        let header = try NKitHeader(binary: nkit, platform: .gamecube)
        let originalSize = header.originalImageSize

        // Read disc header context: game ID, disc number.
        guard let gameIDBytes = nkit.read(atAddress: 0, length: 4)?.rawBytes else {
            throw Error.notAnNKitGCImage
        }
        let discNum: UInt8 = nkit.readSafely(atAddress: 0x06)
        let junkID: [UInt8] = {
            if let override = header.junkOverrideID, !override.isEmpty {
                return Array(override.utf8).prefix(4) + []
            }
            return gameIDBytes
        }()

        // Detect inline compaction by checking every FST file fits at
        // its disc offset within the NKit byte range.
        try validateNoInlineCompaction(nkit: nkit)

        // Allocate output and copy NKit bytes verbatim.
        let output = GoDData(byteOrder: .big)
        let nkitLen = nkit.length
        guard let nkitBytes = nkit.read(atAddress: 0, length: nkitLen)?.rawBytes else {
            throw Error.notAnNKitGCImage
        }
        for b in nkitBytes { output.append(b) }

        // Zero the NKit metadata region so the output looks like a
        // normal disc header (apart from the title string being gone).
        output.setByteOrder(.big)
        for i in 0x200..<0x220 {
            _ = output.write(UInt8(0), atAddress: i)
        }

        // Pad to originalImageSize with PRNG junk.
        if UInt64(nkitLen) < originalSize {
            let junk = JunkStream(gameID: Array(junkID), disc: discNum, length: originalSize)
            let tailStart = UInt64(nkitLen)
            let tailLength = Int(originalSize - tailStart)
            // Read the junk in chunks to avoid building an enormous
            // array in one go.
            let chunkSize = 0x10_0000  // 1 MiB
            var written = 0
            while written < tailLength {
                let take = min(chunkSize, tailLength - written)
                let bytes = junk.read(at: tailStart + UInt64(written), count: take)
                for b in bytes { output.append(b) }
                written += take
            }
        }

        return output
    }

    // MARK: - Validation

    private static func validateNoInlineCompaction(nkit: GoDData) throws {
        nkit.setByteOrder(.big)
        let fstOffset: UInt32 = nkit.readSafely(atAddress: 0x424)
        let fstSize: UInt32 = nkit.readSafely(atAddress: 0x428)
        guard fstOffset > 0, fstSize >= 12,
              Int(fstOffset) + Int(fstSize) <= nkit.length else {
            throw Error.invalidFSTOffsets
        }

        // Root entry at fstOffset: bytes 8..12 hold the total entry
        // count.
        let entryCount: UInt32 = nkit.readSafely(atAddress: Int(fstOffset) + 8)
        guard entryCount > 0,
              Int(fstOffset) + Int(entryCount) * 12 <= Int(fstOffset) + Int(fstSize) else {
            throw Error.invalidFSTOffsets
        }

        // Walk file entries (skip dirs). For each file, ensure its
        // (discOffset + size) fits within the NKit byte range.
        for i in 1..<Int(entryCount) {
            let entryOff = Int(fstOffset) + i * 12
            let flag: UInt8 = nkit.readSafely(atAddress: entryOff)
            guard flag == 0 else { continue }  // directory
            let discOff: UInt32 = nkit.readSafely(atAddress: entryOff + 4)
            let size: UInt32 = nkit.readSafely(atAddress: entryOff + 8)
            let end = UInt64(discOff) + UInt64(size)
            if end > UInt64(nkit.length) {
                throw Error.inlineGapsNotSupported(firstOffendingDiscOffset: UInt64(discOff))
            }
        }
    }
}
