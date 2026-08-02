//
//  CISOFile.swift
//
//  GameCube/Wii CISO ("Compact ISO", a.k.a. Wiimms CISO) — a minimal
//  space-saving format that omits runs of zero bytes from an ISO.
//  No compression, no crypto, no checksums: a 32 KiB header carrying
//  a 1/0 block-presence bitmap, followed by the present blocks
//  concatenated in order.
//
//  Shares the `"CISO"` magic with PSP CSO but is otherwise unrelated;
//  disambiguate by the block-size field at offset 0x04. GC/Wii CISO
//  uses `0x00200000` (2 MiB); PSP CSO uses `0x800` (2 KiB).
//
//  Reference: Documentation/File Formats/Shared/CISO - Compact ISO.md
//

import Foundation
import GoDFoundation

public struct CISOFile: Equatable {

    public static let formatName = "ciso"
    public static let magic: [UInt8] = [0x43, 0x49, 0x53, 0x4F]  // "CISO"
    public static let headerSize: Int = 0x8000
    public static let blockMapSize: Int = 0x7FF8  // 32760
    public static let defaultBlockSize: UInt32 = 0x0020_0000  // 2 MiB

    /// 2 MiB for every GC/Wii CISO in the wild. Legal values per the
    /// spec are any power-of-two ≥ 32 KiB, though nothing produces
    /// those in practice.
    public var blockSize: UInt32

    /// One entry per block — `true` if the block is stored in the body,
    /// `false` if it was omitted (logically 2 MiB of zero). Up to
    /// 32760 entries.
    public var blockMap: [Bool]

    /// The target disc size the restored ISO should have. CISO doesn't
    /// store this; callers or `restoreISO` consumers must supply it.
    /// Kept alongside the header so the pair travels together.
    public var discSize: UInt64

    public init(blockSize: UInt32, blockMap: [Bool], discSize: UInt64) {
        self.blockSize = blockSize
        self.blockMap = blockMap
        self.discSize = discSize
    }

    // MARK: - Parse

    /// Parse a CISO header from the first `0x8000` bytes of a file.
    /// Throws on bad magic or unreasonable block size.
    /// `discSize` is taken from caller context (default: derived from
    /// the last `true` bit in the map × block size, which is the lower
    /// bound; see `CISO - Implementation Plan.md` for the caveat).
    public init(binary: GoDData, discSize: UInt64? = nil) throws {
        binary.setByteOrder(.little)
        guard binary.length >= CISOFile.headerSize else {
            throw FileFormatErrors.invalid(format: CISOFile.formatName)
        }
        let m0: UInt8 = binary.readSafely(atAddress: 0)
        let m1: UInt8 = binary.readSafely(atAddress: 1)
        let m2: UInt8 = binary.readSafely(atAddress: 2)
        let m3: UInt8 = binary.readSafely(atAddress: 3)
        guard [m0, m1, m2, m3] == CISOFile.magic else {
            throw FileFormatErrors.invalid(format: CISOFile.formatName)
        }
        let blockSize: UInt32 = binary.readSafely(atAddress: 4)
        guard blockSize >= 0x8000, blockSize.nonzeroBitCount == 1 else {
            throw FileFormatErrors.invalid(format: CISOFile.formatName)
        }

        var map = [Bool](repeating: false, count: CISOFile.blockMapSize)
        guard let mapBytes = binary.read(atAddress: 8, length: CISOFile.blockMapSize)?.rawBytes else {
            throw FileFormatErrors.invalid(format: CISOFile.formatName)
        }
        for i in 0..<CISOFile.blockMapSize {
            map[i] = mapBytes[i] != 0
        }

        // Trim trailing `false`s — they carry no information and the
        // decoder can always pad zeros beyond the highest-used block.
        while let last = map.last, last == false, map.count > 0 {
            map.removeLast()
            if map.count == 0 { break }
        }

        self.blockSize = blockSize
        self.blockMap = map
        // When the caller hasn't told us the disc size, fall back to
        // the logical size implied by the last present block. Bytes
        // past there will be zero-filled on restore; callers who know
        // the true disc size should pass it in.
        if let given = discSize {
            self.discSize = given
        } else {
            self.discSize = UInt64(map.count) * UInt64(blockSize)
        }
    }

    // MARK: - Header bytes

