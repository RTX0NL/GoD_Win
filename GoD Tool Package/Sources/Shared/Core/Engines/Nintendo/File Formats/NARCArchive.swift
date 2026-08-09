//
//  NARCArchive.swift
//
//  The Nitro archive. Native to the DS and little-endian there; Battle
//  Revolution carries a big-endian port, which announces itself by spelling
//  its own magic backwards (see `NintendoArchiveFormat`).
//
//  Header:
//
//      0x00  4  magic `NARC` / `CRAN`
//      0x04  2  byte-order mark
//      0x06  2  version
//      0x08  4  total file size
//      0x0C  2  header length (0x10)
//      0x0E  2  section count (3)
//
//  Then three sections laid end to end, each `magic (4) + size (4)` followed
//  by its body. Their four-character codes flip with the archive's, so the
//  little-endian spellings `BTAF`/`BTNF`/`GMIF` read as `FATB`/`FNTB`/`FIMG`
//  in a big-endian file.
//
//      FAT   u16 file count, u16 reserved, then a start/end offset pair per
//            file, both relative to the start of the image body
//      FNT   the name table, or a degenerate root-only entry when the files
//            are addressed purely by index
//      IMG   the file data
//
//  Most real archives are nameless — an entry's index *is* its identity (in
//  PBR's `waza_seq_rev.narc` the index is the move ID) — so index order is
//  the one thing a round trip must never disturb.
//

import Foundation
import GoDFoundation

public struct NARCArchive {

    public struct Entry {
        /// Nil when the archive carries no name table, which is the common
        /// case; such a file is addressed by its index.
        public let name: String?
        public let data: GoDData

        public init(name: String?, data: GoDData) {
            self.name = name
            self.data = data
        }
    }

    /// One of the three sections, whose stored spelling flips with the
    /// archive's byte order exactly like the file magic does.
    enum Section: CaseIterable {
        case fileAllocation, fileName, fileImage

        /// The spelling as written on the DS, the platform NARC is native to.
        var nativeMagic: [UInt8] {
            switch self {
            case .fileAllocation: return Array("BTAF".utf8)
            case .fileName: return Array("BTNF".utf8)
            case .fileImage: return Array("GMIF".utf8)
            }
        }

        func magic(byteOrder: ByteOrder) -> [UInt8] {
            byteOrder == NintendoArchiveFormat.narc.nativeByteOrder
                ? nativeMagic
                : nativeMagic.reversed()
        }

        var displayName: String {
            String(decoding: nativeMagic.reversed(), as: UTF8.self)
        }
    }

    public let byteOrder: ByteOrder
    public let entries: [Entry]
    /// The name-table body exactly as it was read, when this archive has the
    /// degenerate nameless form. Re-emitted verbatim so a round trip can't
    /// disagree with the writer of the original — see `namelessNameTable`.
    public let rawNameTable: [UInt8]?

    public init(byteOrder: ByteOrder, entries: [Entry], rawNameTable: [UInt8]? = nil) {
        self.byteOrder = byteOrder
        self.entries = entries
        self.rawNameTable = rawNameTable
    }

    public var hasNames: Bool {
        entries.contains { $0.name != nil }
    }

    // MARK: - Parse

    public init(data: GoDData, engine: NintendoEngine) throws {
        let bytes = data.rawBytes
        guard let signature = NintendoArchiveSignature.detect(data) else {
            throw NintendoArchiveError.unrecognizedMagic(found: Array(bytes.prefix(4)))
        }
        guard signature.format == .narc else {
            throw NintendoArchiveError.wrongFormat(expected: .narc, found: signature.format)
        }

        let order = signature.byteOrder
        let reader = ArchiveReader(bytes: bytes, byteOrder: order, format: "NARC")
        let headerLength = Int(try reader.u16(0x0C))
        let sectionCount = Int(try reader.u16(0x0E))

        // Sections are laid end to end from the end of the header; their
        // order isn't guaranteed by the format, so they're located by magic.
        var located: [[UInt8]: (offset: Int, size: Int)] = [:]
        var cursor = headerLength
        for _ in 0 ..< sectionCount {
            let magic = try reader.magic(cursor)
            let size = Int(try reader.u32(cursor + 4))
            guard size >= 8 else {
                throw NintendoArchiveError.malformed(
                    format: "NARC", reason: "section at \(cursor) declares a size of \(size)"
                )
            }
            located[magic] = (cursor, size)
            cursor += size
        }

        func section(_ which: Section) throws -> (offset: Int, size: Int) {
            guard let found = located[which.magic(byteOrder: order)] else {
                throw NintendoArchiveError.malformed(
                    format: "NARC", reason: "no \(which.displayName) section"
                )
            }
            return found
        }

        let allocation = try section(.fileAllocation)
        let image = try section(.fileImage)
        let names = try section(.fileName)

        let fileCount = Int(try reader.u16(allocation.offset + 8))
        let imageBase = image.offset + 8

        var parsedNames: [String?] = [String?](repeating: nil, count: fileCount)
        var rawNames: [UInt8]?
        if names.size <= 16 {
            // Root entry only: the files have no names.
            rawNames = try reader.slice(names.offset + 8, names.size - 8)
        } else {
            parsedNames = try Self.readNames(
                reader: reader, offset: names.offset, size: names.size, fileCount: fileCount
            )
        }

        var parsed: [Entry] = []
        parsed.reserveCapacity(fileCount)
        for index in 0 ..< fileCount {
            let entry = allocation.offset + 12 + index * 8
            let start = Int(try reader.u32(entry))
            let end = Int(try reader.u32(entry + 4))
            guard end >= start else {
                throw NintendoArchiveError.malformed(
                    format: "NARC",
                    reason: "file \(index) ends at \(end), before its start of \(start)"
                )
            }
            let payload = try reader.slice(imageBase + start, end - start)
            parsed.append(
                Entry(
                    name: parsedNames[index],
                    data: GoDData(byteStream: payload, byteOrder: order)
                )
            )
        }

        self.byteOrder = order
        self.entries = parsed
        self.rawNameTable = rawNames
    }

