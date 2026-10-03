//
//  WIAPartition.swift
//
//  WIA/RVZ per-partition metadata (Wii only). Each partition is
//  described by a `wia_part_t` record:
//
//    0x00  16 bytes  AES-128 title key (already decrypted from the
//                    ticket's common-key encryption)
//    0x10  16 bytes  pd[0] — management segment (tickets, TMD, certs)
//    0x20  16 bytes  pd[1] — bulk data segment
//
//  Each `wia_part_data_t` (pd[i]) is 16 bytes:
//
//    0x00  4  first Wii sector (1 sector = 32 KiB)
//    0x04  4  number of Wii sectors
//    0x08  4  first group index in the group table
//    0x0C  4  number of consecutive groups
//
//  For GameCube images `n_part` is 0 and no `wia_part_t` records
//  exist; the disc's raw data lives entirely in `wia_raw_data_t`
//  descriptors.
//
//  Reference: dolphin-emu/dolphin `docs/WiaAndRvz.md`
//

import Foundation
import GoDFoundation

public struct WIAPartitionSegment: Equatable {
    public static let byteSize: Int = 16

    public var firstSector: UInt32
    public var sectorCount: UInt32
    public var firstGroupIndex: UInt32
    public var groupCount: UInt32

    public init(firstSector: UInt32 = 0, sectorCount: UInt32 = 0,
                firstGroupIndex: UInt32 = 0, groupCount: UInt32 = 0) {
        self.firstSector = firstSector
        self.sectorCount = sectorCount
        self.firstGroupIndex = firstGroupIndex
        self.groupCount = groupCount
    }

    public init(binary: GoDData, at offset: Int) throws {
        binary.setByteOrder(.big)
        guard offset + WIAPartitionSegment.byteSize <= binary.length else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        self.firstSector     = binary.readSafely(atAddress: offset)
        self.sectorCount     = binary.readSafely(atAddress: offset + 4)
        self.firstGroupIndex = binary.readSafely(atAddress: offset + 8)
        self.groupCount      = binary.readSafely(atAddress: offset + 12)
    }

    public func write(into binary: GoDData, at offset: Int) {
        binary.setByteOrder(.big)
        _ = binary.write(firstSector,     atAddress: offset)
        _ = binary.write(sectorCount,     atAddress: offset + 4)
        _ = binary.write(firstGroupIndex, atAddress: offset + 8)
        _ = binary.write(groupCount,      atAddress: offset + 12)
    }
}

public struct WIAPartition: Equatable {
    public static let byteSize: Int = 16 + 2 * WIAPartitionSegment.byteSize  // 48

    public var titleKey: [UInt8]                 // 16 bytes
    public var managementSegment: WIAPartitionSegment     // pd[0]
    public var dataSegment: WIAPartitionSegment           // pd[1]

    public init(
        titleKey: [UInt8] = [UInt8](repeating: 0, count: 16),
        managementSegment: WIAPartitionSegment = WIAPartitionSegment(),
        dataSegment: WIAPartitionSegment = WIAPartitionSegment()
    ) {
        self.titleKey = titleKey
        self.managementSegment = managementSegment
        self.dataSegment = dataSegment
    }

    public init(binary: GoDData, at offset: Int) throws {
        binary.setByteOrder(.big)
        guard offset + WIAPartition.byteSize <= binary.length else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        guard let key = binary.read(atAddress: offset, length: 16)?.rawBytes else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        self.titleKey = key
        self.managementSegment = try WIAPartitionSegment(binary: binary, at: offset + 16)
        self.dataSegment       = try WIAPartitionSegment(binary: binary, at: offset + 32)
    }

    public func write(into binary: GoDData, at offset: Int) {
        binary.setByteOrder(.big)
        for i in 0..<16 {
            _ = binary.write(i < titleKey.count ? titleKey[i] : UInt8(0),
                             atAddress: offset + i)
        }
        managementSegment.write(into: binary, at: offset + 16)
        dataSegment.write(into: binary, at: offset + 32)
    }
}

