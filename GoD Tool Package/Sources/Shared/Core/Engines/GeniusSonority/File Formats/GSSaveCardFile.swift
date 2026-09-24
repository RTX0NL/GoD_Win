//
//  GSSaveCardFile.swift
//
//  Splits the body of a Pokémon **XD** `.gci` save into its three
//  regions:
//
//      0x00000  metadata — 0x6000  card comments, banner, icon frames,
//                                  a checksum over all of it, then zero
//      0x06000  slotA    — 0x28000 encrypted serialized SystemSaveData
//      0x2E000  slotB    — 0x28000 encrypted serialized SystemSaveData
//
//  Total body size: 0x56000.
//
//  > **Correction (2026-09).** This type used to cut the first 0x6000
//  > into a 0x2000 "banner" and two 0x2000 "header sectors". Measured on
//  > all 72 real XD and Colosseum saves, that is not the shape: the
//  > banner ends at 0x1840, icon frames and the shared palette run to
//  > 0x3A40, a checksum word follows, and everything to 0x6000 is zero.
//  > The old split cut the first icon in half and both "header sectors"
//  > held nothing. What the whole region *is* now derives from the save's
//  > own directory entry — see `CardImageBlock` — so this type keeps only
//  > the part that can't be derived: where the game's slots start.
//
//  > **Note (2026-04 correction):** an earlier version claimed Colosseum
//  > used the same 0x56000 / 2-slot shape. Colosseum's save is 0x60000
//  > with **three** 0x1E000 slots; that split lives in
//  > `Colosseum/SaveData/ColoSaveCardFile.swift`.
//
//  The authoritative region list is declared as engine data — see
//  `GeniusSonorityEngine.Data.galeOfDarknessSaveCard` — which is what the
//  GCI operations split on. This type remains for callers that want the
//  slots directly without going through a layout.
//

import Foundation
import GoDFoundation

public struct GSSaveCardFile: Equatable {
    public static let metadataOffset: Int = 0x00000
    public static let slotAOffset: Int  = 0x06000
    public static let slotBOffset: Int  = 0x2E000

    public static let metadataSize: Int = 0x06000
    public static let slotSize: Int     = 0x28000

    public static let bodySize: Int = slotBOffset + slotSize  // 0x56000
    public static let slotCount: Int = 2

    /// Comments, banner, icon frames, the metadata checksum and the zero
    /// fill up to the first slot. Its interior is described by the save's
    /// directory entry, not by this type.
    public var metadata: GoDData
    public var slotA: GoDData
    public var slotB: GoDData

    public init(metadata: GoDData, slotA: GoDData, slotB: GoDData) {
        self.metadata = metadata
        self.slotA = slotA
        self.slotB = slotB
    }

    /// Splits a 0x56000-byte body into its three regions. Throws if the
    /// body length doesn't match — callers should have already validated
    /// that it matches `blockCount * 0x2000`.
    public init(body: GoDData) throws {
        guard body.length == GSSaveCardFile.bodySize else {
            throw GSSaveCardFileError.invalidBodySize(
                expected: GSSaveCardFile.bodySize,
                actual: body.length
            )
        }
        guard
            let metadata = body.read(
                atAddress: UInt(GSSaveCardFile.metadataOffset),
                length: UInt(GSSaveCardFile.metadataSize)
            ),
            let slotA = body.read(
                atAddress: UInt(GSSaveCardFile.slotAOffset),
                length: UInt(GSSaveCardFile.slotSize)
            ),
            let slotB = body.read(
                atAddress: UInt(GSSaveCardFile.slotBOffset),
                length: UInt(GSSaveCardFile.slotSize)
            )
        else {
            throw GSSaveCardFileError.readFailed
        }
        self.init(metadata: metadata, slotA: slotA, slotB: slotB)
    }

    /// The slots in index order, so a caller can pick one by number.
    public var slots: [GoDData] { [slotA, slotB] }

    /// Concatenates the regions back into a single 0x56000-byte body.
    /// Throws if any region is the wrong length.
    public func assembledBody() throws -> GoDData {
        try Self.requireSize(metadata, GSSaveCardFile.metadataSize, named: "metadata")
        try Self.requireSize(slotA, GSSaveCardFile.slotSize, named: "slotA")
        try Self.requireSize(slotB, GSSaveCardFile.slotSize, named: "slotB")

        let combined = GoDData(byteOrder: .big)
        combined.append(metadata)
        combined.append(slotA)
        combined.append(slotB)
        return combined
    }

    private static func requireSize(_ data: GoDData, _ expected: Int, named: String) throws {
        guard data.length == expected else {
            throw GSSaveCardFileError.invalidRegionSize(
                region: named,
                expected: expected,
                actual: data.length
            )
        }
    }
}

public enum GSSaveCardFileError: Error, CustomStringConvertible {
    case invalidBodySize(expected: Int, actual: Int)
    case invalidRegionSize(region: String, expected: Int, actual: Int)
    case readFailed

    public var description: String {
        switch self {
        case let .invalidBodySize(expected, actual):
            return "XD save card body should be \(expected) bytes but is \(actual)"
        case let .invalidRegionSize(region, expected, actual):
            return "XD save card region '\(region)' should be \(expected) bytes but is \(actual)"
        case .readFailed:
            return "Failed to read an XD save card region"
        }
    }
}
