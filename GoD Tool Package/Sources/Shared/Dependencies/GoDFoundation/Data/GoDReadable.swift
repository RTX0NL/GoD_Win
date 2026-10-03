//
//  GoDReadable.swift
//  
//
//  Created by Stars Momodu on 28/05/2022.
//

import Foundation

/// Something you can read bytes out of, whether or not those bytes are in
/// memory.
///
/// This is what a `FileSystemTree` read hands back, so it has to be usable
/// without knowing which it got. `GoDData` holds a buffer; `GoDStreamedData`
/// reads windows off disk; `WiiDecryptedPartitionView` decrypts them on
/// demand. A caller that only reads should never need to tell them apart —
/// hence `length` as a requirement (a source that can't say how big it is
/// can't be read safely) and the whole-buffer helpers below, which are the
/// one place the difference actually costs something.
public protocol GoDReadable {
    var byteOrder: ByteOrder { get }

    /// Total size in bytes. Cheap on every conformer — a stored count, a file
    /// size read at open, or a computed extent — never a read of the contents.
    var length: Int { get }

    /// The entire contents as one in-memory buffer, or nil if this source
    /// won't produce one.
    ///
    /// Optional because handing over a whole buffer is a real cost for
    /// everything except `GoDData`, which just returns itself. A conformer
    /// that can afford it says so by implementing this; one that can't — or
    /// shouldn't be asked, like a view over an encrypted partition — leaves
    /// the default and callers get nil.
    ///
    /// Reach for it only when the work genuinely needs bytes it can hold:
    /// writing the file somewhere else, feeding a compressor, decoding JSON.
    /// Anything that walks a structure wants `read(atAddress:length:)`, which
    /// is what lets a streamed source stay streamed.
    var allData: GoDData? { get }

    func read(atAddress address: UInt, length: UInt) -> GoDData?
}

public enum GoDReadableError: Error, CustomStringConvertible {
    case readFailed(offset: Int, length: Int, total: Int)

    public var description: String {
        switch self {
        case let .readFailed(offset, length, total):
            return "Failed to read \(length) bytes at \(offset) from a \(total)-byte source"
        }
    }
}

public extension GoDReadable {
    /// Build one buffer holding every byte, whatever the source is.
    ///
    /// The counterpart to `allData`, and deliberately a different question.
    /// `allData` asks whether a source *already has* a buffer, or can make one
    /// cheaply, and returns nil when it can't — so a lazy view over a disc
    /// answers nil and nothing accidentally pulls gigabytes. This one always
    /// produces the buffer, a window at a time, which means the call site is
    /// where a caller states it has somewhere to put the bytes.
    ///
    /// Prefer neither where the work is a copy: `FileHandleAccess.write`
    /// already streams a readable to disk in windows, so writing one out never
    /// needs a buffer at all.
    func materialized(chunkSize: Int = 8 << 20) throws -> GoDData {
        if let whole = allData { return whole }
        let out = GoDData(data: Data(count: length), byteOrder: byteOrder)
        var offset = 0
        while offset < length {
            let count = min(chunkSize, length - offset)
            guard let chunk = read(atAddress: offset, length: count), chunk.length > 0 else {
                throw GoDReadableError.readFailed(offset: offset, length: count, total: length)
            }
            out.write(chunk, atAddress: UInt(offset))
            offset += chunk.length
        }
        return out
    }
}

public extension GoDReadable {
    /// Nothing to hand over unless a conformer says otherwise. Defaulting to
    /// nil rather than to a full read keeps the expensive answer opt-in: a
    /// source has to volunteer its buffer, and a caller that assumed one is
    /// available finds out at the call site instead of somewhere downstream
    /// having quietly read a disc image into memory.
    var allData: GoDData? { nil }

    func read(atAddress address: Int, length: Int) -> GoDData? {
        return read(atAddress: UInt(address), length: UInt(length))
    }

    func readValue<T: ExpressibleByFixedLengthData>(atAddress address: Int) -> T? {
        guard let data = read(atAddress: address, length: T.byteLength) else {
            return nil
        }
        return T(data: data)
    }
    
    func readValues<T: ExpressibleByFixedLengthData>(atAddress address: Int, count: Int) -> [T]? {
        guard let data = read(atAddress: address, length: T.byteLength * count) else {
            return nil
        }
        return Array<T>(data: data)
    }
    
    func readSafely<T: ExpressibleByFixedLengthData & ValueDefaulting>(atAddress address: Int) -> T {
        guard let data = read(atAddress: address, length: T.byteLength) else {
            return T.defaultValue
        }
        return T(data: data) ?? T.defaultValue
    }
    
    func readType<T: ExpressibleByFixedLengthData>(_ type: T.Type, atAddress address: Int) -> T? {
        guard let data = read(atAddress: address, length: T.byteLength) else {
            return nil
        }
        return T(data: data)
    }
    
    func readTypeSafely<T: ExpressibleByFixedLengthData & ValueDefaulting>(_ type: T.Type, atAddress address: Int) -> T {
        guard let data = read(atAddress: address, length: T.byteLength) else {
            return T.defaultValue
        }
        return T(data: data) ?? T.defaultValue
    }
    
    func readTypeAsInt<T: ExpressibleByFixedLengthData & IntegerConvertible>(_ type: T.Type, atAddress address: Int) -> Int {
        guard let data = read(atAddress: address, length: T.byteLength) else {
            return 0
        }
        return T(data: data)?.asInt ?? 0
    }
    
    func readPrimtive<T: PrimitiveDataType>(atAddress address: Int) -> T? {
        guard let data = read(atAddress: address, length: T.byteLength) else {
            return nil
        }
        if data.byteOrder != Environment.byteOrder {
            data.switchByteOrder(boundary: T.byteLength)
        }
        return T(data: data)
    }
    
