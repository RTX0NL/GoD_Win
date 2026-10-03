//
//  BitFieldLayout.swift
//
//  An integer field split into named bit ranges.
//
//  Bit numbering is **MSB-0**: bit 0 is the most significant bit of the
//  container, the last index the least significant. A `uint8` numbers its
//  bits 0 (`0x80`) through 7 (`0x01`); a `uint16` numbers 0 (`0x8000`)
//  through 15 (`0x0001`). That is PowerPC's own numbering, which is where
//  every bit meaning in this project was read from — an `rlwinm` field in a
//  32-bit register maps straight across, and for a narrower container
//  loaded by `lbz`/`lhz` the index is `rlwinm index - (32 - storage bits)`.
//
//  Never "bit N of byte M": the container is decoded as one integer in the
//  surrounding `GoDData.byteOrder` first, so bit 0 of a big-endian `uint16`
//  is the top bit of the first byte on disc and of a little-endian one the
//  top bit of the second — which is what a load plus a mask does on either
//  platform.
//
//  A layout must tile its storage unit exactly, in index order. Bits
//  nothing reads still carry per-row values, so they are named (and get a
//  column) rather than treated as padding.
//

import Foundation
import GoDFoundation

public struct BitFieldLayout: Equatable {

    /// The integer the bits live in. Its length is the property's length.
    public let storage: IntegerProperties

    /// The named ranges, ascending (most significant first), tiling
    /// `storage` exactly. `issues` reports any way that fails.
    public let fields: [Field]

    public init(storage: IntegerProperties, fields: [Field]) {
        self.storage = storage
        self.fields = fields
    }

    public var bitCount: Int { storage.length * 8 }

    public func field(named name: String) -> Field? {
        fields.first { $0.name == name }
    }

    // MARK: - One named range

    public struct Field: Equatable {

        public let name: String

        /// MSB-0 indices, inclusive. `0...2` is the top three bits.
        public let bits: ClosedRange<Int>

        public let value: Value

        public let description: String?

        public init(
            name: String,
            bits: ClosedRange<Int>,
            value: Value = .unsigned,
            description: String? = nil
        ) {
            self.name = name
            self.bits = bits
            self.value = value
            self.description = description
        }

        public var width: Int { bits.count }

        /// How far the field sits above the storage unit's least
        /// significant bit.
        public func shift(inStorageOf bitCount: Int) -> Int {
            bitCount - 1 - bits.upperBound
        }

        /// The field's bits, in place within the storage unit.
        public func mask(inStorageOf bitCount: Int) -> UInt64 {
            Self.lowMask(width: width) << UInt64(shift(inStorageOf: bitCount))
        }

        /// `width` low bits set. Spelled out rather than `(1 << width) - 1`
        /// because a 64-bit field would overflow the shift.
        static func lowMask(width: Int) -> UInt64 {
            width >= 64 ? UInt64.max : (UInt64(1) << UInt64(width)) - 1
        }

        /// The field's value, read out of the whole storage unit.
        /// Sign-extended from the field's own top bit when `.signed`.
        public func extract(fromStorage storage: UInt64, bitCount: Int) -> Int {
            let raw = (storage >> UInt64(shift(inStorageOf: bitCount))) & Self.lowMask(width: width)
            guard case .signed = value, width < 64 else {
                return Int(bitPattern: UInt(raw))
            }
            let signBit = UInt64(1) << UInt64(width - 1)
            if raw & signBit != 0 {
                return Int(bitPattern: UInt(raw | ~Self.lowMask(width: width)))
            }
            return Int(bitPattern: UInt(raw))
        }

        /// `storage` with this field replaced. The value is truncated to the
        /// field's width, so an out-of-range number never reaches a
        /// neighbour's bits.
        public func insert(_ newValue: Int, intoStorage storage: UInt64, bitCount: Int) -> UInt64 {
            let shift = UInt64(self.shift(inStorageOf: bitCount))
            let truncated = (UInt64(bitPattern: Int64(newValue)) & Self.lowMask(width: width)) << shift
            return (storage & ~mask(inStorageOf: bitCount)) | truncated
        }

