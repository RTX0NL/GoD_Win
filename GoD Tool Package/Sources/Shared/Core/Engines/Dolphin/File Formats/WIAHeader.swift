//
//  WIAHeader.swift
//
//  Dolphin's WIA/RVZ disc image format — the top two header structs:
//
//    wia_file_head_t   (0x48 bytes, fixed)  at file offset 0
//    wia_disc_t        (variable, size declared in file_head.disc_size)
//                                           at file offset 0x48
//
//  WIA and RVZ use the same magic ("WIA\x01") and the same file-head
//  layout; they diverge in `wia_disc_t.compression`, where WIA allows
//  {none, purge, bzip2, lzma, lzma2} and RVZ adds {zstd} while
//  disallowing purge. Callers pick WIA vs RVZ by inspecting the
//  compression ID.
//
//  Reference:
//    dolphin-emu/dolphin `docs/WiaAndRvz.md`
//    Documentation/File Formats/Shared/RVZ - Dolphin Disc Image.md
//

import Foundation
import GoDFoundation

public struct WIAFileHeader: Equatable {

    /// wit's magic, and the one Dolphin's own spec document names.
    public static let wiaMagic: [UInt8] = [0x57, 0x49, 0x41, 0x01]  // "WIA\x01"
    /// Dolphin writes this for the RVZ variant. Files in the wild carry it,
    /// and it is inside the range `fileHeadHash` covers, so it has to be
    /// kept rather than normalized to the WIA spelling.
    public static let rvzMagic: [UInt8] = [0x52, 0x56, 0x5A, 0x01]  // "RVZ\x01"
    public static let fixedSize: Int = 0x48

    /// The four magic bytes exactly as stored.
    public var magic: [UInt8]
    public var version: UInt32
    public var versionCompatible: UInt32
    public var discSize: UInt32             // bytes of `wia_disc_t` that follow
    public var discHash: [UInt8]            // SHA-1 (20 bytes) over the disc struct
    public var isoFileSize: UInt64          // size of the reconstructed source disc
    public var wiaFileSize: UInt64          // size of this .wia/.rvz on disk
    public var fileHeadHash: [UInt8]        // SHA-1 (20 bytes) over bytes [0x00..0x34)

    public init(
        magic: [UInt8] = WIAFileHeader.wiaMagic,
        version: UInt32 = 0,
        versionCompatible: UInt32 = 0,
        discSize: UInt32 = 0,
        discHash: [UInt8] = [UInt8](repeating: 0, count: 20),
        isoFileSize: UInt64 = 0,
        wiaFileSize: UInt64 = 0,
        fileHeadHash: [UInt8] = [UInt8](repeating: 0, count: 20)
    ) {
        self.magic = magic
        self.version = version
        self.versionCompatible = versionCompatible
        self.discSize = discSize
        self.discHash = discHash
        self.isoFileSize = isoFileSize
        self.wiaFileSize = wiaFileSize
        self.fileHeadHash = fileHeadHash
    }

    public init(binary: GoDData) throws {
        binary.setByteOrder(.big)
        guard binary.length >= WIAFileHeader.fixedSize else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        guard let magic = binary.read(atAddress: 0, length: 4)?.rawBytes,
              magic == WIAFileHeader.wiaMagic || magic == WIAFileHeader.rvzMagic else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        self.magic = magic
        self.version = binary.readSafely(atAddress: 0x04)
        self.versionCompatible = binary.readSafely(atAddress: 0x08)
        self.discSize = binary.readSafely(atAddress: 0x0C)
        guard let hash1 = binary.read(atAddress: 0x10, length: 20)?.rawBytes else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        self.discHash = hash1
        self.isoFileSize = binary.readSafely(atAddress: 0x24)
        self.wiaFileSize = binary.readSafely(atAddress: 0x2C)
        guard let hash2 = binary.read(atAddress: 0x34, length: 20)?.rawBytes else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        self.fileHeadHash = hash2
    }

