//
//  CardComments.swift
//
//  The two 32-byte strings a GameCube save shows in the memory-card
//  manager: a title and a subtitle, at the directory entry's
//  `commentsAddress`.
//
//  The pair is addressed independently of the image block and need not
//  sit next to it. Pokémon XD puts it at 0 and its images at 0x40;
//  Luigi's Mansion puts its images at 0 and the comments after them.
//
//  See `Documentation/File Formats/Shared/GCI - GameCube Memory Card Save.md`.
//

import Foundation
import GoDFoundation

public struct CardComments: Equatable {

    public static let fieldLength = 32
    public static let byteCount = fieldLength * 2

    /// `commentsAddress` when the save carries no comments.
    public static let noCommentsAddress: UInt32 = 0xFFFFFFFF

    /// Which character set the strings are in.
    ///
    /// The memory card header records this at `+0x24`, but a `.gci` has
    /// no card header, so a standalone save has to infer it. The
    /// gamecode's region character is the available proxy.
    public enum TextEncoding: String, Codable, CaseIterable {
        case ansi
        case shiftJIS

        var stringEncoding: String.Encoding {
            switch self {
            case .ansi: return .windowsCP1252
            case .shiftJIS: return .shiftJIS
            }
        }
    }

    public var title: String
    public var subtitle: String
    public var encoding: TextEncoding

    public init(title: String, subtitle: String, encoding: TextEncoding) {
        self.title = title
        self.subtitle = subtitle
        self.encoding = encoding
    }

    /// Japanese releases write Shift-JIS; everything else writes CP1252.
    public static func encoding(forGamecode gamecode: String) -> TextEncoding {
        let region = Array(gamecode).count >= 4 ? Array(gamecode)[3] : Character(" ")
        return region == "J" ? .shiftJIS : .ansi
    }

    /// Decode the pair out of a save body. Returns `nil` when the entry
    /// declares no comments or points outside the body.
    public static func decode(
        body: GoDData,
        header: GCIFile.Header,
        encoding: TextEncoding? = nil
    ) -> CardComments? {
        guard header.commentsAddr != noCommentsAddress else { return nil }
        let offset = Int(header.commentsAddr)
        guard offset >= 0, offset + byteCount <= body.length else { return nil }
        let chosen = encoding ?? Self.encoding(forGamecode: header.gamecode)
        let bytes = body.rawBytes
        return CardComments(
            title: decodeField(Array(bytes[offset..<(offset + fieldLength)]), chosen),
            subtitle: decodeField(
                Array(bytes[(offset + fieldLength)..<(offset + byteCount)]), chosen
            ),
            encoding: chosen
        )
    }

    /// Re-encode to the 64 bytes the body holds. Each field is truncated
    /// to 32 bytes and NUL-padded, which is what the card format stores.
    public func encoded() -> [UInt8] {
        encodeField(title) + encodeField(subtitle)
    }

    /// True when re-encoding reproduces the bytes at `header.commentsAddr`.
    /// False means the text is a lossy view — an undecodable sequence, or
    /// bytes left after the terminator — and the raw bytes have to be
    /// carried instead.
    public func verifies(against body: GoDData, header: GCIFile.Header) -> Bool {
        guard header.commentsAddr != Self.noCommentsAddress else { return false }
        let offset = Int(header.commentsAddr)
        guard offset >= 0, offset + Self.byteCount <= body.length else { return false }
        return encoded() == Array(body.rawBytes[offset..<(offset + Self.byteCount)])
    }

    private static func decodeField(_ bytes: [UInt8], _ encoding: TextEncoding) -> String {
        let terminated = Array(bytes.prefix(while: { $0 != 0 }))
        let data = Data(terminated)
        if let text = String(data: data, encoding: encoding.stringEncoding) {
            return text
        }
        // A field that won't decode still has to produce something; the
        // caller's verify catches it and keeps the raw bytes.
        return String(decoding: terminated, as: UTF8.self)
    }

    private func encodeField(_ text: String) -> [UInt8] {
        var bytes = [UInt8]()
        if let data = text.data(using: encoding.stringEncoding) {
            bytes = [UInt8](data)
        } else if let data = text.data(using: .utf8) {
            bytes = [UInt8](data)
        }
        if bytes.count > Self.fieldLength {
            bytes = Array(bytes.prefix(Self.fieldLength))
        }
        return bytes + [UInt8](repeating: 0, count: Self.fieldLength - bytes.count)
    }
}
