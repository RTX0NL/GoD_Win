//
//  GCIFile.swift
//
//  GameCube `.gci` save export — a 0x40 DEntry header followed by
//  `blockCount * 0x2000` bytes of file body. Both halves round-trip
//  byte-identically; this type is the FileFormat shell that splits
//  the two so callers (project setup, sub-format ops) can reason
//  about them separately.
//
//  See `Documentation/File Formats/Shared/GCI - GameCube Memory Card Save.md`
//  for the full layout.
//

import Foundation
import GoDFoundation

public struct GCIFile: FileFormat {
    public static let formatName = "gci"
    public static let headerSize = 0x40
    public static let blockSize = 0x2000

    public var name: String = "gci"
    public var header: Header
    /// Raw card-file body. For Pokémon Colosseum / XD this is exactly
    /// `0x56000` bytes (banner + two header sectors + slot A + slot B).
    public var body: GoDData

    public init(name: String = "gci", header: Header, body: GoDData) {
        self.name = name
        self.header = header
        self.body = body
    }

    // MARK: - Header

    /// 0x40-byte DEntry. Layout follows Dolphin's `GCMemcardDirEntry`.
    /// Reserved fields are kept explicit so the round-trip is exact.
    public struct Header: Codable, Equatable {
        public var gamecode: String         // 4 chars
        public var makercode: String        // 2 chars
        public var unused1: UInt8           // 0xFF on real cards
        public var bannerAndIconFlags: UInt8
        public var filename: String         // up to 32 chars, NUL-terminated
        public var modtime: UInt32
        public var imageOffset: UInt32
        public var iconFmt: UInt16
        public var animSpeed: UInt16
        public var permissions: UInt8
        public var copyCounter: UInt8
        public var firstBlock: UInt16
        public var blockCount: UInt16
        public var unused2: UInt16          // 0xFFFF on real cards
        public var commentsAddr: UInt32

        public init(
            gamecode: String,
            makercode: String,
            unused1: UInt8 = 0xFF,
            bannerAndIconFlags: UInt8,
            filename: String,
            modtime: UInt32,
            imageOffset: UInt32,
            iconFmt: UInt16,
            animSpeed: UInt16,
            permissions: UInt8,
            copyCounter: UInt8,
            firstBlock: UInt16,
            blockCount: UInt16,
            unused2: UInt16 = 0xFFFF,
            commentsAddr: UInt32
        ) {
            self.gamecode = gamecode
            self.makercode = makercode
            self.unused1 = unused1
            self.bannerAndIconFlags = bannerAndIconFlags
            self.filename = filename
            self.modtime = modtime
            self.imageOffset = imageOffset
            self.iconFmt = iconFmt
            self.animSpeed = animSpeed
            self.permissions = permissions
            self.copyCounter = copyCounter
            self.firstBlock = firstBlock
            self.blockCount = blockCount
            self.unused2 = unused2
            self.commentsAddr = commentsAddr
        }
    }

    // MARK: - Binary parsing

    public init(binaries: [FileData]) throws {
        guard let entry = binaries.first else {
            throw GCIFile.invalidFileError
        }
        let stem = entry.file.path.withoutExtensions
        try self.init(data: entry.data, name: stem.isEmpty ? "gci" : stem)
    }

    public init(data: GoDData, name: String = "gci") throws {
        data.setByteOrder(.big)
        guard data.length >= GCIFile.headerSize else {
            throw GCIFile.invalidFileError
        }

        let raw = data.rawBytes
        let gamecode = GCIFile.readAsciiFixed(raw, at: 0x00, length: 4)
        let makercode = GCIFile.readAsciiFixed(raw, at: 0x04, length: 2)
        let unused1: UInt8 = data.readSafely(atAddress: 0x06)
        let bannerAndIconFlags: UInt8 = data.readSafely(atAddress: 0x07)
        let filename = GCIFile.readAsciiFixed(raw, at: 0x08, length: 32)
        let modtime: UInt32 = data.readSafely(atAddress: 0x28)
        let imageOffset: UInt32 = data.readSafely(atAddress: 0x2C)
        let iconFmt: UInt16 = data.readSafely(atAddress: 0x30)
        let animSpeed: UInt16 = data.readSafely(atAddress: 0x32)
        let permissions: UInt8 = data.readSafely(atAddress: 0x34)
        let copyCounter: UInt8 = data.readSafely(atAddress: 0x35)
        let firstBlock: UInt16 = data.readSafely(atAddress: 0x36)
        let blockCount: UInt16 = data.readSafely(atAddress: 0x38)
        let unused2: UInt16 = data.readSafely(atAddress: 0x3A)
        let commentsAddr: UInt32 = data.readSafely(atAddress: 0x3C)

        let expectedBodyLength = Int(blockCount) * GCIFile.blockSize
        let actualBodyLength = data.length - GCIFile.headerSize
        guard actualBodyLength == expectedBodyLength else {
            throw FileFormatErrors.invalidFileData(
                formatName: GCIFile.formatName,
                .init()
            )
        }

        guard let body = data.read(
            atAddress: UInt(GCIFile.headerSize),
            length: UInt(expectedBodyLength)
        ) else {
            throw GCIFile.invalidFileError
        }

        let header = Header(
            gamecode: gamecode,
            makercode: makercode,
            unused1: unused1,
            bannerAndIconFlags: bannerAndIconFlags,
            filename: filename,
            modtime: modtime,
            imageOffset: imageOffset,
            iconFmt: iconFmt,
            animSpeed: animSpeed,
            permissions: permissions,
            copyCounter: copyCounter,
            firstBlock: firstBlock,
            blockCount: blockCount,
            unused2: unused2,
            commentsAddr: commentsAddr
        )
        self.init(name: name, header: header, body: body)
    }