    /// Serialize to the 0x48-byte on-disc representation. The hash
    /// fields are written verbatim; callers are responsible for
    /// filling them with the correct SHA-1 values before calling.
    public var binaryData: GoDData {
        let out = GoDData(byteOrder: .big)
        for b in magic.prefix(4) { out.append(b) }
        for _ in magic.count..<4 { out.append(UInt8(0)) }
        out.append(version)
        out.append(versionCompatible)
        out.append(discSize)
        for b in discHash.prefix(20) { out.append(b) }
        for _ in discHash.count..<20 { out.append(UInt8(0)) }  // pad if short
        out.append(isoFileSize)
        out.append(wiaFileSize)
        for b in fileHeadHash.prefix(20) { out.append(b) }
        for _ in fileHeadHash.count..<20 { out.append(UInt8(0)) }
        assert(out.length == WIAFileHeader.fixedSize)
        return out
    }
}

// MARK: - wia_disc_t

public struct WIADisc: Equatable {

    public enum DiscType: UInt32, Equatable {
        case unknown   = 0
        case gamecube  = 1
        case wii       = 2
    }

    public enum Compression: UInt32, Equatable {
        case none  = 0
        case purge = 1    // WIA only (legacy)
        case bzip2 = 2
        case lzma  = 3
        case lzma2 = 4
        case zstd  = 5    // RVZ only

        /// Whether this compression value is valid in RVZ. PURGE is
        /// WIA-only.
        public var allowedInRVZ: Bool { self != .purge }
        /// Whether this compression value is valid in WIA. Zstd is
        /// RVZ-only.
        public var allowedInWIA: Bool { self != .zstd }
    }

    public static let fixedFieldsSize: Int = 0xDC  // through compr_data
    public static let discHeaderSize: Int = 0x80    // dhead verbatim copy

    public var discType: DiscType
    public var compression: Compression
    public var compressionLevel: Int32          // signed — Zstd can be negative
    public var chunkSize: UInt32
    public var discHeader: [UInt8]              // first 0x80 bytes of the original disc
    public var partitionCount: UInt32
    public var partitionStructSize: UInt32
    public var partitionTableOffset: UInt64
    public var partitionHash: [UInt8]           // SHA-1 over the partition table
    public var rawDataCount: UInt32
    public var rawDataOffset: UInt64
    public var rawDataCompressedSize: UInt32
    public var groupCount: UInt32
    public var groupTableOffset: UInt64
    public var groupTableCompressedSize: UInt32
    public var compressionData: [UInt8]         // up to 7 bytes; meaning depends on compression

    public init(
        discType: DiscType = .unknown,
        compression: Compression = .none,
        compressionLevel: Int32 = 0,
        chunkSize: UInt32 = 0,
        discHeader: [UInt8] = [UInt8](repeating: 0, count: WIADisc.discHeaderSize),
        partitionCount: UInt32 = 0,
        partitionStructSize: UInt32 = 0,
        partitionTableOffset: UInt64 = 0,
        partitionHash: [UInt8] = [UInt8](repeating: 0, count: 20),
        rawDataCount: UInt32 = 0,
        rawDataOffset: UInt64 = 0,
        rawDataCompressedSize: UInt32 = 0,
        groupCount: UInt32 = 0,
        groupTableOffset: UInt64 = 0,
        groupTableCompressedSize: UInt32 = 0,
        compressionData: [UInt8] = []
    ) {
        self.discType = discType
        self.compression = compression
        self.compressionLevel = compressionLevel
        self.chunkSize = chunkSize
        self.discHeader = discHeader
        self.partitionCount = partitionCount
        self.partitionStructSize = partitionStructSize
        self.partitionTableOffset = partitionTableOffset
        self.partitionHash = partitionHash
        self.rawDataCount = rawDataCount
        self.rawDataOffset = rawDataOffset
        self.rawDataCompressedSize = rawDataCompressedSize
        self.groupCount = groupCount
        self.groupTableOffset = groupTableOffset
        self.groupTableCompressedSize = groupTableCompressedSize
        self.compressionData = compressionData
    }

