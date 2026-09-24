//
//  PBRStringDirectory.swift
//  PBR
//
//  The directory that turns a string id into a string.
//
//  PBR's game data never names a string table: a message field holds a
//  global id, and this member of `common.fsys` says which table holds that
//  string and where in it. It is a dense array indexed by id, so every id
//  from 1 to the count has a record — there is no way to express a gap.
//
//  ```
//  +0x00  u32          number of string tables (4 on every retail disc)
//  +0x04  u32          number of string ids
//  +0x08  record × N   one per id, in id order starting at 1:
//                        +0x00  u16  table id
//                        +0x02  u16  index within that table, 1-based
//  ```
//
//  The file is exactly `8 + 4N` bytes. On the PAL disc that is 21,812 ids
//  across four tables — 10011 + 9235 + 173 + 2393 — which accounts for
//  every string in every table exactly once, so the mapping is a bijection
//  rather than a lookup that might leave strings unreachable.
//
//  Retail also happens to keep each table's ids in index order, but nothing
//  in the game depends on that: both halves of a lookup are array indexing.
//  What matters is that a build re-derives this file from the catalogue, so
//  an id keeps its meaning while indexes move underneath it.
//

import Foundation
import GoDFoundation

public struct PBRStringDirectory {
    public static let headerSize = 0x08
    public static let recordSize = 0x04

    public enum Error: GoDError {
        case truncated(ErrorTrace = .init())
        case sizeMismatch(declared: Int, length: Int, ErrorTrace = .init())

        public var description: String {
            switch self {
            case let .truncated(trace):
                return "Error: PBR string directory is too short to hold its header.\n\(trace)"
            case let .sizeMismatch(declared, length, trace):
                return "Error: PBR string directory declares \(declared) strings, which needs "
                    + "\(PBRStringDirectory.headerSize + declared * PBRStringDirectory.recordSize) "
                    + "bytes, but the file is \(length).\n\(trace)"
            }
        }
    }

    /// Where one string id resolves to.
    public struct Record: Equatable {
        /// The `tableID` of the `PBRStringTable` holding the string.
        public let tableID: Int
        /// 1-based index within that table.
        public let index: Int

        public init(tableID: Int, index: Int) {
            self.tableID = tableID
            self.index = index
        }
    }

    /// Number of string tables the game loads — the word at +0x00.
    public var tableCount: Int
    /// One record per id. `records[0]` is string id 1.
    public var records: [Record]

    public init(tableCount: Int, records: [Record]) {
        self.tableCount = tableCount
        self.records = records
    }

    public init(binary: GoDReadable) throws {
        guard let tableCount: UInt32 = binary.readValue(atAddress: 0x00),
              let stringCount: UInt32 = binary.readValue(atAddress: 0x04)
        else {
            throw Error.truncated()
        }
        let declared = Int(stringCount)
        let expected = Self.headerSize + declared * Self.recordSize
        guard binary.length == expected else {
            throw Error.sizeMismatch(declared: declared, length: binary.length)
        }

        self.tableCount = Int(tableCount)
        self.records = []
        self.records.reserveCapacity(declared)
        for id in 1...max(declared, 1) where declared > 0 {
            let offset = Self.headerSize + (id - 1) * Self.recordSize
            guard let table: UInt16 = binary.readValue(atAddress: offset),
                  let index: UInt16 = binary.readValue(atAddress: offset + 2)
            else {
                throw Error.truncated()
            }
            records.append(Record(tableID: Int(table), index: Int(index)))
        }
    }

    /// Where string `id` lives, or nil if the id is outside the directory.
    public func record(forStringID id: Int) -> Record? {
        guard id >= 1, id <= records.count else { return nil }
        return records[id - 1]
    }

    public func rawData() -> GoDData {
        let data = GoDData(byteOrder: .big)
        data.append(UInt32(tableCount))
        data.append(UInt32(records.count))
        for record in records {
            data.append(UInt16(record.tableID))
            data.append(UInt16(record.index))
        }
        return data
    }
}
