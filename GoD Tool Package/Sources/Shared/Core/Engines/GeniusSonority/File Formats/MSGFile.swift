//
//  MSGFile.swift
//
//  Pokemon Colosseum / XD message string table.
//
//  Header (big-endian):
//    0x00  UInt32   reservedPrefix  (varies per file; not a magic)
//    0x04  UInt16   entry count
//    0x06  2 bytes  region code (ASCII, e.g. "US", "JP")
//    0x08  8 bytes  reservedSuffix (observed all-zero; preserved verbatim)
//
//  Entry table at 0x10, `count` × 8 bytes:
//    UInt32 id (low 20 bits effective), UInt32 offset (file-relative)
//
//  Strings: GS-encoded UTF-16 BE, word-aligned, terminator 0x0000.
//  Specials: 0xFFFF + 1-byte code + 0..4 param bytes (Colo/XD share layout).
//

import Foundation
import GoDFoundation

public struct MSGFile: FileFormat, Equatable {
    public static let formatName = "msg"

    public var name: String = "msg"

    /// Colo and XD share the binary layout. The variant only affects how
    /// control codes are rendered to / parsed from the pretty JSON form.
    public enum Variant: String, Codable {
        case colo
        case xd

        var stringFormat: StringFormats {
            switch self {
            case .colo: return .gsColo
            case .xd:   return .gsXD
            }
        }
    }

    public struct Entry: Codable, Equatable {
        public let id: UInt32
        public var string: GSString

        public init(id: UInt32, string: GSString) {
            self.id = id
            self.string = string
        }
    }

    public var variant: Variant
    /// Raw bytes 0x00..0x03 preserved for byte-identical rebuild.
    public var reservedPrefix: [UInt8]
    /// Raw bytes 0x06..0x07 (region code). Two ASCII bytes in the samples
    /// observed, but kept as raw bytes to support anything.
    public var region: [UInt8]
    /// Raw bytes 0x08..0x0F (observed all-zero). Preserved verbatim.
    public var reservedSuffix: [UInt8]
    public var entries: [Entry]

