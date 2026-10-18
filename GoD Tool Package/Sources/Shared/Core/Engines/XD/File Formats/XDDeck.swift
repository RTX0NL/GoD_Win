import GoDFoundation

/// XD trainer deck file (`DeckData_*.bin`, in `deck_archive.fsys`).
///
/// A 0x10-byte `DECK` header — magic, total file size, deck id, a reserved
/// word — then sections back to back until the end of the file. Each
/// section has its own 0x10-byte header: a four-letter tag, the section's
/// size *including* that header, a record count and a reserved word.
///
/// | Tag    | Holds                                   | Record |
/// |--------|-----------------------------------------|--------|
/// | `DTNR` | trainers (`DeckTrainer`)                | 0x38   |
/// | `DPKM` | trainer Pokémon (`DeckTrainerPokemon`)  | 0x20   |
/// | `DTAI` | trainer AI (`DeckTrainerAI`)            | 0x20   |
/// | `DDPK` | shadow Pokémon (`DeckShadowPokemon`)    | 0x18   |
/// | `DSTR` | trainer tag strings; its count is 0     | —      |
///
/// `DeckData_DarkPokemon` holds a single `DDPK` section; the other decks
/// hold `DTNR`, `DPKM`, `DTAI` and `DSTR` in that order. Measured on every
/// deck of the US disc: sections are packed with no padding between them,
/// and the header's size is the file's size.
///
/// This type keeps each section's body as bytes. What the records mean is
/// the engine's struct definitions' business; the deck operations pair the
/// two. Parsing and serializing are exact inverses.
public struct XDDeck: Equatable {

    public static let magic = "DECK"
    public static let headerSize = 0x10

    public struct Section: Equatable {
        public var tag: String
        /// The header's record count, as stored. For a record section it
        /// equals the body's length over the record size; `DSTR` stores 0.
        public var count: UInt32
        public var reserved: UInt32
        public var body: [UInt8]

        public init(tag: String, count: UInt32, reserved: UInt32 = 0, body: [UInt8]) {
            self.tag = tag
            self.count = count
            self.reserved = reserved
            self.body = body
        }
    }

    public var deckID: UInt32
    public var reserved: UInt32
    public var sections: [Section]

    public init(deckID: UInt32, reserved: UInt32 = 0, sections: [Section]) {
        self.deckID = deckID
        self.reserved = reserved
        self.sections = sections
    }

    public init(bytes: [UInt8]) throws {
        guard bytes.count >= Self.headerSize, Self.tag(in: bytes, at: 0) == Self.magic else {
            throw XDDeckError.notADeck
        }
        let declaredSize = Int(Self.word(in: bytes, at: 4))
        guard declaredSize == bytes.count else {
            throw XDDeckError.sizeMismatch(declared: declaredSize, actual: bytes.count)
        }
        deckID = Self.word(in: bytes, at: 8)
        reserved = Self.word(in: bytes, at: 12)

        var sections = [Section]()
        var offset = Self.headerSize
        while offset < bytes.count {
            guard offset + Self.headerSize <= bytes.count,
                  let tag = Self.tag(in: bytes, at: offset) else {
                throw XDDeckError.malformedSection(offset: offset)
            }
            let size = Int(Self.word(in: bytes, at: offset + 4))
            guard size >= Self.headerSize, offset + size <= bytes.count else {
                throw XDDeckError.malformedSection(offset: offset)
            }
            sections.append(Section(
                tag: tag,
                count: Self.word(in: bytes, at: offset + 8),
                reserved: Self.word(in: bytes, at: offset + 12),
                body: Array(bytes[(offset + Self.headerSize) ..< (offset + size)])
            ))
            offset += size
        }
        self.sections = sections
    }

    public var bytes: [UInt8] {
        let total = Self.headerSize + sections.reduce(0) { $0 + Self.headerSize + $1.body.count }
        var out = Array(Self.magic.utf8)
        out += Self.bytes(of: UInt32(total)) + Self.bytes(of: deckID) + Self.bytes(of: reserved)
        for section in sections {
            out += Array(section.tag.utf8)
            out += Self.bytes(of: UInt32(Self.headerSize + section.body.count))
            out += Self.bytes(of: section.count) + Self.bytes(of: section.reserved)
            out += section.body
        }
        return out
    }

    // MARK: - String table (DSTR)

    /// One `DSTR` string and where it starts. A trainer's `stringID` is
    /// that offset.
    public struct TaggedString: Codable, Equatable {
        public var offset: Int
        public var text: String

        public init(offset: Int, text: String) {
            self.offset = offset
            self.text = text
        }
    }

    /// Splits a `DSTR` body into its strings: each is NUL-terminated and
    /// padded with zeros to the next multiple of 4. Returns nil when the
    /// body doesn't follow that layout exactly, so a caller can keep it as
    /// bytes instead of guessing.
    public static func decodeStrings(_ body: [UInt8]) -> [TaggedString]? {
        var strings = [TaggedString]()
        var offset = 0
        while offset < body.count {
            guard let end = body[offset...].firstIndex(of: 0),
                  let text = String(bytes: body[offset ..< end], encoding: .utf8) else {
                return nil
            }
            strings.append(TaggedString(offset: offset, text: text))
            offset = (end + 4) & ~3
        }
        return encodeStrings(strings.map(\.text)) == body ? strings : nil
    }

    /// The inverse of `decodeStrings`, laying the strings out from offset 0.
    public static func encodeStrings(_ texts: [String]) -> [UInt8] {
        var out = [UInt8]()
        for text in texts {
            out += Array(text.utf8) + [0]
            while out.count % 4 != 0 { out.append(0) }
        }
        return out
    }

    /// Where each string lands when `texts` are laid out by `encodeStrings`.
    public static func stringOffsets(_ texts: [String]) -> [Int] {
        var offsets = [Int]()
        var offset = 0
        for text in texts {
            offsets.append(offset)
            offset = (offset + text.utf8.count + 4) & ~3
        }
        return offsets
    }

    // MARK: - Big-endian helpers

    private static func word(in bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset ..< offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func bytes(of word: UInt32) -> [UInt8] {
        [UInt8(word >> 24), UInt8(word >> 16 & 0xFF), UInt8(word >> 8 & 0xFF), UInt8(word & 0xFF)]
    }

    /// The four bytes at `offset` as a tag, when they are printable ASCII.
    private static func tag(in bytes: [UInt8], at offset: Int) -> String? {
        let raw = bytes[offset ..< offset + 4]
        guard raw.allSatisfy({ (0x20 ... 0x7E).contains($0) }) else { return nil }
        return String(decoding: raw, as: UTF8.self)
    }
}

public enum XDDeckError: Error, CustomStringConvertible {
    case notADeck
    case sizeMismatch(declared: Int, actual: Int)
    case malformedSection(offset: Int)

    public var description: String {
        switch self {
        case .notADeck:
            return "not an XD deck file (no DECK header)"
        case let .sizeMismatch(declared, actual):
            return "deck header says \(declared) bytes, but the file is \(actual)"
        case let .malformedSection(offset):
            return "deck section at 0x\(String(offset, radix: 16)) has no valid header or runs past the end of the file"
        }
    }
}
