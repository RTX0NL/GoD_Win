//
//  HexInt.swift
//
//  An Int that always serializes as a hexadecimal string (`"0x..."`).
//  Used for fields whose values are conceptually bit patterns rather
//  than counts — addresses, offsets, raw instruction words, module IDs,
//  magic numbers — so the on-disc JSON is readable without a mental
//  base conversion.
//
//  Decoder is lenient: accepts `"0x..."` / `"0X..."`, a plain decimal
//  string, or a JSON number. That lets us adopt the type on fields
//  whose JSON used to be a bare integer without breaking old files
//  someone already has on disk.
//
//  Encoder always emits the canonical `"0x..."` form (lowercase, no
//  padding) so round-tripping through the type normalizes historic
//  decimal JSON to hex on the next write.
//

import Foundation

public struct HexInt: Codable, Equatable, Hashable, ExpressibleByIntegerLiteral,
                      CustomStringConvertible, CustomDebugStringConvertible {
    public var value: Int

    public init(_ value: Int) { self.value = value }
    public init(integerLiteral value: Int) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(Int.self) {
            self.value = raw
            return
        }
        let string = try container.decode(String.self)
        let trimmed = string.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "_", with: "")
        if let parsed = HexInt.parse(trimmed) {
            self.value = parsed
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "HexInt cannot parse \(string.debugDescription)"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }

    /// Canonical encoding: `"0x..."` in lowercase, negative values
    /// prefixed with `-` (the bit-pattern form `0xFFFFFFFF…` is left to
    /// the caller — wrap unsigned semantics in HexUInt-style sites).
    public var hexString: String {
        if value < 0 {
            return "-0x" + String(-value, radix: 16, uppercase: false)
        }
        return "0x" + String(value, radix: 16, uppercase: false)
    }

    public var description: String { hexString }
    public var debugDescription: String { "HexInt(\(hexString))" }

    // MARK: - Parsing

    /// Parse a `"0x..."`, `"-0x..."`, or plain decimal string. Returns
    /// nil if neither form matches. Underscores have already been
    /// stripped by the caller.
    private static func parse(_ text: String) -> Int? {
        var s = text
        var negative = false
        if s.hasPrefix("-") {
            negative = true
            s.removeFirst()
        } else if s.hasPrefix("+") {
            s.removeFirst()
        }
        let magnitude: Int?
        if s.hasPrefix("0x") || s.hasPrefix("0X") {
            magnitude = Int(s.dropFirst(2), radix: 16)
        } else {
            magnitude = Int(s, radix: 10)
        }
        guard let m = magnitude else { return nil }
        return negative ? -m : m
    }
}

// MARK: - Conversions

public extension HexInt {
    /// Convenience for working with unsigned fixed-width fields without
    /// the caller having to repeat a bit-pattern cast.
    init(_ value: UInt32) { self.value = Int(value) }
    init(_ value: UInt16) { self.value = Int(value) }
    init(_ value: UInt8)  { self.value = Int(value) }
    init(_ value: Int32)  { self.value = Int(value) }

    var uint32: UInt32 { UInt32(truncatingIfNeeded: value) }
    var uint16: UInt16 { UInt16(truncatingIfNeeded: value) }
    var uint8:  UInt8  { UInt8(truncatingIfNeeded: value) }
    var int32:  Int32  { Int32(truncatingIfNeeded: value) }
}

// MARK: - Comparison with plain Int

public extension HexInt {
    static func == (lhs: HexInt, rhs: Int) -> Bool { lhs.value == rhs }
    static func == (lhs: Int, rhs: HexInt) -> Bool { lhs == rhs.value }
}