    public init(binary: GoDData) throws {
        binary.setByteOrder(.big)
        guard binary.length >= WIADisc.fixedFieldsSize else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        let discTypeRaw: UInt32 = binary.readSafely(atAddress: 0x00)
        let compressionRaw: UInt32 = binary.readSafely(atAddress: 0x04)
        guard let discType = DiscType(rawValue: discTypeRaw),
              let compression = Compression(rawValue: compressionRaw) else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        self.discType = discType
        self.compression = compression
        let levelRaw: UInt32 = binary.readSafely(atAddress: 0x08)
        self.compressionLevel = Int32(bitPattern: levelRaw)
        self.chunkSize = binary.readSafely(atAddress: 0x0C)
        guard let head = binary.read(atAddress: 0x10, length: WIADisc.discHeaderSize)?.rawBytes else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        self.discHeader = head
        self.partitionCount = binary.readSafely(atAddress: 0x90)
        self.partitionStructSize = binary.readSafely(atAddress: 0x94)
        self.partitionTableOffset = binary.readSafely(atAddress: 0x98)
        guard let partHash = binary.read(atAddress: 0xA0, length: 20)?.rawBytes else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        self.partitionHash = partHash
        self.rawDataCount = binary.readSafely(atAddress: 0xB4)
        self.rawDataOffset = binary.readSafely(atAddress: 0xB8)
        self.rawDataCompressedSize = binary.readSafely(atAddress: 0xC0)
        self.groupCount = binary.readSafely(atAddress: 0xC4)
        self.groupTableOffset = binary.readSafely(atAddress: 0xC8)
        self.groupTableCompressedSize = binary.readSafely(atAddress: 0xD0)
        let compressionDataLen: UInt8 = binary.readSafely(atAddress: 0xD4)
        let len = min(Int(compressionDataLen), 7)
        if len > 0, let cd = binary.read(atAddress: 0xD5, length: len)?.rawBytes {
            self.compressionData = cd
        } else {
            self.compressionData = []
        }
    }

    public var binaryData: GoDData {
        let out = GoDData(byteOrder: .big)
        out.append(discType.rawValue)
        out.append(compression.rawValue)
        out.append(UInt32(bitPattern: compressionLevel))
        out.append(chunkSize)
        for b in discHeader.prefix(WIADisc.discHeaderSize) { out.append(b) }
        for _ in discHeader.count..<WIADisc.discHeaderSize { out.append(UInt8(0)) }
        out.append(partitionCount)
        out.append(partitionStructSize)
        out.append(partitionTableOffset)
        for b in partitionHash.prefix(20) { out.append(b) }
        for _ in partitionHash.count..<20 { out.append(UInt8(0)) }
        out.append(rawDataCount)
        out.append(rawDataOffset)
        out.append(rawDataCompressedSize)
        out.append(groupCount)
        out.append(groupTableOffset)
        out.append(groupTableCompressedSize)
        let comprLen = min(compressionData.count, 7)
        out.append(UInt8(comprLen))
        for i in 0..<7 {
            out.append(i < comprLen ? compressionData[i] : UInt8(0))
        }
        assert(out.length == WIADisc.fixedFieldsSize)
        return out
    }

    // MARK: - Derived compressor parameters

    /// LZMA-encoded `(lc, pb, lp)` from the first byte of
    /// `compressionData`. Valid only when `compression == .lzma`.
    public var lzmaProperties: (lc: UInt8, pb: UInt8, lp: UInt8)? {
        guard compression == .lzma, compressionData.count >= 1 else { return nil }
        let d = compressionData[0]
        return (lc: d % 9, pb: (d / 9) / 5, lp: (d / 9) % 5)
    }

    /// LZMA dictionary size (4 bytes LE in `compressionData[1..<5]`).
    public var lzmaDictSize: UInt32? {
        guard compression == .lzma, compressionData.count >= 5 else { return nil }
        return (UInt32(compressionData[1]))
            | (UInt32(compressionData[2]) << 8)
            | (UInt32(compressionData[3]) << 16)
            | (UInt32(compressionData[4]) << 24)
    }

    /// LZMA2 dictionary size, computed from the single property byte.
    /// - Property 40 → `0xFFFFFFFF` (max).
    /// - Otherwise: `((2 | (prop & 1)) << (prop / 2 + 11))`.
    public var lzma2DictSize: UInt32? {
        guard compression == .lzma2, compressionData.count >= 1 else { return nil }
        let prop = compressionData[0]
        if prop == 40 { return 0xFFFF_FFFF }
        return (UInt32(2) | (UInt32(prop) & 1)) << (UInt32(prop) / 2 + 11)
    }

    /// Distinguish WIA and RVZ by compression + chunk-size rules.
    ///
    /// RVZ allows Zstd and chunk sizes smaller than 2 MiB (power-of-2,
    /// down to 32 KiB); WIA forbids both. Any file using either is
    /// necessarily RVZ.
    public var isRVZ: Bool {
        if compression == .zstd { return true }
        if chunkSize < 0x0020_0000 { return true }
        return false
    }
}