    /// Serialize the 32 KiB header (magic + block size + full map,
    /// zero-padded to 32760 entries).
    public var headerBytes: GoDData {
        let out = GoDData(byteOrder: .little)
        for b in CISOFile.magic { out.append(b) }
        out.append(blockSize)
        // Map: 1 byte per entry, up to 32760 entries. Excess entries
        // (beyond `blockMap.count`) are `0` (absent).
        var mapBytes = [UInt8](repeating: 0, count: CISOFile.blockMapSize)
        for i in 0..<min(blockMap.count, CISOFile.blockMapSize) {
            mapBytes[i] = blockMap[i] ? 1 : 0
        }
        for b in mapBytes { out.append(b) }
        return out
    }

    // MARK: - Block location

    /// File offset of the body bytes for block `index`, or `nil` if
    /// the block is absent from the map.
    public func fileOffset(ofBlock index: Int) -> UInt64? {
        guard index < blockMap.count, blockMap[index] else { return nil }
        var presentBefore = 0
        for i in 0..<index where blockMap[i] {
            presentBefore += 1
        }
        return UInt64(CISOFile.headerSize) + UInt64(presentBefore) * UInt64(blockSize)
    }

    /// Total on-disk size of the CISO file (header + concatenated
    /// present blocks).
    public var totalFileSize: UInt64 {
        let present = blockMap.reduce(0) { $0 + ($1 ? 1 : 0) }
        return UInt64(CISOFile.headerSize) + UInt64(present) * UInt64(blockSize)
    }
}

// MARK: - Dump / build

public enum CISOConverter {

    /// Shrink a raw ISO into a CISO. Any 2 MiB block of all-zero bytes
    /// is marked absent in the map and dropped from the body.
    public static func build(iso: GoDData, blockSize: UInt32 = CISOFile.defaultBlockSize) -> GoDData {
        let bs = Int(blockSize)
        let totalBytes = iso.length
        let blockCount = (totalBytes + bs - 1) / bs
        var map = [Bool](repeating: false, count: blockCount)
        var bodyChunks: [GoDData] = []

        for i in 0..<blockCount {
            let off = i * bs
            let len = min(bs, totalBytes - off)
            guard let chunk = iso.read(atAddress: off, length: len) else { continue }
            let bytes = chunk.rawBytes
            let isAllZero = bytes.allSatisfy { $0 == 0 }
            if isAllZero && len == bs {
                map[i] = false
            } else {
                map[i] = true
                if len < bs {
                    // Pad the last short block to full block size with
                    // zeros so the body's block alignment holds.
                    let padded = GoDData(byteStream: bytes + [UInt8](repeating: 0, count: bs - len), byteOrder: .big)
                    bodyChunks.append(padded)
                } else {
                    bodyChunks.append(chunk)
                }
            }
        }

        let ciso = CISOFile(blockSize: blockSize, blockMap: map, discSize: UInt64(totalBytes))
        let out = ciso.headerBytes
        for c in bodyChunks { out.append(c) }
        return out
    }

    /// Restore a CISO file to the original ISO bytes. `targetDiscSize`
    /// controls how many total bytes the restored ISO will have; when
    /// nil, defaults to `blockMap.count * blockSize` (the minimum size
    /// that contains every present block).
    public static func dump(ciso: GoDData, targetDiscSize: UInt64? = nil) throws -> GoDData {
        let header = try CISOFile(binary: ciso, discSize: targetDiscSize)
        let bs = Int(header.blockSize)
        let totalBytes = Int(targetDiscSize ?? header.discSize)
        let out = GoDData(byteOrder: .big)

        // Walk the body sequentially: each `true` in the map consumes
        // one block worth of body bytes; `false` writes a zero block.
        var bodyCursor = CISOFile.headerSize
        let totalBlocks = (totalBytes + bs - 1) / bs
        for i in 0..<totalBlocks {
            let len = min(bs, totalBytes - i * bs)
            if i < header.blockMap.count, header.blockMap[i] {
                guard let chunk = ciso.read(atAddress: bodyCursor, length: bs) else {
                    throw FileFormatErrors.invalid(format: CISOFile.formatName)
                }
                if len == bs {
                    out.append(chunk)
                } else {
                    let bytes = chunk.rawBytes
                    for b in bytes.prefix(len) { out.append(b) }
                }
                bodyCursor += bs
            } else {
                // Absent block or past the map — zero fill.
                for _ in 0..<len { out.append(UInt8(0)) }
            }
        }
        return out
    }
}
