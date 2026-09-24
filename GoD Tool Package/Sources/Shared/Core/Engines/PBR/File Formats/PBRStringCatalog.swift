//
//  PBRStringCatalog.swift
//  PBR
//
//  Every string on the disc, in one editable document.
//
//  A PBR string is addressed by a global id (`PBRStringDirectory`), stored
//  in one of a handful of `MESG` tables (`PBRStringTable`), and shipped once
//  per language. Splitting that across files the way the disc does makes the
//  one thing an editor cares about — "what does string 11 say?" — the one
//  thing you cannot see. So the catalogue inverts it: a section per table,
//  and inside it a row per id carrying that id's text in every language.
//
//  Almost everything is derived rather than stored, because anything stored
//  twice can disagree:
//
//  * a table's id is its position in `tables`, counting from 1;
//  * a string's index is its row's position in `strings`, counting from 1;
//  * the string count is however many rows there are;
//  * the directory is rebuilt from the rows.
//
//  Which leaves ids as the only stable reference, and indexes as an
//  implementation detail the build owns. Move a row and every id that points
//  into that table still resolves; add a row at the end and nothing before
//  it shifts. The disc's own tables happen to be in id order, and a dump of
//  an untouched disc reproduces that, but nothing requires it.
//
//  `files` names the binaries each language's copy is written back to — a
//  list, because two of PBR's tables ship a byte-identical second copy in
//  another archive (`mes_fight_*` for table 2, `mes_name_*` for table 3) and
//  writing only one leaves the other stale.
//

import Foundation
import GoDFoundation

public struct PBRStringCatalog: Codable, Equatable {

    public enum Error: GoDError {
        case tableIDsNotContiguous(found: [Int], ErrorTrace = .init())
        case languageResumesAfterItsEnd(tableID: Int, id: Int, code: String, ErrorTrace = .init())
        case unexpectedLanguage(tableID: Int, id: Int, code: String, ErrorTrace = .init())
        case duplicateStringID(id: Int, ErrorTrace = .init())
        case stringIDsNotContiguous(missing: Int, count: Int, ErrorTrace = .init())
        case unreachableString(tableID: Int, index: Int, ErrorTrace = .init())
        case noTables(ErrorTrace = .init())

        public var description: String {
            switch self {
            case let .tableIDsNotContiguous(found, trace):
                return "Error: PBR string tables must be numbered from 1 with no gaps; found \(found).\n\(trace)"
            case let .languageResumesAfterItsEnd(tableID, id, code, trace):
                return "Error: PBR string \(id) (table \(tableID)) has \(code) text, but an "
                    + "earlier string doesn't — a language's strings have to be an unbroken run "
                    + "from the start of the table, because every language shares one index per "
                    + "id. Fill the gap, or clear the \(code) text from here on.\n\(trace)"
            case let .unexpectedLanguage(tableID, id, code, trace):
                return "Error: PBR string \(id) (table \(tableID)) carries \(code) text, but the "
                    + "table has no \(code) file to write it to.\n\(trace)"
            case let .duplicateStringID(id, trace):
                return "Error: PBR string id \(id) is listed more than once. An id belongs to "
                    + "exactly one table.\n\(trace)"
            case let .stringIDsNotContiguous(missing, count, trace):
                return "Error: PBR string id \(missing) is missing. The directory is an array "
                    + "indexed by id, so ids must run from 1 to \(count) with no gaps — add new "
                    + "strings at the end, and blank a string's text rather than removing it.\n\(trace)"
            case let .unreachableString(tableID, index, trace):
                return "Error: PBR string table \(tableID) index \(index) has no id pointing at "
                    + "it, so it could never be displayed.\n\(trace)"
            case let .noTables(trace):
                return "Error: a PBR string catalogue needs at least one table.\n\(trace)"
            }
        }
    }

    /// One language's copy of a table, and the binaries it is written to.
    public struct LanguageFile: Codable, Equatable {
        /// The four-character code stored at +0x0C of the binary.
        public let code: String
        /// Paths relative to the unpack root. More than one when the disc
        /// ships the same table in a second archive.
        public let paths: [String]

        public init(code: String, paths: [String]) {
            self.code = code
            self.paths = paths
        }
    }