    // MARK: - Binary serialisation

    public var binaries: [FileData] {
        get throws {
            let combined = try assembled()
            return [FileData(file: File("\(name).gci"), data: combined)]
        }
    }

    /// Serialise the parsed header + body back to a single `.gci` byte
    /// stream. Public so callers (build ops) can grab the bytes without
    /// going through `FileData` wrapping.
    public func assembled() throws -> GoDData {
        var bytes = [UInt8](repeating: 0, count: GCIFile.headerSize)

        // Fixed-length ASCII fields, NUL-padded.
        GCIFile.writeAsciiFixed(header.gamecode, into: &bytes, at: 0x00, length: 4)
        GCIFile.writeAsciiFixed(header.makercode, into: &bytes, at: 0x04, length: 2)
        bytes[0x06] = header.unused1
        bytes[0x07] = header.bannerAndIconFlags
        GCIFile.writeAsciiFixed(header.filename, into: &bytes, at: 0x08, length: 32)

        GCIFile.writeBE(header.modtime, into: &bytes, at: 0x28)
        GCIFile.writeBE(header.imageOffset, into: &bytes, at: 0x2C)
        GCIFile.writeBE(header.iconFmt, into: &bytes, at: 0x30)
        GCIFile.writeBE(header.animSpeed, into: &bytes, at: 0x32)
        bytes[0x34] = header.permissions
        bytes[0x35] = header.copyCounter
        GCIFile.writeBE(header.firstBlock, into: &bytes, at: 0x36)
        GCIFile.writeBE(header.blockCount, into: &bytes, at: 0x38)
        GCIFile.writeBE(header.unused2, into: &bytes, at: 0x3A)
        GCIFile.writeBE(header.commentsAddr, into: &bytes, at: 0x3C)

        let expectedBodyLength = Int(header.blockCount) * GCIFile.blockSize
        guard body.length == expectedBodyLength else {
            throw FileFormatErrors.failedToEncode(
                format: GCIFile.formatName,
                target: "body length \(body.length) does not match blockCount * 0x2000 = \(expectedBodyLength)"
            )
        }

        let combined = GoDData(byteStream: bytes, byteOrder: .big)
        combined.append(body)
        return combined
    }

    private static func writeAsciiFixed(_ string: String, into bytes: inout [UInt8], at offset: Int, length: Int) {
        let utf8 = Array(string.utf8.prefix(length))
        for i in 0..<utf8.count { bytes[offset + i] = utf8[i] }
        // Remaining bytes already 0 from the initial zero-fill.
    }

    /// Reads a fixed-length ASCII field from `bytes`, trimming trailing
    /// NUL padding. Used for gamecode / makercode / filename fields
    /// where the on-disk form is exactly `length` bytes regardless of
    /// the logical string length.
    private static func readAsciiFixed(_ bytes: [UInt8], at offset: Int, length: Int) -> String {
        var slice = Array(bytes[offset..<(offset + length)])
        while let last = slice.last, last == 0x00 {
            slice.removeLast()
        }
        return String(bytes: slice, encoding: .ascii) ?? ""
    }

    private static func writeBE(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset]     = UInt8((value >> 8) & 0xFF)
        bytes[offset + 1] = UInt8(value & 0xFF)
    }

    private static func writeBE(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset]     = UInt8((value >> 24) & 0xFF)
        bytes[offset + 1] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 3] = UInt8(value & 0xFF)
    }

    // MARK: - Editable artifacts

    /// JSON manifest filename (`<name>.gci.json`).
    public var manifestFilename: File { File("\(name).\(GCIFile.formatName).json") }
    /// Body sidecar filename (`<name>.gci.body.bin`). Kept alongside the
    /// JSON so the two together reconstitute the `.gci`.
    public var bodyFilename: File { File("\(name).\(GCIFile.formatName).body.bin") }

    public init(outputs: [FileData]) throws {
        let jsonSuffix = ".\(GCIFile.formatName).json"
        let bodySuffix = ".\(GCIFile.formatName).body.bin"
        guard let manifest = outputs.first(where: { $0.file.path.lowercased().hasSuffix(jsonSuffix) }) else {
            throw GCIFile.missingOutputError(key: "*\(jsonSuffix)")
        }
        guard let bodyEntry = outputs.first(where: { $0.file.path.lowercased().hasSuffix(bodySuffix) }) else {
            throw GCIFile.missingOutputError(key: "*\(bodySuffix)")
        }

        let header: Header
        do {
            header = try JSONDecoder().decode(Header.self, from: Data(manifest.data.rawBytes))
        } catch {
            throw FileFormatErrors.invalidFileData(
                formatName: GCIFile.formatName,
                .init()
            )
        }

        let stem = manifest.file.path.withoutExtensions
        let body = bodyEntry.data
        body.setByteOrder(.big)
        self.init(
            name: stem.isEmpty ? "gci" : stem,
            header: header,
            body: body
        )
    }

    public var outputs: [FileData] {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let manifestData: Data = try encoder.encode(header)
            return [
                FileData(
                    file: manifestFilename,
                    data: GoDData(byteStream: [UInt8](manifestData), byteOrder: .big)
                ),
                FileData(file: bodyFilename, data: body)
            ]
        }
    }
}