// MARK: - Raw data descriptor

/// Describes a non-partition span of the disc (GC data, Wii disc
/// header, the 0x40000 partition table at the start of a Wii disc,
/// the update partition if present, any filler between partitions).
public struct WIARawData: Equatable {
    public static let byteSize: Int = 24

    public var discOffset: UInt64        // position on the original disc
    public var size: UInt64              // decompressed byte count
    public var firstGroupIndex: UInt32
    public var groupCount: UInt32

    public init(
        discOffset: UInt64 = 0,
        size: UInt64 = 0,
        firstGroupIndex: UInt32 = 0,
        groupCount: UInt32 = 0
    ) {
        self.discOffset = discOffset
        self.size = size
        self.firstGroupIndex = firstGroupIndex
        self.groupCount = groupCount
    }

    public init(binary: GoDData, at offset: Int) throws {
        binary.setByteOrder(.big)
        guard offset + WIARawData.byteSize <= binary.length else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        self.discOffset      = binary.readSafely(atAddress: offset)
        self.size            = binary.readSafely(atAddress: offset + 8)
        self.firstGroupIndex = binary.readSafely(atAddress: offset + 16)
        self.groupCount      = binary.readSafely(atAddress: offset + 20)
    }

    public func write(into binary: GoDData, at offset: Int) {
        binary.setByteOrder(.big)
        _ = binary.write(discOffset,      atAddress: offset)
        _ = binary.write(size,            atAddress: offset + 8)
        _ = binary.write(firstGroupIndex, atAddress: offset + 16)
        _ = binary.write(groupCount,      atAddress: offset + 20)
    }
}

// MARK: - Group entry

/// One group's file-layout entry. WIA uses an 8-byte record; RVZ
/// extends it to 12 bytes with an additional "packed size" field and
/// a bit-31 "compressed" flag on the size field.
public enum WIAGroupEntry: Equatable {
    case wia(dataOffsetDiv4: UInt32, dataSize: UInt32)
    case rvz(dataOffsetDiv4: UInt32, dataSize: UInt32, isCompressed: Bool, rvzPackedSize: UInt32)

    public static let wiaByteSize: Int = 8
    public static let rvzByteSize: Int = 12

    /// File offset of the group's compressed payload (data_off4 × 4).
    public var dataOffset: UInt64 {
        switch self {
        case .wia(let off, _): return UInt64(off) * 4
        case .rvz(let off, _, _, _): return UInt64(off) * 4
        }
    }

    /// Compressed byte size of the payload (`data_size` with the top
    /// bit stripped on RVZ).
    public var dataSize: UInt32 {
        switch self {
        case .wia(_, let s): return s
        case .rvz(_, let s, _, _): return s
        }
    }

    /// All-zero groups are stored as `data_size == 0` (or in RVZ,
    /// `data_size_flag == 0`). The reader expands them to
    /// `chunk_size` bytes of zeros without any IO.
    public var isAllZeros: Bool { dataSize == 0 }

    public init(wiaBinary: GoDData, at offset: Int) throws {
        wiaBinary.setByteOrder(.big)
        guard offset + WIAGroupEntry.wiaByteSize <= wiaBinary.length else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        let off: UInt32 = wiaBinary.readSafely(atAddress: offset)
        let sz: UInt32  = wiaBinary.readSafely(atAddress: offset + 4)
        self = .wia(dataOffsetDiv4: off, dataSize: sz)
    }

    public init(rvzBinary: GoDData, at offset: Int) throws {
        rvzBinary.setByteOrder(.big)
        guard offset + WIAGroupEntry.rvzByteSize <= rvzBinary.length else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        let off: UInt32 = rvzBinary.readSafely(atAddress: offset)
        let sizeFlag: UInt32 = rvzBinary.readSafely(atAddress: offset + 4)
        let packed: UInt32 = rvzBinary.readSafely(atAddress: offset + 8)
        let isCompressed = (sizeFlag & 0x8000_0000) != 0
        let size = sizeFlag & 0x7FFF_FFFF
        self = .rvz(dataOffsetDiv4: off, dataSize: size, isCompressed: isCompressed, rvzPackedSize: packed)
    }

