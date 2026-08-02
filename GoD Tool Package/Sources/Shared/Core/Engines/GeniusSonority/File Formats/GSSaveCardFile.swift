//
//  GSSaveCardFile.swift
//
//  Splits the body of a Pokémon **XD** `.gci` save into five fixed-size
//  regions:
//
//      0x00000  banner   — 0x2000  CARD banner / icon images + comments
//      0x02000  header0  — 0x2000  slot-header records + flag/state area
//      0x04000  header1  — 0x2000  spare / GBA-exchange bookkeeping
//      0x06000  slotA    — 0x28000 encrypted serialized SystemSaveData
//      0x2E000  slotB    — 0x28000 encrypted serialized SystemSaveData
//
//  Total body size: 0x56000.
//
//  > **Note (2026-04 correction):** an earlier version of this file
//  > claimed Colosseum used the same 0x56000 / 2-slot shape. Cross-
//  > checking against PKHeX's `ColoCrypto.cs` confirms Colosseum's
//  > save is actually 0x60000 bytes with **three** 0x1E000-byte slots
//  > and a flat 0x6000 preamble (no banner / hdr0 / hdr1 split).
//  > Colo splitting now lives in `Colosseum/SaveData/ColoSaveCardFile.swift`.
//  > This type is XD-only; it stays in the GeniusSonority module
//  > because PBR-on-Wii uses a similar (but not identical) GCI shape
//  > and may share constants here in the future.
//

import Foundation
import GoDFoundation

public struct GSSaveCardFile: Equatable {
    public static let bannerOffset: Int = 0x00000
    public static let header0Offset: Int = 0x02000
    public static let header1Offset: Int = 0x04000
    public static let slotAOffset: Int  = 0x06000
    public static let slotBOffset: Int  = 0x2E000

    public static let bannerSize: Int  = 0x02000
    public static let header0Size: Int = 0x02000
    public static let header1Size: Int = 0x02000
    public static let slotSize: Int    = 0x28000

    public static let bodySize: Int = slotBOffset + slotSize  // 0x56000

    public var banner: GoDData
    public var header0: GoDData
    public var header1: GoDData
    public var slotA: GoDData
    public var slotB: GoDData

    public init(banner: GoDData, header0: GoDData, header1: GoDData, slotA: GoDData, slotB: GoDData) {
        self.banner = banner
        self.header0 = header0
        self.header1 = header1
        self.slotA = slotA
        self.slotB = slotB
    }

    /// Splits a 0x56000-byte body into the five named regions. Throws if
    /// the body length doesn't match the expected total — callers should
    /// have already validated that the GCI body matches `blockCount *
    /// 0x2000`.
    public init(body: GoDData) throws {
        guard body.length == GSSaveCardFile.bodySize else {
            throw GSSaveCardFileError.invalidBodySize(
                expected: GSSaveCardFile.bodySize,
                actual: body.length
            )
        }
        guard
            let banner = body.read(
                atAddress: UInt(GSSaveCardFile.bannerOffset),
                length: UInt(GSSaveCardFile.bannerSize)
            ),
            let header0 = body.read(
                atAddress: UInt(GSSaveCardFile.header0Offset),
                length: UInt(GSSaveCardFile.header0Size)
            ),
            let header1 = body.read(
                atAddress: UInt(GSSaveCardFile.header1Offset),
                length: UInt(GSSaveCardFile.header1Size)
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
        self.init(banner: banner, header0: header0, header1: header1, slotA: slotA, slotB: slotB)
    }

    /// Concatenates the five regions back into a single 0x56000-byte
    /// body. Throws if any region is the wrong length.
    public func assembledBody() throws -> GoDData {
        try Self.requireSize(banner, GSSaveCardFile.bannerSize, named: "banner")
        try Self.requireSize(header0, GSSaveCardFile.header0Size, named: "header0")
        try Self.requireSize(header1, GSSaveCardFile.header1Size, named: "header1")
        try Self.requireSize(slotA, GSSaveCardFile.slotSize, named: "slotA")
        try Self.requireSize(slotB, GSSaveCardFile.slotSize, named: "slotB")

        let combined = GoDData(byteOrder: .big)
        combined.append(banner)
        combined.append(header0)
        combined.append(header1)
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
            return "GSSaveCardFile: body size \(actual) does not match expected \(expected) (0x56000)"
        case let .invalidRegionSize(region, expected, actual):
            return "GSSaveCardFile: region '\(region)' size \(actual) does not match expected \(expected)"
        case .readFailed:
            return "GSSaveCardFile: failed to read region from body"
        }
    }
}
