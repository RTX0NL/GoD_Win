//
//  THPFile.swift
//
//  Genius Sonority packs Nintendo THP videos as a paired THH (0x2C,
//  header) + THD (0x2E, frame data) in FSYS archives. The logical
//  "THP" file is the concatenation of the two plus two pointer
//  fixups — after which the bytes are a standard Nintendo THP that any
//  off-the-shelf player (Dolphin, a THP-aware ffmpeg/vgmstream build,
//  jhpthp) can open.
//
//  Editable artifact bundle:
//    <name>.thp — standard playable THP (THH + THD joined, with the
//                 0x28/0x2C pointers re-based onto the combined file).
//
//  No JSON sidecar: THP is fully self-describing binary, so everything
//  needed to rebuild is already in the `.thp`. `thhSize` is recovered
//  from the combined file's 0x28 field at parse time.
//
//  Roundtrip is bit-identical: the concatenation and pointer math
//  are invertible (thhSize is recoverable from the combined THP's
//  `firstFrameOffset` at 0x28, since the split form uses 0-based
//  offsets into THD).
//
//  Pointer fixup semantics (from Documentation/File Formats/Shared/
//  THP - Video Format.md):
//
//    - Split form stores offsets at 0x28 (first frame) and 0x2C
//      (last frame) relative to the *start of THD*, not the combined
//      file. For this layout the first frame lives at the very start
//      of THD, so split[0x28] is 0 in all samples observed.
//    - Combined form needs those same offsets re-based to the joined
//      file, so we add `thhSize` on dump and subtract it on build.
//

import Foundation
import GoDFoundation

public struct THPFile: FileFormat {
    public static let formatName = "thp"

    public var name: String = "thp"

    /// The combined THP bytes — THH header and THD frame stream joined,
    /// pointer offsets already re-based. This is the canonical form we
    /// store and edit against; splitting happens at serialize time.
    public var combined: GoDData
    /// Size of the THH portion of `combined`, in bytes. Used to reverse
    /// the pointer fixup when re-splitting. Recovered from the combined
    /// THP's 0x28 field on parse, since that offset equals `thhSize` in
    /// the split-form convention (split[0x28] == 0).
    public var thhSize: Int

    public init(name: String = "thp", combined: GoDData, thhSize: Int) {
        self.name = name
        self.combined = combined
        self.thhSize = thhSize
    }

    // MARK: - Pointer fixup offsets

    /// Offsets within the THH/combined header that hold file-relative
    /// frame pointers needing rebase. The doc only documents two; the
    /// list is centralised so tests can assert both are handled.
    public static let frameOffsetFieldAddresses: [Int] = [0x28, 0x2C]

    // MARK: - FileFormat: paired THH + THD binaries

    public init(binaries: [FileData]) throws {
        guard binaries.count >= 2 else { throw THPFile.invalidFileError }
        let thh = binaries.first(where: { $0.file.path.lowercased().hasSuffix(".thh") })
        let thd = binaries.first(where: { $0.file.path.lowercased().hasSuffix(".thd") })
        guard let thhData = thh?.data, let thdData = thd?.data else {
            throw THPFile.invalidFileError
        }
        let stem = thh.map { $0.file.path.withoutExtensions } ?? "thp"
        try self.init(thh: thhData, thd: thdData, name: stem.isEmpty ? "thp" : stem)
    }

    public init(thh: GoDData, thd: GoDData, name: String = "thp") throws {
        thh.setByteOrder(.big)
        guard thh.length >= 0x30 else {
            throw THPFile.invalidFileError
        }

        // Build the combined byte stream.
        let combined = GoDData(byteOrder: .big)
        for b in thh.rawBytes { combined.append(b) }
        for b in thd.rawBytes { combined.append(b) }

        // Add `thhSize` to each documented frame-offset field.
        let thhSize = thh.length
        for address in THPFile.frameOffsetFieldAddresses {
            let original: UInt32 = combined.readSafely(atAddress: address)
            _ = combined.write(
                (original &+ UInt32(thhSize)) as UInt32,
                atAddress: address
            )
        }

        self.init(name: name, combined: combined, thhSize: thhSize)
    }

    public var binaries: [FileData] {
        get throws {
            let (thh, thd) = try splitCombined()
            return [
                FileData(file: File("\(name).thh"), data: thh),
                FileData(file: File("\(name).thd"), data: thd)
            ]
        }
    }

    /// Splits `combined` back into THH + THD, reversing the pointer
    /// fixup. Exposed publicly so the build op can consume the pair
    /// without going through `binaries`' FileData wrapping.
    public func splitCombined() throws -> (thh: GoDData, thd: GoDData) {
        guard combined.length >= thhSize, thhSize > 0 else {
            throw FileFormatErrors.failedToEncode(
                format: THPFile.formatName,
                target: "thhSize (\(thhSize)) out of range for combined length \(combined.length)"
            )
        }
        let thhBytes = combined.rawBytes.prefix(thhSize)
        let thdBytes = combined.rawBytes.dropFirst(thhSize)
        let thh = GoDData(byteStream: Array(thhBytes), byteOrder: .big)
        let thd = GoDData(byteStream: Array(thdBytes), byteOrder: .big)
        for address in THPFile.frameOffsetFieldAddresses {
            let combinedValue: UInt32 = thh.readSafely(atAddress: address)
            _ = thh.write(
                (combinedValue &- UInt32(thhSize)) as UInt32,
                atAddress: address
            )
        }
        return (thh, thd)
    }

    // MARK: - FileFormat: editable artifacts (single `.thp`)

    public init(outputs: [FileData]) throws {
        let thpSuffix = ".\(THPFile.formatName)"
        guard let entry = outputs.first(where: { $0.file.path.lowercased().hasSuffix(thpSuffix) }) else {
            throw THPFile.missingOutputError(key: "*\(thpSuffix)")
        }
        let stem = entry.file.path.withoutExtensions
        let bytes = entry.data
        // The combined THP's 0x28 field gives us thhSize directly (the
        // split form puts 0 there; dump adds thhSize).
        bytes.setByteOrder(.big)
        let thhSize: UInt32 = bytes.readSafely(atAddress: 0x28)
        self.init(
            name: stem.isEmpty ? "thp" : stem,
            combined: bytes,
            thhSize: Int(thhSize)
        )
    }

    public var outputs: [FileData] {
        get throws {
            let thpFile = File("\(name).\(THPFile.formatName)")
            return [FileData(file: thpFile, data: combined)]
        }
    }
}