    /// Walks the name table's root sub-table for file names.
    ///
    /// A sub-table is a run of length-prefixed names: a control byte under
    /// 0x80 introduces a file name of that many bytes, one at or above 0x80
    /// a directory name followed by a two-byte id, and zero ends the run.
    /// Only the root's files are collected — a NARC nests directories only
    /// rarely, and an entry's index remains its identity either way.
    private static func readNames(
        reader: ArchiveReader, offset: Int, size: Int, fileCount: Int
    ) throws -> [String?] {
        var names = [String?](repeating: nil, count: fileCount)
        let body = offset + 8
        var cursor = body + Int(try reader.u32(body))
        let limit = offset + size
        var index = 0

        while index < fileCount, cursor < limit {
            let control = try reader.u8(cursor)
            cursor += 1
            if control == 0 { break }
            let length = Int(control & 0x7F)
            let name = decodeName(try reader.slice(cursor, length))
            cursor += length
            if control < 0x80 {
                names[index] = name
                index += 1
            } else {
                cursor += 2                       // a subdirectory's id
            }
        }
        return names
    }

    // MARK: - Serialize

    public func data(engine: NintendoEngine) throws -> GoDData {
        let constants = engine.data.narc

        // FIMG body: every file on an alignment boundary, offsets recorded
        // relative to the start of the body.
        var payloads: [UInt8] = []
        var extents: [(start: Int, end: Int)] = []
        for entry in entries {
            let padding = align(payloads.count, to: constants.fileAlignment) - payloads.count
            payloads += [UInt8](repeating: constants.paddingByte, count: padding)
            let start = payloads.count
            payloads += entry.data.rawBytes
            extents.append((start, payloads.count))
        }

        let nameTable = try nameTableBody()

        let allocationSize = 12 + entries.count * 8
        let nameSize = 8 + nameTable.count
        let imageSize = 8 + payloads.count
        let totalSize = constants.headerLength + allocationSize + nameSize + imageSize

        var writer = ArchiveWriter(byteOrder: byteOrder, reserving: totalSize)
        writer.append(raw: NintendoArchiveSignature(format: .narc, byteOrder: byteOrder).magic)
        writer.append(u16: constants.byteOrderMark)
        writer.append(u16: constants.version)
        writer.append(u32: UInt32(totalSize))
        writer.append(u16: UInt16(constants.headerLength))
        writer.append(u16: 3)

        writer.append(raw: Section.fileAllocation.magic(byteOrder: byteOrder))
        writer.append(u32: UInt32(allocationSize))
        writer.append(u16: UInt16(entries.count))
        writer.append(u16: 0)
        for extent in extents {
            writer.append(u32: UInt32(extent.start))
            writer.append(u32: UInt32(extent.end))
        }

        writer.append(raw: Section.fileName.magic(byteOrder: byteOrder))
        writer.append(u32: UInt32(nameSize))
        writer.append(raw: nameTable)

        writer.append(raw: Section.fileImage.magic(byteOrder: byteOrder))
        writer.append(u32: UInt32(imageSize))
        writer.append(raw: payloads)

        return GoDData(byteStream: writer.bytes, byteOrder: byteOrder)
    }

    private func nameTableBody() throws -> [UInt8] {
        // Names win over a replayed table: an archive that was unpacked
        // nameless and then had names added in its manifest should come
        // back named, not silently keep the empty table it arrived with.
        // The two can't conflict on a parsed archive — a raw table is only
        // kept when there were no names to read.
        guard hasNames else { return rawNameTable ?? namelessNameTable() }

        // A single root directory holding every file, each name written as
        // a length byte followed by its bytes, then a terminator.
        var sub = ArchiveWriter(byteOrder: byteOrder)
        for entry in entries {
            let encoded = encodeName(entry.name ?? "")
            guard !encoded.isEmpty, encoded.count < 0x80 else {
                throw NintendoArchiveError.malformed(
                    format: "NARC",
                    reason: "a name table entry must be 1...127 bytes, got \(encoded.count)"
                )
            }
            sub.append(u8: UInt8(encoded.count))
            sub.append(raw: encoded)
        }
        sub.append(u8: 0)

        var body = ArchiveWriter(byteOrder: byteOrder)
        body.append(u32: 8)                       // sub-table starts after this entry
        body.append(u16: 0)                       // first file id
        body.append(u16: 1)                       // one directory: the root
        body.append(raw: sub.bytes)
        return body.bytes
    }

    /// The root-only name table written when there is nothing to name.
    ///
    /// The two 16-bit fields come out in the opposite order on the two
    /// platforms: a big-endian archive stores `1` then `0` where the DS
    /// stores `0` then `1`. Both spellings are reproduced as measured
    /// rather than reconciled — parsing keeps the original bytes anyway
    /// (`rawNameTable`), so this is only reached when building a NARC that
    /// didn't come from one.
    private func namelessNameTable() -> [UInt8] {
        var body = ArchiveWriter(byteOrder: byteOrder)
        body.append(u32: 4)
        if byteOrder == .big {
            body.append(u16: 1)
            body.append(u16: 0)
        } else {
            body.append(u16: 0)
            body.append(u16: 1)
        }
        return body.bytes
    }
}
