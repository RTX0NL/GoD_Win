//
//  NKitHeader.swift
//
//  The NKit metadata block that lives at file offset 0x200 of every
//  `.nkit.iso`. Same layout for GameCube and Wii NKit images; Wii
//  images additionally set a few flags in the first 0x200 bytes of
//  the disc header and write a CRC of a removed update partition.
//
//  Confirmed against Nanook/NKitv1 `NKit/Conversion/Writers/`:
//
//    0x200  8  ASCII   Magic + version "NKIT v01"
//    0x208  4  UInt32  Original-ISO CRC32
//    0x20C  4  UInt32  CRC-force value (picks up the slack so
//                      CRC32(.nkit.iso) matches the original CRC)
//    0x210  4  UInt32  Original ISO size (divided by 4 for Wii to fit)
//    0x214  4  ASCII   Junk-override Game ID (GC); all-zero if unused
//    0x218  4  UInt32  Update-partition CRC (Wii only; 0 if not removed)
//
//  Reference: Documentation/File Formats/Shared/NKIT - Lossless Shrunk ISO.md
//

import Foundation
import GoDFoundation

public struct NKitHeader: Equatable {

    public enum Platform: Equatable { case gamecube, wii }

    /// File offset of the header block.
    public static let blockOffset: Int = 0x200
    /// Byte size of the header's fields (ASCII magic + 24 bytes of
    /// scalar values = 32 bytes). The rest of the 0x200-0x3FF region
    /// is zero padding.
    public static let fieldsSize: Int = 32
    public static let magic: [UInt8] = [0x4E, 0x4B, 0x49, 0x54, 0x20, 0x76, 0x30, 0x31] // "NKIT v01"

    public var platform: Platform
    public var originalCRC: UInt32
    public var crcForce: UInt32
    public var originalImageSize: UInt64       // already un-divided for both platforms
    public var junkOverrideID: String?         // nil ⇔ bytes at 0x214 are all zero
    public var updatePartitionCRC: UInt32?     // Wii only; nil if update partition wasn't removed

    public init(
        platform: Platform,
        originalCRC: UInt32 = 0,
        crcForce: UInt32 = 0,
        originalImageSize: UInt64 = 0,
        junkOverrideID: String? = nil,
        updatePartitionCRC: UInt32? = nil
    ) {
        self.platform = platform
        self.originalCRC = originalCRC
        self.crcForce = crcForce
        self.originalImageSize = originalImageSize
        self.junkOverrideID = junkOverrideID
        self.updatePartitionCRC = updatePartitionCRC
    }

    // MARK: - Parse

    /// Parse the NKit header out of a `.nkit.iso`'s first sector.
    /// Expects `binary` to contain at least `0x200 + fieldsSize`
    /// bytes of the file.
    ///
    /// Takes a `GoDReadable` so a 1 GB image can be identified without
    /// being loaded, and decodes its fields big-endian explicitly
    /// rather than through the source's declared byte order — a
    /// readable handed back by `FileSystem.readFile` carries the
    /// *host's* order, and this block is big-endian whatever that is.
    public init(binary: GoDReadable, platform: Platform) throws {
        guard binary.length >= NKitHeader.blockOffset + NKitHeader.fieldsSize,
              let block = binary.read(
                  atAddress: NKitHeader.blockOffset, length: NKitHeader.fieldsSize
              )?.rawBytes,
              block.count == NKitHeader.fieldsSize else {
            throw FileFormatErrors.invalid(format: "nkit")
        }

        // Magic + version: "NKIT v01"
        guard Array(block[0 ..< 8]) == NKitHeader.magic else {
            throw FileFormatErrors.invalid(format: "nkit")
        }

        func word(_ offset: Int) -> UInt32 {
            (UInt32(block[offset]) << 24) | (UInt32(block[offset + 1]) << 16)
                | (UInt32(block[offset + 2]) << 8) | UInt32(block[offset + 3])
        }

        let originalCRC = word(0x08)
        let crcForce = word(0x0C)
        let rawSize = word(0x10)
        let originalImageSize: UInt64
        switch platform {
        case .gamecube: originalImageSize = UInt64(rawSize)
        case .wii:      originalImageSize = UInt64(rawSize) &* 4
        }

        var junkOverride: String? = nil
        if platform == .gamecube {
            let bytes = Array(block[0x14 ..< 0x18])
            if bytes.contains(where: { $0 != 0 }),
               let ascii = String(bytes: bytes, encoding: .ascii) {
                junkOverride = ascii
            }
        }

        var updateCRC: UInt32? = nil
        if platform == .wii {
            let raw = word(0x18)
            if raw != 0 { updateCRC = raw }
        }

        self.platform = platform
        self.originalCRC = originalCRC
        self.crcForce = crcForce
        self.originalImageSize = originalImageSize
        self.junkOverrideID = junkOverride
        self.updatePartitionCRC = updateCRC
    }

    // MARK: - Serialize

    /// Write the header into `binary` at the well-known 0x200 offset.
    /// `binary` must already be at least `0x200 + fieldsSize` bytes
    /// long; the function patches the block in place.
    public func write(into binary: GoDData) {
        binary.setByteOrder(.big)
        for (i, b) in NKitHeader.magic.enumerated() {
            _ = binary.write(b, atAddress: NKitHeader.blockOffset + i)
        }
        _ = binary.write(originalCRC, atAddress: NKitHeader.blockOffset + 0x08)
        _ = binary.write(crcForce,    atAddress: NKitHeader.blockOffset + 0x0C)

        let storedSize: UInt32
        switch platform {
        case .gamecube: storedSize = UInt32(truncatingIfNeeded: originalImageSize)
        case .wii:      storedSize = UInt32(truncatingIfNeeded: originalImageSize / 4)
        }
        _ = binary.write(storedSize, atAddress: NKitHeader.blockOffset + 0x10)

        // Junk override ID (GC): 4 ASCII bytes or all-zero.
        var junkBytes: [UInt8] = [0, 0, 0, 0]
        if platform == .gamecube, let id = junkOverrideID {
            let idBytes = Array(id.utf8).prefix(4)
            for (i, b) in idBytes.enumerated() { junkBytes[i] = b }
        }
        for (i, b) in junkBytes.enumerated() {
            _ = binary.write(b, atAddress: NKitHeader.blockOffset + 0x14 + i)
        }

        // Update partition CRC (Wii): UInt32 at 0x218.
        let updateRaw: UInt32 = (platform == .wii) ? (updatePartitionCRC ?? 0) : 0
        _ = binary.write(updateRaw, atAddress: NKitHeader.blockOffset + 0x18)
    }
}