    public func write(into binary: GoDData, at offset: Int) {
        binary.setByteOrder(.big)
        switch self {
        case .wia(let off, let sz):
            _ = binary.write(off, atAddress: offset)
            _ = binary.write(sz,  atAddress: offset + 4)
        case .rvz(let off, let sz, let compressed, let packed):
            _ = binary.write(off, atAddress: offset)
            let sizeFlag: UInt32 = sz | (compressed ? 0x8000_0000 : 0)
            _ = binary.write(sizeFlag, atAddress: offset + 4)
            _ = binary.write(packed,   atAddress: offset + 8)
        }
    }
}

// MARK: - Exception list

/// Hash override list prefixed to every Wii partition group's
/// compressed payload. Each exception replaces a single SHA-1 in the
/// group's hash metadata with a fixed value — used when the original
/// disc's hashes don't match the recomputed ones (e.g. scene-modified
/// images where hashes differ by design).
public struct WIAExceptionList: Equatable {
    public static let prefixSize: Int = 2                 // n_exceptions (UInt16 BE)
    public static let exceptionSize: Int = 22             // UInt16 offset + 20-byte SHA-1

    public struct Exception: Equatable {
        public var offset: UInt16
        public var hash: [UInt8]       // 20 bytes

        public init(offset: UInt16, hash: [UInt8]) {
            precondition(hash.count == 20, "WIA exception hash must be 20 bytes")
            self.offset = offset
            self.hash = hash
        }
    }

    public var exceptions: [Exception]

    public init(exceptions: [Exception] = []) {
        self.exceptions = exceptions
    }

    /// Parse starting at `offset` in `binary`. Returns the list and
    /// the number of bytes consumed (for iteration over payloads that
    /// store multiple prefixed lists).
    public static func decode(from binary: GoDData, at offset: Int) throws -> (WIAExceptionList, consumed: Int) {
        binary.setByteOrder(.big)
        return try decode(from: binary.rawBytes, at: offset)
    }

    /// Parse from a plain byte buffer. The group decoder works this way —
    /// its payload is already a decompressed `[UInt8]`, and wrapping each
    /// one in a `GoDData` just to read a two-byte count would copy the
    /// whole chunk.
    public static func decode(from bytes: [UInt8], at offset: Int) throws -> (WIAExceptionList, consumed: Int) {
        guard offset >= 0, offset + prefixSize <= bytes.count else {
            throw FileFormatErrors.invalid(format: "wia")
        }
        let n = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        var cur = offset + prefixSize
        var exceptions: [Exception] = []
        exceptions.reserveCapacity(n)
        for _ in 0..<n {
            guard cur + exceptionSize <= bytes.count else {
                throw FileFormatErrors.invalid(format: "wia")
            }
            let o = UInt16(bytes[cur]) << 8 | UInt16(bytes[cur + 1])
            exceptions.append(Exception(offset: o, hash: Array(bytes[(cur + 2)..<(cur + 22)])))
            cur += exceptionSize
        }
        return (WIAExceptionList(exceptions: exceptions), consumed: cur - offset)
    }

    public func encode() -> [UInt8] {
        var out = [UInt8]()
        let n = UInt16(exceptions.count)
        out.append(UInt8(truncatingIfNeeded: n >> 8))
        out.append(UInt8(truncatingIfNeeded: n))
        for e in exceptions {
            out.append(UInt8(truncatingIfNeeded: e.offset >> 8))
            out.append(UInt8(truncatingIfNeeded: e.offset))
            out.append(contentsOf: e.hash.prefix(20))
            for _ in e.hash.count..<20 { out.append(0) }
        }
        return out
    }
}