        /// Whether `rawValue` fits the field (two's complement when signed).
        public func canHold(_ rawValue: Int) -> Bool {
            if width >= 64 { return true }
            switch value {
            case .signed:
                let half = Int64(1) << Int64(width - 1)
                return Int64(rawValue) >= -half && Int64(rawValue) < half
            case .unsigned, .boolean, .enumeration:
                return rawValue >= 0 && UInt64(rawValue) <= Self.lowMask(width: width)
            }
        }
    }

    // MARK: - What a range means

    public enum Value: Equatable {
        case unsigned
        /// Two's complement within the field's own width.
        case signed
        /// Width must be exactly one bit.
        case boolean
        /// The range's width decides the field's size, not the enum's
        /// `propertyType`; every case has to fit it.
        case enumeration(Enum)

        public var name: String {
            switch self {
            case .unsigned: return "unsigned"
            case .signed: return "signed"
            case .boolean: return "boolean"
            case .enumeration(let definition): return "enum \(definition.name)"
            }
        }
    }

    // MARK: - Reading and writing a whole container

    /// Every field's value, keyed by name.
    public func values(inStorage storage: UInt64) -> [String: Int] {
        var result = [String: Int]()
        for field in fields {
            result[field.name] = field.extract(fromStorage: storage, bitCount: bitCount)
        }
        return result
    }

    public func extract(_ field: Field, fromStorage storage: UInt64) -> Int {
        field.extract(fromStorage: storage, bitCount: bitCount)
    }

    public func insert(_ value: Int, for field: Field, intoStorage storage: UInt64) -> UInt64 {
        field.insert(value, intoStorage: storage, bitCount: bitCount)
    }

    // MARK: - Validation

    /// Every way a declaration can be unusable. Checked where an engine
    /// loads, so a bad layout never reaches a dump.
    public enum Issue: Equatable, CustomStringConvertible {
        case rangeOutsideStorage(field: String, bits: ClosedRange<Int>, storageBits: Int)
        case fieldsOutOfOrder(field: String, after: String)
        case overlappingFields(field: String, with: String)
        case uncoveredBits(ClosedRange<Int>)
        case booleanWiderThanOneBit(field: String, width: Int)
        case enumCaseOutsideRange(field: String, enumName: String, caseName: String, rawValue: Int, width: Int)
        case invalidFieldName(String)
        case duplicateFieldName(String)
        case noFields

        public var description: String {
            func range(_ bits: ClosedRange<Int>) -> String {
                bits.count == 1 ? "\(bits.lowerBound)" : "\(bits.lowerBound):\(bits.upperBound)"
            }
            switch self {
            case let .rangeOutsideStorage(field, bits, storageBits):
                return "field '\(field)' covers bits \(range(bits)), outside the storage unit's 0:\(storageBits - 1)"
            case let .fieldsOutOfOrder(field, after):
                return "field '\(field)' is declared after '\(after)' but covers earlier bits; declare fields most significant first"
            case let .overlappingFields(field, with):
                return "field '\(field)' overlaps '\(with)'"
            case let .uncoveredBits(bits):
                return "bits \(range(bits)) are not covered by any field; name them (a run nothing reads is still a value, not padding)"
            case let .booleanWiderThanOneBit(field, width):
                return "field '\(field)' is a boolean but covers \(width) bits"
            case let .enumCaseOutsideRange(field, enumName, caseName, rawValue, width):
                return "field '\(field)': case '\(caseName)' of enum '\(enumName)' is \(rawValue), which doesn't fit \(width) bit(s)"
            case let .invalidFieldName(name):
                return "'\(name)' isn't a usable field name"
            case let .duplicateFieldName(name):
                return "field '\(name)' is declared more than once"
            case .noFields:
                return "no fields declared"
            }
        }
    }

