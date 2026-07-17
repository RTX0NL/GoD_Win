//
//  ColosseumSaveSlot.swift
//
//  Pokémon Colosseum save-slot scaffold. Today this only reads the
//  plaintext slot header (magic + counter) — richer sub-block
//  extraction is driven by the engine's `saveSections` in the dump
//  operation. See
//  `Documentation/File Formats/Colosseum/Colosseum Save File.md`
//  for the open work.
//
//  Colo's slot layout is *different* from XD's. The legacy GoD tool
//  addresses sub-blocks by hard-coded absolute offsets instead of via
//  the 24-entry TOC at +0x38 that XD uses, so this type is genuinely
//  separate from `XDSaveSlot` rather than a re-skin of it.
//
//  Slot framing (post-decrypt, big-endian) per `ColoSaveCipher` /
//  PKHeX `ColoCrypto.cs`:
//      0x00..0x04   magic (4 bytes)        — plaintext
//      0x04..0x08   save counter (u32 BE)  — plaintext
//      0x08..0x20   further header fields (checksum at 0x0C, …)
//  A slot is `ColoSaveCipher.slotSize` (0x1E000) bytes — NOT the
//  0x28000 that XD uses.
//
//  Integrity is validated by the cipher's SHA-1 header/body checksums
//  (surfaced by `ColoSaveCipher.decrypt`), so this type intentionally
//  does *not* gate on a hard-coded magic constant: the real Colo magic
//  has not been verified against a genuine save, and a wrong guess
//  would reject valid slots. The magic bytes are captured verbatim as
//  metadata instead.
//

import Foundation
import GoDFoundation

public struct ColosseumSaveSlot: Equatable {
    public static let slotSize: Int = ColoSaveCipher.slotSize

    public struct Header: Codable, Equatable {
        /// The 4-byte plaintext identifier at slot[0x00..0x04].
        /// Captured as-is; not validated against a fixed constant.
        public var magic: [UInt8]
        public var counter: UInt32

        public init(magic: [UInt8], counter: UInt32) {
            self.magic = magic
            self.counter = counter
        }
    }

    public var raw: GoDData
    public let header: Header

    public init(raw: GoDData) throws {
        guard raw.length == ColosseumSaveSlot.slotSize else {
            throw ColosseumSaveSlotError.invalidSlotSize(
                expected: ColosseumSaveSlot.slotSize,
                actual: raw.length
            )
        }
        raw.setByteOrder(.big)

        let bytes = raw.rawBytes
        let magic = Array(bytes[0x00..<0x04])
        let counter: UInt32 = raw.readSafely(atAddress: 0x04)

        self.raw = raw
        self.header = Header(magic: magic, counter: counter)
    }

    public func assemble() -> GoDData {
        return raw
    }
}

public enum ColosseumSaveSlotError: Error, CustomStringConvertible {
    case invalidSlotSize(expected: Int, actual: Int)

    public var description: String {
        switch self {
        case let .invalidSlotSize(expected, actual):
            return "ColosseumSaveSlot: slot size \(actual) does not match expected \(expected) (0x1E000)"
        }
    }
}