    public init(
        variant: Variant,
        reservedPrefix: [UInt8] = [0, 0, 0, 0],
        region: [UInt8] = [0x55, 0x53],         // "US"
        reservedSuffix: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0],
        entries: [Entry] = []
    ) {
        self.variant = variant
        self.reservedPrefix = reservedPrefix
        self.region = region
        self.reservedSuffix = reservedSuffix
        self.entries = entries
    }

    // MARK: - FileFormat (binary)

    /// Parse from a single raw `.msg` binary. Defaults to XD control-code
    /// semantics; use `init(binary:variant:)` for Colo.
    public init(binaries: [FileData]) throws {
        guard let first = binaries.first else {
            throw MSGFile.invalidFileError
        }
        let stem = first.file.fileName.withoutExtensions
        try self.init(binary: first.data, variant: .xd, name: stem.isEmpty ? "msg" : stem)
    }

    public init(binary: GoDData, variant: Variant, name: String = "msg") throws {
        let data = binary.copy
        data.setByteOrder(.big)
        guard data.length >= 0x10 else { throw MSGFile.invalidFileError }

        let prefix: UInt32 = data.readValue(atAddress: 0x00) ?? 0
        guard let count: UInt16 = data.readValue(atAddress: 0x04) else {
            throw MSGFile.invalidFileError
        }
        let regionBytes = data.read(atAddress: 0x06, length: 2)?.rawBytes ?? [0, 0]
        let suffixBytes = data.read(atAddress: 0x08, length: 8)?.rawBytes
            ?? [UInt8](repeating: 0, count: 8)

        let tableStart = 0x10
        let tableEnd = tableStart + Int(count) * 8
        guard data.length >= tableEnd else { throw MSGFile.invalidFileError }

        var entries: [Entry] = []
        entries.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            let entryOffset = tableStart + i * 8
            guard let rawId: UInt32 = data.readValue(atAddress: entryOffset),
                  let stringOffset: UInt32 = data.readValue(atAddress: entryOffset + 4) else {
                throw MSGFile.invalidFileError
            }
            let string = data.readGSStringSafely(
                atAddress: Int(stringOffset),
                format: variant.stringFormat
            )
            entries.append(Entry(id: rawId, string: string))
        }

        self.init(
            variant: variant,
            reservedPrefix: prefixBytes(prefix),
            region: regionBytes,
            reservedSuffix: suffixBytes,
            entries: entries
        )
        self.name = name
    }

    public var binaries: [FileData] {
        get throws {
            [FileData(file: File("\(name).\(MSGFile.formatName)"), data: try computedBinaryData)]
        }
    }

    private var computedBinaryData: GoDData {
        get throws {
            let out = GoDData(byteOrder: .big)

            // Header bytes 0x00..0x03
            for b in paddedBytes(reservedPrefix, to: 4) { out.append(UInt8(b)) }
            // Header bytes 0x04..0x05 — count. The field is a u16, so an
            // over-large table would trap on the conversion; reject it.
            guard entries.count <= 0xFFFF else {
                throw FileFormatErrors.failedToEncode(
                    format: MSGFile.formatName,
                    target: "entry count \(entries.count) exceeds the u16 header field maximum (65535)"
                )
            }
            out.append(UInt16(entries.count))
            // Header bytes 0x06..0x07 — region
            for b in paddedBytes(region, to: 2) { out.append(UInt8(b)) }
            // Header bytes 0x08..0x0F — reserved suffix
            for b in paddedBytes(reservedSuffix, to: 8) { out.append(UInt8(b)) }

            // Sort entries by ID so the table always comes out in a
            // deterministic order, matching the legacy tool's behaviour.
            let sorted = entries.sorted(by: { $0.id < $1.id })

            // Reserve space for the entry table. We know each string's
            // offset only after we decide the layout — compute offsets by
            // laying strings out sequentially after the table.
            let tableStart = 0x10
            let tableLength = sorted.count * 8
            var stringStart = tableStart + tableLength

            var stringBlobs: [(id: UInt32, offset: Int, bytes: [UInt8])] = []
            for entry in sorted {
                let bytes = entry.string.rawData(byteOrder: .big).rawBytes
                stringBlobs.append((entry.id, stringStart, bytes))
                // Each string is terminated by a UTF-16 null word, and the
                // next entry starts on a 2-byte boundary.
                stringStart += bytes.count + 2
                if stringStart % 2 != 0 { stringStart += 1 }
            }

            // Write entry table
            for blob in stringBlobs {
                out.append(blob.id)
                out.append(UInt32(blob.offset))
            }

            // Write string pool
            for blob in stringBlobs {
                // Pad any gap (currently none — offsets flow in sequence).
                while out.length < blob.offset {
                    out.append(UInt8(0))
                }
                for b in blob.bytes { out.append(b) }
                // Null terminator
                out.append(UInt16(0))
            }

            return out
        }
    }

    // MARK: - FileFormat (outputs / JSON)

    public init(outputs: [FileData]) throws {
        let dict = outputs.byFile
        let suffix = ".\(MSGFile.formatName).json"
        guard let jsonKey = dict.keys.first(where: { $0.path.hasSuffix(suffix) }) else {
            throw MSGFile.missingOutputError(key: "*\(suffix)")
        }
        let stem = String(jsonKey.path.dropLast(suffix.count))
        guard let jsonData = dict[jsonKey] else {
            throw MSGFile.missingOutputError(key: jsonKey.path)
        }
        let decoder = JSONDecoder()
        let dto = try decoder.decode(DTO.self, from: jsonData.data)
        self.init(
            variant: dto.variant,
            reservedPrefix: MSGFile.bytesFromHex(dto.reservedPrefix) ?? [0, 0, 0, 0],
            region: MSGFile.bytesFromRegion(dto.region) ?? [0x55, 0x53],
            reservedSuffix: MSGFile.bytesFromHex(dto.reservedSuffix)
                ?? [UInt8](repeating: 0, count: 8),
            entries: dto.entries.map { e in
                Entry(
                    id: e.id,
                    string: GSString(string: e.text, format: dto.variant.stringFormat)
                )
            }
        )
        self.name = stem.isEmpty ? "msg" : stem
    }

    public var outputs: [FileData] {
        get throws {
            let dto = DTO(
                variant: variant,
                reservedPrefix: MSGFile.hexFromBytes(reservedPrefix),
                region: MSGFile.regionFromBytes(region),
                reservedSuffix: MSGFile.hexFromBytes(reservedSuffix),
                entries: entries.map { e in
                    DTO.EntryDTO(id: e.id, text: e.string.string(format: variant.stringFormat))
                }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data: Data = try encoder.encode(dto)
            return [FileData(file: jsonFilename, data: GoDData(data: data, byteOrder: .big))]
        }
    }

    // MARK: - JSON DTO

    private struct DTO: Codable {
        let variant: Variant
        let reservedPrefix: String   // hex
        let region: String           // ASCII if printable, else hex
        let reservedSuffix: String   // hex
        let entries: [EntryDTO]

        struct EntryDTO: Codable {
            let id: UInt32
            let text: String
        }
    }

    // MARK: - Helpers

    private static func hexFromBytes(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }

    private static func bytesFromHex(_ hex: String) -> [UInt8]? {
        let clean = hex.trimmingCharacters(in: .whitespaces)
        guard clean.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard let byte = UInt8(clean[idx..<next], radix: 16) else { return nil }
            out.append(byte)
            idx = next
        }
        return out
    }

    /// If `bytes` are two ASCII printables, render as a 2-char string;
    /// otherwise fall back to hex so the roundtrip is lossless.
    private static func regionFromBytes(_ bytes: [UInt8]) -> String {
        if bytes.count == 2, bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) {
            return String(decoding: bytes, as: UTF8.self)
        }
        return hexFromBytes(bytes)
    }

    private static func bytesFromRegion(_ region: String) -> [UInt8]? {
        if region.count == 2, region.allSatisfy({ $0.isASCII }) {
            return Array(region.utf8)
        }
        return bytesFromHex(region)
    }
}

// MARK: - Free helpers

private func prefixBytes(_ value: UInt32) -> [UInt8] {
    [
        UInt8((value >> 24) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >>  8) & 0xFF),
        UInt8( value        & 0xFF)
    ]
}

private func paddedBytes(_ bytes: [UInt8], to length: Int) -> [UInt8] {
    if bytes.count == length { return bytes }
    if bytes.count > length  { return Array(bytes.prefix(length)) }
    return bytes + [UInt8](repeating: 0, count: length - bytes.count)
}