    func readPrimitives<T: PrimitiveDataType>(atAddress address: Int, count: Int) -> [T]? {
        guard let data = read(atAddress: address, length: T.byteLength * count) else {
            return nil
        }
        if data.byteOrder != Environment.byteOrder {
            data.switchByteOrder(boundary: T.byteLength)
        }
        return Array<T>(data: data)
    }
    
    internal func readChar(atAddress address: Int, format: StringFormats) -> GSCharacter? {
        let subData = read(atAddress: address, length: format.characterLength)
        if let subData = subData,
           UInt16(data: subData) == 0xFFFF {
            switch format {
            case .gsColo, .gsXD:
                guard let charID: UInt8 = readValue(atAddress: address + 2) else { return nil }
                let paramsLength: Int
                switch charID {
                case 0x07, 0x09, 0x38, 0x52, 0x53, 0x5B, 0x5C: paramsLength = 1
                case 0x8: paramsLength = 4
                default: paramsLength = 0
                }
                guard let paramData = read(atAddress: address + 3, length: paramsLength) else { return nil }
                let paramBytes = paramData.rawBytes
                return GSCharacter.special([charID] + paramBytes)
            case .gsPBR:
                guard let charID: UInt16 = readValue(atAddress: address + 2) else { return nil }
                let paramsLength: Int
                switch charID {
                case 0x01, 0x02, 0x03, 0x04, 0x05: paramsLength = 2
                // Vertical offset, a signed 32-bit displacement. Retail
                // always follows it with a line break, but the break is a
                // character of its own and is read as one.
                case 0x8011: paramsLength = 4
                default: paramsLength = 0
                }
                guard let paramData = read(atAddress: address + 4, length: paramsLength) else { return nil }
                var paramBytes = paramData.rawBytes
                if charID == 1, paramBytes.count == 2 {
                    // A furigana marker is followed by its kana reading and
                    // then the kanji it annotates, each counted by its own
                    // byte: kana first, kanji second.
                    let kanaCount = Int(paramBytes[0])
                    let kanjiCount = Int(paramBytes[1])
                    let characterLength = (kanaCount + kanjiCount) * 2
                    if let characterData = read(atAddress: address + 6, length: characterLength) {
                        paramBytes += characterData.rawBytes
                    }
                }
                return GSCharacter.special([UInt8(charID >> 8), UInt8(charID & 0xFF)] + paramBytes)
            default:
                return nil
            }
        } else {
            guard let subData = subData else {
                return nil
            }
            if subData.isNull {
                return .raw("\u{00}")
            }
            return GSCharacter.raw(subData.string(format: format))
        }
    }

    func readString(atAddress address: Int, format: StringFormats, maxCharacters: Int? = nil) -> String? {
        if let maxCharacters = maxCharacters {
            var stringLength = maxCharacters * format.characterLength
            switch format {
            case .gsColo, .gsXD, .gsPBR, .gs, .utf8:
                break
            default:
                stringLength += format.characterLength
            }
            let subData = read(atAddress: address, length: stringLength)
            return subData?.string(format: format)
        } else {
            var nextChar: GSCharacter?
            var result = ""

            var startOffset = 0
            switch format {
            case .unicode_big, .utf16_big:
                if let subData = read(atAddress: address, length: 2) {
                    if subData[0] == 0xFE, subData[1] == 0xFF {
                        startOffset += 2
                    }
                }
            case .unicode_little, .utf16_little:
                if let subData = read(atAddress: address, length: 2) {
                    if subData[0] == 0xFF, subData[1] == 0xFE {
                        startOffset += 2
                    }
                }
            default:
                break
            }
            var offset = startOffset

            repeat {
                nextChar = readChar(atAddress: address + offset, format: format)
                switch (format, nextChar) {
                case (_, .raw("\u{00}")), (.gsPBR, .special([0xFF, 0xFF])):
                    nextChar = nil
                default:
                    result += nextChar?.string(format: format) ?? ""
                }
                switch nextChar {
                case .special:
                    offset += nextChar?.rawData(byteOrder: self.byteOrder).length ?? 0
                case .raw:
                    offset += format.characterLength
                case nil:
                    break
                }
            } while nextChar != nil

            if offset == startOffset { return nil }
            return result
        }
    }
    
    func readStringSafely(atAddress address: Int, format: StringFormats, maxCharacters: Int? = nil) -> String {
        return readString(atAddress: address, format: format, maxCharacters: maxCharacters) ?? ""
    }
    
    func readGSString(atAddress address: Int, format: StringFormats) -> GSString? {
        var nextChar: GSCharacter?
        var result = [GSCharacter]()
        var offset = 0
        repeat {
            switch format {
            case .gsColo: fallthrough
            case .gsXD: fallthrough
            case .gsPBR: fallthrough
            case .gs: nextChar = readChar(atAddress: address + offset, format: format)
            default: nextChar = readChar(atAddress: address + offset, format: .gs)
            }
            
            switch (format, nextChar) {
            case (_, .raw("\u{00}")), (_, .raw("")), (.gsPBR, .special([0xFF, 0xFF])):
                nextChar = nil
            default:
                if let nextChar = nextChar {
                    result.append(nextChar)
                }
                offset += nextChar?.rawData(byteOrder: self.byteOrder).length ?? 0
            }
        } while nextChar != nil
        guard result.count > 0 else { return nil }
        return GSString(characters: result)
    }
    
    func readGSStringSafely(atAddress address: Int, format: StringFormats) -> GSString {
        return readGSString(atAddress: address, format: format) ?? ""
    }
}