    /// A string's text, per language — or one text used for every language,
    /// which is worth allowing because plenty of names really are identical
    /// across them. Only accepted on the way in; a dump always writes the
    /// full map so a re-dump doesn't reshuffle the document.
    public enum Text: Codable, Equatable {
        case everyLanguage(String)
        case perLanguage([String: String])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let shared = try? container.decode(String.self) {
                self = .everyLanguage(shared)
            } else {
                self = .perLanguage(try container.decode([String: String].self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .everyLanguage(shared): try container.encode(shared)
            case let .perLanguage(texts): try container.encode(texts)
            }
        }

        /// The text for `code`, or nil when this row doesn't carry it.
        public func text(for code: String) -> String? {
            switch self {
            case let .everyLanguage(shared): return shared
            case let .perLanguage(texts): return texts[code]
            }
        }

        /// The codes this row names, or nil when it applies to all of them.
        public var codes: Set<String>? {
            switch self {
            case .everyLanguage: return nil
            case let .perLanguage(texts): return Set(texts.keys)
            }
        }
    }

    /// One string: its global id and its text.
    public struct Entry: Codable, Equatable {
        public let id: Int
        public let text: Text

        public init(id: Int, text: Text) {
            self.id = id
            self.text = text
        }
    }

    /// One `MESG` table across every language. Its table id is its position
    /// in `tables`, counting from 1.
    public struct Table: Codable, Equatable {
        public let files: [LanguageFile]
        public let strings: [Entry]

        public init(files: [LanguageFile], strings: [Entry]) {
            self.files = files
            self.strings = strings
        }
    }

    /// Path of the directory binary, relative to the unpack root.
    public var directory: String
    public var tables: [Table]

    public init(directory: String, tables: [Table]) {
        self.directory = directory
        self.tables = tables
    }
}

// MARK: - Dumping

public extension PBRStringCatalog {

    /// One language's parsed copy of a table.
    struct LanguageSource {
        public let code: String
        public let paths: [String]
        public let table: PBRStringTable

        public init(code: String, paths: [String], table: PBRStringTable) {
            self.code = code
            self.paths = paths
            self.table = table
        }
    }

    /// One table, in every language the disc ships it in.
    struct TableSource {
        public let tableID: Int
        public let languages: [LanguageSource]

        public init(tableID: Int, languages: [LanguageSource]) {
            self.tableID = tableID
            self.languages = languages
        }
    }

    /// Builds the catalogue from the disc's own files.
    ///
    /// The directory decides which row each string becomes: a table's rows
    /// come out in index order, each labelled with the id that points at it.
    /// A string no id points at, or an id pointing past the end of its
    /// table, is an error rather than something to paper over — either means
    /// the directory and the tables disagree, and a build from a catalogue
    /// that hid it would silently drop text.
    static func make(
        directory: PBRStringDirectory,
        directoryPath: String,
        tables sources: [TableSource]
    ) throws -> PBRStringCatalog {
        guard !sources.isEmpty else { throw Error.noTables() }
        let ordered = sources.sorted { $0.tableID < $1.tableID }
        guard ordered.map(\.tableID) == Array(1...ordered.count) else {
            throw Error.tableIDsNotContiguous(found: ordered.map(\.tableID))
        }
        // The directory says how many tables the game loads, and a disc can
        // declare one it doesn't ship: the JP disc declares four and has
        // three, having dropped the battle tutorial. The missing one still
        // occupies its slot, or every table after it would be renumbered, so
        // it becomes an empty section — no files, no strings — that the
        // build writes nothing for and counts all the same.
        let tableCount = max(ordered.count, directory.tableCount)

        // One index addresses every language, but the languages need not all
        // reach it: the US disc's English tables run past the others (9995
        // strings to 9991 in table 1, 9233 to 8737 in table 2), with the
        // shorter ones simply stopping — their last entries are empty and
        // only four ids reach past them. So a table is as long as its
        // longest language, and a row carries text only for the languages
        // that reach it.
        var counts = [Int: Int]()
        for source in ordered {
            counts[source.tableID] = source.languages.map(\.table.strings.count).max() ?? 0
        }

        // Walk the directory in id order, dropping each id into its table's
        // row for the index it names.
        var rows = [Int: [Entry?]]()
        for source in ordered {
            rows[source.tableID] = Array(repeating: nil, count: counts[source.tableID] ?? 0)
        }
        for (position, record) in directory.records.enumerated() {
            let id = position + 1
            guard let source = ordered.first(where: { $0.tableID == record.tableID }),
                  let count = counts[record.tableID],
                  record.index >= 1, record.index <= count
            else {
                throw Error.unreachableString(tableID: record.tableID, index: record.index)
            }
            if rows[record.tableID]?[record.index - 1] != nil {
                throw Error.duplicateStringID(id: id)
            }
            var texts = [String: String]()
            for language in source.languages where record.index <= language.table.strings.count {
                texts[language.code] = language.table.strings[record.index - 1].string(format: .gsPBR)
            }
            rows[record.tableID]?[record.index - 1] = Entry(id: id, text: .perLanguage(texts))
        }

        var catalogTables = [Table]()
        for source in ordered {
            let filled = rows[source.tableID] ?? []
            var strings = [Entry]()
            strings.reserveCapacity(filled.count)
            for (offset, entry) in filled.enumerated() {
                guard let entry else {
                    throw Error.unreachableString(tableID: source.tableID, index: offset + 1)
                }
                strings.append(entry)
            }
            catalogTables.append(Table(
                files: source.languages.map { LanguageFile(code: $0.code, paths: $0.paths) },
                strings: strings
            ))
        }
        while catalogTables.count < tableCount {
            catalogTables.append(Table(files: [], strings: []))
        }
        return PBRStringCatalog(directory: directoryPath, tables: catalogTables)
    }
}

// MARK: - Building

public extension PBRStringCatalog {