    public var issues: [Issue] {
        var issues = [Issue]()
        guard !fields.isEmpty else { return [.noFields] }

        for field in fields {
            if !StructDefinition.isValidPropertyName(field.name) {
                issues.append(.invalidFieldName(field.name))
            }
            if field.bits.lowerBound < 0 || field.bits.upperBound >= bitCount {
                issues.append(.rangeOutsideStorage(
                    field: field.name, bits: field.bits, storageBits: bitCount
                ))
            }
            if case .boolean = field.value, field.width != 1 {
                issues.append(.booleanWiderThanOneBit(field: field.name, width: field.width))
            }
            if case .enumeration(let definition) = field.value {
                for enumCase in definition.values where !field.canHold(enumCase.rawValue) {
                    issues.append(.enumCaseOutsideRange(
                        field: field.name,
                        enumName: definition.name,
                        caseName: enumCase.name,
                        rawValue: enumCase.rawValue,
                        width: field.width
                    ))
                }
            }
        }

        let duplicates = Dictionary(grouping: fields.map(\.name), by: { $0 })
            .filter { $0.value.count > 1 }.keys.sorted()
        issues.append(contentsOf: duplicates.map(Issue.duplicateFieldName))

        // Order first, then overlap and coverage. Each stage is only
        // meaningful once the one before it holds: ranges out of bounds
        // would make every gap a restatement of the bounds failure, and a
        // list declared out of order has no coverage worth reporting (the
        // bits may well all be there, just not in reading order).
        guard !issues.contains(where: {
            if case .rangeOutsideStorage = $0 { return true }
            return false
        }) else { return issues }

        for (index, field) in fields.enumerated().dropFirst() {
            let previous = fields[index - 1]
            if field.bits.lowerBound < previous.bits.lowerBound {
                issues.append(.fieldsOutOfOrder(field: field.name, after: previous.name))
            }
        }
        guard !issues.contains(where: {
            if case .fieldsOutOfOrder = $0 { return true }
            return false
        }) else { return issues }

        var nextExpected = 0
        for (index, field) in fields.enumerated() {
            if field.bits.lowerBound < nextExpected {
                issues.append(.overlappingFields(field: field.name, with: fields[index - 1].name))
            } else if field.bits.lowerBound > nextExpected {
                issues.append(.uncoveredBits(nextExpected...(field.bits.lowerBound - 1)))
            }
            nextExpected = max(nextExpected, field.bits.upperBound + 1)
        }
        if nextExpected < bitCount {
            issues.append(.uncoveredBits(nextExpected...(bitCount - 1)))
        }

        return issues
    }

    // MARK: - Range spelling

    /// `"0:2"` for a run, `"3"` for one bit — first index, last index,
    /// ascending. A descending spelling is refused rather than reversed:
    /// one notation, so a declaration can't be read two ways.
    public static func range(from text: String) -> ClosedRange<Int>? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        func index(_ part: String) -> Int? {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part) else { return nil }
            return value
        }
        switch parts.count {
        case 1:
            guard let only = index(parts[0]) else { return nil }
            return only...only
        case 2:
            guard let first = index(parts[0]), let last = index(parts[1]), first <= last else { return nil }
            return first...last
        default:
            return nil
        }
    }

    public static func text(for bits: ClosedRange<Int>) -> String {
        bits.count == 1 ? "\(bits.lowerBound)" : "\(bits.lowerBound):\(bits.upperBound)"
    }
}

extension BitFieldLayout: CustomStringConvertible {
    public var description: String {
        "bits(\(storage.description))"
    }
}

// MARK: - Declaring one in Swift

public extension BitFieldLayout.Field {

    /// An unsigned (or, with `signed`, two's-complement) run of bits.
    static func number(
        name: String,
        bits: ClosedRange<Int>,
        signed: Bool = false,
        description: String? = nil
    ) -> BitFieldLayout.Field {
        .init(name: name, bits: bits, value: signed ? .signed : .unsigned, description: description)
    }

    /// One bit, read and written as a boolean.
    static func flag(
        name: String,
        bit: Int,
        description: String? = nil
    ) -> BitFieldLayout.Field {
        .init(name: name, bits: bit...bit, value: .boolean, description: description)
    }

    /// A run of bits named by an enum. The run's width decides the field's
    /// size, so the enum's own `propertyType` is not consulted — every case
    /// has to fit the run instead.
    static func abstraction(
        name: String,
        bits: ClosedRange<Int>,
        enumeration: Enum,
        description: String? = nil
    ) -> BitFieldLayout.Field {
        .init(name: name, bits: bits, value: .enumeration(enumeration), description: description)
    }
}
