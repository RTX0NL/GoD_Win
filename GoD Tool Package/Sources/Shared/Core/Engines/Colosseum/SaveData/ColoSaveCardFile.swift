//
//  ColoSaveCardFile.swift
//
//  Splits the body of a Pokémon **Colosseum** `.gci` save into:
//
//      0x00000  preamble — 0x6000 bytes (memory-card metadata; we
//                          treat as opaque)
//      0x06000  slot 0   — 0x1E000 encrypted save slot
//      0x24000  slot 1   — 0x1E000 encrypted save slot
//      0x42000  slot 2   — 0x1E000 encrypted save slot
//
//  Total body size: 0x60000.
//
//  Layout taken from PKHeX's `ColoCrypto.cs`
//  (`SLOT_START = 0x6000`, `SLOT_SIZE = 0x1E000`, `SLOT_COUNT = 3`,
//  `SAVE_SIZE = SLOT_START + SLOT_SIZE * SLOT_COUNT = 0x60000`).
//  This is fundamentally different from XD's 2-slot 0x56000 shape —
//  see `GeniusSonority/File Formats/GSSaveCardFile.swift` for that
//  one.
//

import Foundation
import GoDFoundation

public struct ColoSaveCardFile: Equatable {
    public static let preambleOffset: Int = 0x00000
    public static let preambleSize: Int = 0x06000
    public static let slotOffset0: Int = 0x06000
    public static let slotOffset1: Int = 0x24000
    public static let slotOffset2: Int = 0x42000
    public static let slotSize: Int = 0x1E000
    public static let slotCount: Int = 3
    public static let bodySize: Int = 0x60000

    public var preamble: GoDData
    public var slots: [GoDData]   // exactly 3 entries, each 0x1E000 bytes

    public init(preamble: GoDData, slots: [GoDData]) {
        self.preamble = preamble
        self.slots = slots
    }

    public init(body: GoDData) throws {
        guard body.length == ColoSaveCardFile.bodySize else {
            throw ColoSaveCardFileError.invalidBodySize(
                expected: ColoSaveCardFile.bodySize,
                actual: body.length
            )
        }
        guard let preamble = body.read(
            atAddress: UInt(ColoSaveCardFile.preambleOffset),
            length: UInt(ColoSaveCardFile.preambleSize)
        ) else {
            throw ColoSaveCardFileError.readFailed
        }
        var slots: [GoDData] = []
        for i in 0..<ColoSaveCardFile.slotCount {
            let off = ColoSaveCardFile.preambleSize + i * ColoSaveCardFile.slotSize
            guard let slot = body.read(
                atAddress: UInt(off),
                length: UInt(ColoSaveCardFile.slotSize)
            ) else {
                throw ColoSaveCardFileError.readFailed
            }
            slots.append(slot)
        }
        self.init(preamble: preamble, slots: slots)
    }

    public func assembledBody() throws -> GoDData {
        try Self.requireSize(preamble, ColoSaveCardFile.preambleSize, named: "preamble")
        guard slots.count == ColoSaveCardFile.slotCount else {
            throw ColoSaveCardFileError.invalidSlotCount(
                expected: ColoSaveCardFile.slotCount,
                actual: slots.count
            )
        }
        for (i, slot) in slots.enumerated() {
            try Self.requireSize(slot, ColoSaveCardFile.slotSize, named: "slot \(i)")
        }
        let combined = GoDData(byteOrder: .big)
        combined.append(preamble)
        for slot in slots { combined.append(slot) }
        return combined
    }

    /// Picks the slot with the highest counter at slot[0x04..0x08].
    /// Mirrors PKHeX `ColoCrypto.DetectLatest`. Counter is signed
    /// big-endian Int32 (PKHeX uses Int32).
    public func detectLatestIndex() -> Int? {
        var bestIndex = -1
        var bestCounter: Int32 = .min
        for (i, slot) in slots.enumerated() {
            let raw = slot.rawBytes
            let u: UInt32 = (UInt32(raw[4]) << 24)
                          | (UInt32(raw[5]) << 16)
                          | (UInt32(raw[6]) << 8)
                          |  UInt32(raw[7])
            let counter = Int32(bitPattern: u)
            if counter > bestCounter {
                bestCounter = counter
                bestIndex = i
            }
        }
        return bestIndex >= 0 ? bestIndex : nil
    }

    private static func requireSize(_ data: GoDData, _ expected: Int, named: String) throws {
        guard data.length == expected else {
            throw ColoSaveCardFileError.invalidRegionSize(
                region: named, expected: expected, actual: data.length
            )
        }
    }
}

public enum ColoSaveCardFileError: Error, CustomStringConvertible {
    case invalidBodySize(expected: Int, actual: Int)
    case invalidRegionSize(region: String, expected: Int, actual: Int)
    case invalidSlotCount(expected: Int, actual: Int)
    case readFailed

    public var description: String {
        switch self {
        case let .invalidBodySize(expected, actual):
            return "ColoSaveCardFile: body size \(actual) does not match expected \(expected) (0x60000)"
        case let .invalidRegionSize(region, expected, actual):
            return "ColoSaveCardFile: region '\(region)' size \(actual) does not match expected \(expected)"
        case let .invalidSlotCount(expected, actual):
            return "ColoSaveCardFile: expected \(expected) slots, got \(actual)"
        case .readFailed:
            return "ColoSaveCardFile: failed to read region from body"
        }
    }
}