    /// One language's rebuilt table, and where it goes.
    struct ResolvedLanguage {
        public let code: String
        public let paths: [String]
        public let strings: [GSString]
    }

    /// One table's rebuilt copies.
    struct ResolvedTable {
        public let tableID: Int
        public let languages: [ResolvedLanguage]
    }

    /// The disc's files, rebuilt from the catalogue.
    struct Resolution {
        public let directory: PBRStringDirectory
        public let directoryPath: String
        public let tables: [ResolvedTable]
    }

    /// Turns the catalogue back into a directory and a set of tables.
    ///
    /// Validates what the format can't express before writing anything, so
    /// a bad edit fails with the id that caused it rather than producing a
    /// disc whose text is subtly wrong.
    func resolve() throws -> Resolution {
        guard !tables.isEmpty else { throw Error.noTables() }

        var records = [Int: PBRStringDirectory.Record]()
        var resolved = [ResolvedTable]()

        for (position, table) in tables.enumerated() {
            let tableID = position + 1
            let codes = table.files.map(\.code)
            var strings = [String: [GSString]]()
            for code in codes { strings[code] = [] }

            // A language that stops short stops for good: its strings are a
            // prefix of the table's rows, because index N means the same id
            // in every language. Text after the stop can't be written
            // anywhere, so it's an error rather than something to drop.
            var ended = Set<String>()
            for (rowIndex, entry) in table.strings.enumerated() {
                if let named = entry.text.codes {
                    for code in named where !codes.contains(code) {
                        throw Error.unexpectedLanguage(tableID: tableID, id: entry.id, code: code)
                    }
                }
                for code in codes {
                    guard let text = entry.text.text(for: code) else {
                        ended.insert(code)
                        continue
                    }
                    guard !ended.contains(code) else {
                        throw Error.languageResumesAfterItsEnd(
                            tableID: tableID, id: entry.id, code: code
                        )
                    }
                    strings[code]?.append(GSString(string: text, format: .gsPBR))
                }
                guard records[entry.id] == nil else {
                    throw Error.duplicateStringID(id: entry.id)
                }
                records[entry.id] = .init(tableID: tableID, index: rowIndex + 1)
            }

            resolved.append(ResolvedTable(
                tableID: tableID,
                languages: table.files.map { file in
                    ResolvedLanguage(code: file.code, paths: file.paths, strings: strings[file.code] ?? [])
                }
            ))
        }

        // The directory is an array indexed by id, so the ids have to be
        // exactly 1…N. A gap isn't representable; a duplicate was caught
        // above.
        let count = records.count
        var ordered = [PBRStringDirectory.Record]()
        ordered.reserveCapacity(count)
        for id in 1...max(count, 1) where count > 0 {
            guard let record = records[id] else {
                throw Error.stringIDsNotContiguous(missing: id, count: count)
            }
            ordered.append(record)
        }

        return Resolution(
            directory: PBRStringDirectory(tableCount: tables.count, records: ordered),
            directoryPath: directory,
            tables: resolved
        )
    }
}
