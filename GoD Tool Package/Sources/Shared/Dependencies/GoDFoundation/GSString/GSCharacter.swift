//
//  GSCharacter.swift
//  
//
//  Created by Stars Momodu on 29/05/2022.
//

import Foundation

enum GSCharacter {
    case raw(String)
    case special([UInt8])
}

extension GSCharacter: DataConvertible {
    func rawData(byteOrder: ByteOrder) -> GoDData {
        switch self {
        case .raw(let s): return GoDData(character: s, format: .gs)
        case .special(let bytes): return GoDData(byteStream: [0xFF, 0xFF] + bytes, byteOrder: byteOrder)
        }
    }
}

extension GSCharacter {
    func string(format: StringFormats) -> String {
        switch (format, self) {
        case (_ , .raw(let s)): return s
        case (.gsColo, .special([0])), (.gsXD, .special([0])), (.gsPBR, .special([0xFF, 0xFE])): return "\n"
        case (.gsColo, .special([2])), (.gsXD, .special([2])): return "{Await Input}"
        case (.gsColo, .special([3])), (.gsXD, .special([3])): return "{Clear}"
        case (.gsColo, .special([4])), (.gsXD, .special([4])): return "{Kanji Start}"
        case (.gsColo, .special([5])), (.gsXD, .special([5])): return "{Furigana Start}"
        case (.gsColo, .special([6])), (.gsXD, .special([6])): return "{Furigana End}"
        case (.gsColo, .special([7, 1])), (.gsXD, .special([7, 1])): return "{Font Bold}"
        case (.gsColo, .special([7, 2])), (.gsXD, .special([7, 2])): return "{Font Super 1}"
        case (.gsColo, .special([7, 3])), (.gsXD, .special([7, 3])): return "{Font Regular}"
        case (.gsColo, .special([7, 4])), (.gsXD, .special([7, 4])): return "{Font Super 2}"
        case (.gsColo, .special(let bytes)) where bytes.count == 5 && bytes[0] == 8:
            fallthrough
        case (.gsXD, .special(let bytes)) where bytes.count == 5 && bytes[0] == 8: return "{Color: #\(bytes[1].hex())\(bytes[2].hex())\(bytes[3].hex())}"
        case (.gsColo, .special(let bytes)) where bytes.count == 2 && bytes[0] == 9:
            fallthrough
        case (.gsXD, .special(let bytes)) where bytes.count == 2 && bytes[0] == 9: return "{Pause: \(bytes[1])}"
        case (.gsColo, .special([0x13])), (.gsXD, .special([0x13])): return "{Battle Player}"
        case (.gsColo, .special([0x14])), (.gsXD, .special([0x14])): return "{Sent Out Pokemon 1}"
        case (.gsColo, .special([0x15])), (.gsXD, .special([0x15])): return "{Sent Out Pokemon 2}"
        case (.gsColo, .special([0x22])), (.gsXD, .special([0x22])): return "{Foe Trainer Class}"
        case (.gsColo, .special([0x23])), (.gsXD, .special([0x23])): return "{Foe Trainer Name}"
        case (.gsColo, .special([0x2B])), (.gsXD, .special([0x2B])): return "{Field Player}"
        case (.gsColo, .special([0x2C])): return "{Rui}"
        case (.gsColo, .special([0x38, 0])), (.gsXD, .special([0x38, 0])): return "{White}"
        case (.gsColo, .special([0x38, 1])), (.gsXD, .special([0x38, 1])): return "{Yellow}"
        case (.gsColo, .special([0x38, 2])), (.gsXD, .special([0x38, 2])): return "{Green}"
        case (.gsColo, .special([0x38, 3])), (.gsXD, .special([0x38, 3])): return "{Blue}"
        case (.gsColo, .special([0x38, 4])), (.gsXD, .special([0x38, 4])): return "{Yellow 2}"
        case (.gsColo, .special([0x38, 5])), (.gsXD, .special([0x38, 5])): return "{Black}"
        // The value in `$<amount>` and `<N> pts` on the PDA menu — the game's
        // own `msgctrlMenuMoney`. It was named "{Var Species Cry}" from the
        // legacy tool; both discs use it only in `pda_menu.msg`, beside a
        // currency sign.
        case (.gsColo, .special([0x50])), (.gsXD, .special([0x50])): return "{Money}"
        case (.gsColo, .special([0x59])), (.gsXD, .special([0x59])): return "{Speaker}"
        case (.gsXD, .special([0x6A])): return "{Set Speaker}"
        case (.gsXD, .special([0x6D])): return "{Await Input 2}"

        // Names taken from the games' own `msgctrlcode` dispatch table and the
        // handler symbols it points at (`msgctrl.o` in XD's map). Codes above
        // 0x5E exist only in XD — Colosseum's table ends there — so they are
        // matched for `.gsXD` alone and show as hex on a Colosseum string.
        case (.gsColo, .special([0x01])), (.gsXD, .special([0x01])): return "{CR}"
        case (.gsColo, .special([0x0D])), (.gsXD, .special([0x0D])): return "{Var String 0}"
        case (.gsColo, .special([0x0E])), (.gsXD, .special([0x0E])): return "{Var String 1}"
        case (.gsColo, .special([0x0F])), (.gsXD, .special([0x0F])): return "{Attacking Pokemon}"
        case (.gsColo, .special([0x10])), (.gsXD, .special([0x10])): return "{Defending Pokemon}"
        case (.gsColo, .special([0x11])), (.gsXD, .special([0x11])): return "{Selected Pokemon}"
        case (.gsColo, .special([0x12])), (.gsXD, .special([0x12])): return "{Target Pokemon}"
        case (.gsColo, .special([0x16])), (.gsXD, .special([0x16])): return "{Foe Pokemon 1}"
        case (.gsColo, .special([0x17])), (.gsXD, .special([0x17])): return "{Foe Pokemon 2}"
        case (.gsColo, .special([0x18])), (.gsXD, .special([0x18])): return "{Multi Foe Pokemon 1}"
        case (.gsColo, .special([0x19])), (.gsXD, .special([0x19])): return "{Multi Foe Pokemon 2}"
        case (.gsColo, .special([0x1A])), (.gsXD, .special([0x1A])): return "{Attacker Ability}"
        case (.gsColo, .special([0x1B])), (.gsXD, .special([0x1B])): return "{Defender Ability}"
        case (.gsColo, .special([0x1C])), (.gsXD, .special([0x1C])): return "{Selected Ability}"
        case (.gsColo, .special([0x1D])), (.gsXD, .special([0x1D])): return "{Target Ability}"
        case (.gsColo, .special([0x1E])), (.gsXD, .special([0x1E])): return "{Acting Pokemon}"
        case (.gsColo, .special([0x1F])), (.gsXD, .special([0x1F])): return "{Attacker Subject}"
        case (.gsColo, .special([0x20])), (.gsXD, .special([0x20])): return "{Attacker Object}"
        case (.gsColo, .special([0x21])), (.gsXD, .special([0x21])): return "{Attacker Possessive}"
        case (.gsColo, .special([0x24])), (.gsXD, .special([0x24])): return "{Trainer Lose Text}"
        case (.gsColo, .special([0x25])), (.gsXD, .special([0x25])): return "{Foe Trainer 1}"
        case (.gsColo, .special([0x26])), (.gsXD, .special([0x26])): return "{Foe Trainer 2}"
        case (.gsColo, .special([0x27])), (.gsXD, .special([0x27])): return "{Acting Trainer}"
        case (.gsColo, .special([0x28])), (.gsXD, .special([0x28])): return "{Active Move}"
        case (.gsColo, .special([0x29])), (.gsXD, .special([0x29])): return "{Active Item}"
        case (.gsColo, .special([0x2D])), (.gsXD, .special([0x2D])): return "{Item}"
        case (.gsColo, .special([0x2E])), (.gsXD, .special([0x2E])): return "{Item 2}"
        case (.gsColo, .special([0x2F])), (.gsXD, .special([0x2F])): return "{Number}"
        case (.gsColo, .special([0x30])), (.gsXD, .special([0x30])): return "{Number 2}"
        case (.gsColo, .special([0x31])), (.gsXD, .special([0x31])): return "{Message}"
        case (.gsColo, .special([0x32])), (.gsXD, .special([0x32])): return "{Active Pokemon}"
        case (.gsColo, .special([0x33])), (.gsXD, .special([0x33])): return "{Active Pokemon 2}"
        case (.gsColo, .special([0x34])), (.gsXD, .special([0x34])): return "{Menu Number}"
        case (.gsColo, .special([0x35])), (.gsXD, .special([0x35])): return "{Menu Number 2}"
        case (.gsColo, .special([0x36])), (.gsXD, .special([0x36])): return "{Menu Pokemon}"
        case (.gsColo, .special([0x37])), (.gsXD, .special([0x37])): return "{Menu Text}"
        case (.gsColo, .special([0x39])), (.gsXD, .special([0x39])): return "{Move}"
        case (.gsColo, .special([0x3D])), (.gsXD, .special([0x3D])): return "{Sound Effect Off}"
        case (.gsColo, .special([0x3E])), (.gsXD, .special([0x3E])): return "{Sound Effect On}"
        case (.gsColo, .special([0x41])), (.gsXD, .special([0x41])): return "{Var String 2}"
        case (.gsColo, .special([0x42])), (.gsXD, .special([0x42])): return "{Defender Subject}"
        case (.gsColo, .special([0x43])), (.gsXD, .special([0x43])): return "{Defender Object}"
        case (.gsColo, .special([0x44])), (.gsXD, .special([0x44])): return "{Defender Possessive}"
        case (.gsColo, .special([0x45])), (.gsXD, .special([0x45])): return "{Menu Number Unsigned}"
        case (.gsColo, .special([0x46])), (.gsXD, .special([0x46])): return "{Menu Number Unsigned 2}"
        case (.gsColo, .special([0x47])), (.gsXD, .special([0x47])): return "{Menu Number Hex}"
        case (.gsColo, .special([0x48])), (.gsXD, .special([0x48])): return "{Menu Number Hex 2}"
        case (.gsColo, .special([0x49])), (.gsXD, .special([0x49])): return "{Menu Number Padded}"
        case (.gsColo, .special([0x4A])), (.gsXD, .special([0x4A])): return "{Menu Number Padded 2}"
        case (.gsColo, .special([0x4B])), (.gsXD, .special([0x4B])): return "{Money Value}"
        case (.gsColo, .special([0x4C])), (.gsXD, .special([0x4C])): return "{Time}"
        case (.gsColo, .special([0x4D])), (.gsXD, .special([0x4D])): return "{Text}"
        case (.gsColo, .special([0x4E])), (.gsXD, .special([0x4E])): return "{Pokemon}"
        case (.gsColo, .special([0x4F])), (.gsXD, .special([0x4F])): return "{Menu Number Full Width}"
        case (.gsColo, .special([0x51])), (.gsXD, .special([0x51])): return "{Menu Text 2}"
        case (.gsColo, .special(let bytes)) where bytes.count == 2 && bytes[0] == 0x52:
            fallthrough
        case (.gsXD, .special(let bytes)) where bytes.count == 2 && bytes[0] == 0x52:
            return "{Text Shadow: \(bytes[1])}"
        case (.gsColo, .special(let bytes)) where bytes.count == 2 && bytes[0] == 0x53:
            fallthrough
        case (.gsXD, .special(let bytes)) where bytes.count == 2 && bytes[0] == 0x53:
            return "{Text Align: \(bytes[1])}"
        case (.gsColo, .special(let bytes)) where bytes.count == 2 && bytes[0] == 0x54:
            fallthrough
        case (.gsXD, .special(let bytes)) where bytes.count == 2 && bytes[0] == 0x54:
            return "{Talk Sound: \(bytes[1])}"
        case (.gsColo, .special([0x55])), (.gsXD, .special([0x55])): return "{Menu Message}"
        case (.gsColo, .special([0x56])), (.gsXD, .special([0x56])): return "{Menu Message 2}"
        case (.gsColo, .special([0x57])), (.gsXD, .special([0x57])): return "{Text 2}"
        case (.gsColo, .special([0x58])), (.gsXD, .special([0x58])): return "{Trainer Class 2}"
        case (.gsColo, .special([0x5A])), (.gsXD, .special([0x5A])): return "{Indent Off}"
        case (.gsColo, .special(let bytes)) where bytes.count == 2 && bytes[0] == 0x5B:
            fallthrough
        case (.gsXD, .special(let bytes)) where bytes.count == 2 && bytes[0] == 0x5B:
            return "{Line Height: \(bytes[1])}"
        case (.gsColo, .special(let bytes)) where bytes.count == 2 && bytes[0] == 0x5C:
            fallthrough
        case (.gsXD, .special(let bytes)) where bytes.count == 2 && bytes[0] == 0x5C:
            return "{Baseline Shift: \(Int8(bitPattern: bytes[1]))}"
        case (.gsColo, .special([0x5D])), (.gsXD, .special([0x5D])): return "{Play Sound}"
        case (.gsColo, .special([0x5E])), (.gsXD, .special([0x5E])): return "{Wait For Sound}"
        case (.gsXD, .special([0x5F])): return "{Menu Number Half}"
        case (.gsXD, .special([0x60])): return "{Menu Number Half 2}"
        case (.gsXD, .special([0x61])): return "{Menu Number Unsigned Half}"
        case (.gsXD, .special([0x62])): return "{Menu Number Unsigned Half 2}"
        case (.gsXD, .special([0x63])): return "{Money Value Half}"
        case (.gsXD, .special([0x64])): return "{Time Half}"
        case (.gsXD, .special([0x65])): return "{Menu Number Hex Half}"
        case (.gsXD, .special([0x66])): return "{Menu Number Hex Half 2}"
        case (.gsXD, .special([0x67])): return "{Menu Number Padded Half}"
        case (.gsXD, .special([0x68])): return "{Menu Number Padded Half 2}"
        case (.gsXD, .special([0x69])): return "{Menu Money Half}"
        case (.gsXD, .special([0x6B])): return "{Number Half}"
        case (.gsXD, .special([0x6C])): return "{Number Half 2}"
        case (.gsXD, .special([0x6E])): return "{Await Check}"
            
        case (.gsPBR, .special(let bytes)) where bytes.count > 4 && bytes[0...1] == [0,1]:
            // Kana reading first, then the kanji it annotates, each counted by
            // its own byte. A byte count that doesn't match the two falls
            // through to the raw form below rather than rendering as nothing.
            let kanaCount = Int(bytes[2])
            let kanjiCount = Int(bytes[3])
            let characterCount = kanaCount + kanjiCount
            if bytes.count == 4 + (characterCount * 2) {
                let kanaBytes = Array(bytes[4 ..< 4 + (kanaCount * 2)])
                let kana = GoDData(byteStream: kanaBytes, byteOrder: .big)
                    .string(format: StringFormats.utf16_big)
                let kanjiBytes = Array(bytes[(4 + kanaCount * 2)...])
                let kanji = GoDData(byteStream: kanjiBytes, byteOrder: .big)
                    .string(format: StringFormats.utf16_big)
                // The colon separates the reading from what it annotates. A
                // run containing a colon of its own would make the token
                // ambiguous, so it falls back to raw bytes rather than
                // round-tripping wrongly — nothing on the JP disc does, and
                // it is the only disc with furigana at all.
                if !kana.contains(":"), !kanji.contains(":") {
                    return "{Furigana:\(kana):\(kanji)}"
                }
            }
            return Self.rawSpecialToken(bytes)
        case (.gsPBR, .special(let bytes)) where bytes.count == 4 && bytes[0...1] == [0,2]:
            let durationBytes = Array(bytes[2 ..< 4])
            let durationData = GoDData(byteStream: durationBytes, byteOrder: .big)
            return "{Pause: \(UInt16(data: durationData) ?? 0)}"
        case (.gsPBR, .special([0xFF, 0xFF])):
            return "{End}"

        // Formatting markers. The font size and letter spacing carry their
        // parameter in the marker's own low byte; alignment, colour and the
        // vertical offset take a following value. Every PBR string starts
        // with a size and a spacing marker, so these four cover the bulk of
        // what a reader would otherwise see as hex.
        case (.gsPBR, .special(let bytes)) where bytes.count == 2 && bytes[0] == 0xF0:
            return "{Size: \(bytes[1])}"
        case (.gsPBR, .special(let bytes)) where bytes.count == 2 && bytes[0] == 0xF1:
            return "{Spacing: \(Int8(bitPattern: bytes[1]))}"
        case (.gsPBR, .special(let bytes)) where bytes.count == 4 && bytes[0...1] == [0x00, 0x03]:
            return "{Align: \(Int(bytes[2]) << 8 | Int(bytes[3]))}"
        case (.gsPBR, .special(let bytes)) where bytes.count == 4 && bytes[0...1] == [0x00, 0x05]:
            return "{Color: \(Int(bytes[2]) << 8 | Int(bytes[3]))}"
        case (.gsPBR, .special(let bytes)) where bytes.count == 6 && bytes[0...1] == [0x80, 0x11]:
            let magnitude = bytes[2...5].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            return "{VerticalOffset: \(Int32(bitPattern: magnitude))}"

        // Fixed abbreviations the game substitutes from its own font.
        case (.gsPBR, .special([0xFF, 0xFC])): return "{No.}"
        case (.gsPBR, .special([0xFF, 0xFB])): return "{Lv.}"
        case (.gsPBR, .special([0xFF, 0xFA])): return "{HP}"
        case (.gsPBR, .special([0xFF, 0xF9])): return "{PP}"
            
        case (_, .special(let bytes)):
            return Self.rawSpecialToken(bytes)
        }
        
        return ""
    }

    /// The integer in a `{Name: value}` token, or nil if the token isn't
    /// that one. Accepts decimal and `0x`-prefixed values, and a leading
    /// minus, because `integerValue` does.
    private static func parameter(of string: String, named name: String) -> Int? {
        let prefix = "{" + name + ": "
        guard string.startsWith(prefix), string.endsWith("}") else { return nil }
        return string.substring(from: prefix.count).substring(from: 0, to: -1).integerValue
    }

    /// A special character with no named form, rendered as its bytes.
    private static func rawSpecialToken(_ bytes: [UInt8]) -> String {
        guard bytes.count > 0 else { return "" }
        var string = ""
        for byte in bytes {
            string += byte.hex() + " "
        }
        if string.last == " " {
            string.removeLast()
        }
        return "{" + string + "}"
    }
}

extension GSCharacter {
    init?(string: String, format: StringFormats) {
        switch format {
        case .gsColo, .gsXD:
            if string == "\n" { self = .special([0x00]); return }
            if string == "{New Line}" { self = .special([0x00]); return }
            if string == "{Await Input}" { self = .special([0x02]); return }
            if string == "{Clear}" { self = .special([0x03]); return }
            if string == "{Kanji Start}" { self = .special([0x04]); return }
            if string == "{Furigana Start}" { self = .special([0x05]); return }
            if string == "{Furigana End}" { self = .special([0x06]); return }
            if string == "{Font Bold}" { self = .special([0x07, 0x01]); return }
            if string == "{Font Super 1}" { self = .special([0x07, 0x02]); return }
            if string == "{Font Regular}" { self = .special([0x07, 0x03]); return }
            if string == "{Font Super 2}" { self = .special([0x07, 0x04]); return }
            if string.startsWith("{Color: #"), string.endsWith("}") {
                var substring = string.substring(from: "{Color: #".count)
                substring = substring.substring(from: 0, to: -1)
                guard substring.count == 6 else { return nil }
                let red = UInt8(substring.substring(from: 0, to: 2).hexValue() ?? 0)
                let green = UInt8(substring.substring(from: 2, to: 4).hexValue() ?? 0)
                let blue = UInt8(substring.substring(from: 4, to: 6).hexValue() ?? 0)
                self = .special([0x08, red, green, blue, 0xFF]); return
            }
            if string.startsWith("{Pause: "), string.endsWith("}") {
                var substring = string.substring(from: "{Pause: ".count)
                substring = substring.substring(from: 0, to: -1)
                guard let duration = substring.integerValue else { return nil }
                self = .special([0x09, UInt8(duration & 0xFF)]); return
            }
            if string == "{Battle Player}" { self = .special([0x13]); return }
            if string == "{Sent Out Pokemon 1}" { self = .special([0x14]); return }
            if string == "{Sent Out Pokemon 2}" { self = .special([0x15]); return }
            if string == "{Foe Trainer Class}" { self = .special([0x22]); return }
            if string == "{Foe Trainer Name}" { self = .special([0x23]); return }
            if string == "{Field Player}" { self = .special([0x2B]); return }
            if string == "{Rui}" { self = .special([0x2C]); return }
            if string == "{White}" { self = .special([0x38, 0x00]); return }
            if string == "{Yellow}" { self = .special([0x38, 0x01]); return }
            if string == "{Green}" { self = .special([0x38, 0x02]); return }
            if string == "{Blue}" { self = .special([0x38, 0x03]); return }
            if string == "{Yellow 2}" { self = .special([0x38, 0x04]); return }
            if string == "{Black}" { self = .special([0x38, 0x05]); return }
            if string == "{Money}" { self = .special([0x50]); return }
            if string == "{Speaker}" { self = .special([0x59]); return }
            if string == "{Set Speaker}" { self = .special([0x6A]); return }
            if string == "{Await Input 2}" { self = .special([0x6D]); return }
            if string == "{CR}" { self = .special([0x01]); return }
            if string == "{Var String 0}" { self = .special([0x0D]); return }
            if string == "{Var String 1}" { self = .special([0x0E]); return }
            if string == "{Attacking Pokemon}" { self = .special([0x0F]); return }
            if string == "{Defending Pokemon}" { self = .special([0x10]); return }
            if string == "{Selected Pokemon}" { self = .special([0x11]); return }
            if string == "{Target Pokemon}" { self = .special([0x12]); return }
            if string == "{Foe Pokemon 1}" { self = .special([0x16]); return }
            if string == "{Foe Pokemon 2}" { self = .special([0x17]); return }
            if string == "{Multi Foe Pokemon 1}" { self = .special([0x18]); return }
            if string == "{Multi Foe Pokemon 2}" { self = .special([0x19]); return }
            if string == "{Attacker Ability}" { self = .special([0x1A]); return }
            if string == "{Defender Ability}" { self = .special([0x1B]); return }
            if string == "{Selected Ability}" { self = .special([0x1C]); return }
            if string == "{Target Ability}" { self = .special([0x1D]); return }
            if string == "{Acting Pokemon}" { self = .special([0x1E]); return }
            if string == "{Attacker Subject}" { self = .special([0x1F]); return }
            if string == "{Attacker Object}" { self = .special([0x20]); return }
            if string == "{Attacker Possessive}" { self = .special([0x21]); return }
            if string == "{Trainer Lose Text}" { self = .special([0x24]); return }
            if string == "{Foe Trainer 1}" { self = .special([0x25]); return }
            if string == "{Foe Trainer 2}" { self = .special([0x26]); return }
            if string == "{Acting Trainer}" { self = .special([0x27]); return }
            if string == "{Active Move}" { self = .special([0x28]); return }
            if string == "{Active Item}" { self = .special([0x29]); return }
            if string == "{Item}" { self = .special([0x2D]); return }
            if string == "{Item 2}" { self = .special([0x2E]); return }
            if string == "{Number}" { self = .special([0x2F]); return }
            if string == "{Number 2}" { self = .special([0x30]); return }
            if string == "{Message}" { self = .special([0x31]); return }
            if string == "{Active Pokemon}" { self = .special([0x32]); return }
            if string == "{Active Pokemon 2}" { self = .special([0x33]); return }
            if string == "{Menu Number}" { self = .special([0x34]); return }
            if string == "{Menu Number 2}" { self = .special([0x35]); return }
            if string == "{Menu Pokemon}" { self = .special([0x36]); return }
            if string == "{Menu Text}" { self = .special([0x37]); return }
            if string == "{Move}" { self = .special([0x39]); return }
            if string == "{Sound Effect Off}" { self = .special([0x3D]); return }
            if string == "{Sound Effect On}" { self = .special([0x3E]); return }
            if string == "{Var String 2}" { self = .special([0x41]); return }
            if string == "{Defender Subject}" { self = .special([0x42]); return }
            if string == "{Defender Object}" { self = .special([0x43]); return }
            if string == "{Defender Possessive}" { self = .special([0x44]); return }
            if string == "{Menu Number Unsigned}" { self = .special([0x45]); return }
            if string == "{Menu Number Unsigned 2}" { self = .special([0x46]); return }
            if string == "{Menu Number Hex}" { self = .special([0x47]); return }
            if string == "{Menu Number Hex 2}" { self = .special([0x48]); return }
            if string == "{Menu Number Padded}" { self = .special([0x49]); return }
            if string == "{Menu Number Padded 2}" { self = .special([0x4A]); return }
            if string == "{Money Value}" { self = .special([0x4B]); return }
            if string == "{Time}" { self = .special([0x4C]); return }
            if string == "{Text}" { self = .special([0x4D]); return }
            if string == "{Pokemon}" { self = .special([0x4E]); return }
            if string == "{Menu Number Full Width}" { self = .special([0x4F]); return }
            if string == "{Menu Text 2}" { self = .special([0x51]); return }
            if let value = Self.parameter(of: string, named: "Text Shadow") {
                self = .special([0x52, UInt8(truncatingIfNeeded: value)]); return
            }
            if let value = Self.parameter(of: string, named: "Text Align") {
                self = .special([0x53, UInt8(truncatingIfNeeded: value)]); return
            }
            if let value = Self.parameter(of: string, named: "Talk Sound") {
                self = .special([0x54, UInt8(truncatingIfNeeded: value)]); return
            }
            if string == "{Menu Message}" { self = .special([0x55]); return }
            if string == "{Menu Message 2}" { self = .special([0x56]); return }
            if string == "{Text 2}" { self = .special([0x57]); return }
            if string == "{Trainer Class 2}" { self = .special([0x58]); return }
            if string == "{Indent Off}" { self = .special([0x5A]); return }
            if let value = Self.parameter(of: string, named: "Line Height") {
                self = .special([0x5B, UInt8(truncatingIfNeeded: value)]); return
            }
            if let value = Self.parameter(of: string, named: "Baseline Shift") {
                self = .special([0x5C, UInt8(truncatingIfNeeded: value)]); return
            }
            if string == "{Play Sound}" { self = .special([0x5D]); return }
            if string == "{Wait For Sound}" { self = .special([0x5E]); return }
            if string == "{Menu Number Half}" { self = .special([0x5F]); return }
            if string == "{Menu Number Half 2}" { self = .special([0x60]); return }
            if string == "{Menu Number Unsigned Half}" { self = .special([0x61]); return }
            if string == "{Menu Number Unsigned Half 2}" { self = .special([0x62]); return }
            if string == "{Money Value Half}" { self = .special([0x63]); return }
            if string == "{Time Half}" { self = .special([0x64]); return }
            if string == "{Menu Number Hex Half}" { self = .special([0x65]); return }
            if string == "{Menu Number Hex Half 2}" { self = .special([0x66]); return }
            if string == "{Menu Number Padded Half}" { self = .special([0x67]); return }
            if string == "{Menu Number Padded Half 2}" { self = .special([0x68]); return }
            if string == "{Menu Money Half}" { self = .special([0x69]); return }
            if string == "{Number Half}" { self = .special([0x6B]); return }
            if string == "{Number Half 2}" { self = .special([0x6C]); return }
            if string == "{Await Check}" { self = .special([0x6E]); return }
            
        case .gsPBR:
            if string == "\n" { self = .special([0xFF, 0xFE]); return }
            if string == "{New Line}" { self = .special([0xFF, 0xFE]); return }
            if string == "{End}" { self = .special([0xFF, 0xFF]); return }
            
            if string.startsWith("{Furigana:"), string.endsWith("}") {
                // `{Furigana:<kana>:<kanji>}` — the reading first, then the
                // kanji it annotates, which is the order the marker's two
                // count bytes and its characters are in. Empty runs are kept
                // rather than dropped, so the split can't lose one.
                let body = String(string.dropFirst("{Furigana:".count).dropLast())
                let parts = body.split(separator: ":", omittingEmptySubsequences: false)
                if parts.count == 2 {
                    let kana = Array(String(parts[0]).utf16)
                    let kanji = Array(String(parts[1]).utf16)
                    if kana.count <= 0xFF, kanji.count <= 0xFF {
                        let data = GoDData(byteOrder: .big)
                        data.append(UInt16(1))
                        // The counts are in UTF-16 units, which is what the
                        // characters are written as.
                        data.append(UInt8(kana.count))
                        data.append(UInt8(kanji.count))
                        // Appended as bare code units: `GoDData(string:format:)`
                        // prefixes a byte-order mark, and one in front of every
                        // character is not what the marker's counts describe.
                        for unit in kana + kanji {
                            data.append(unit)
                        }
                        guard let bytes = [UInt8](data: data) else {
                            return nil
                        }
                        self = .special(bytes); return
                    }
                }
            }
            if string.startsWith("{Pause: "), string.endsWith("}") {
                var substring = string.substring(from: "{Pause: ".count)
                substring = substring.substring(from: 0, to: -1)
                if let duration = substring.integerValue {
                    let data = GoDData(byteOrder: .big)
                    data.append(UInt16(2))
                    data.append(UInt16(duration & 0xFFFF))
                    guard let bytes = [UInt8](data: data) else {
                        return nil
                    }
                    self = .special(bytes); return
                }
            }
            if let size = Self.parameter(of: string, named: "Size") {
                self = .special([0xF0, UInt8(size & 0xFF)]); return
            }
            if let spacing = Self.parameter(of: string, named: "Spacing") {
                self = .special([0xF1, UInt8(bitPattern: Int8(truncatingIfNeeded: spacing))]); return
            }
            if let alignment = Self.parameter(of: string, named: "Align") {
                self = .special([0x00, 0x03, UInt8((alignment >> 8) & 0xFF), UInt8(alignment & 0xFF)]); return
            }
            if let color = Self.parameter(of: string, named: "Color") {
                self = .special([0x00, 0x05, UInt8((color >> 8) & 0xFF), UInt8(color & 0xFF)]); return
            }
            if let offset = Self.parameter(of: string, named: "VerticalOffset") {
                let magnitude = UInt32(bitPattern: Int32(truncatingIfNeeded: offset))
                self = .special([0x80, 0x11,
                                 UInt8((magnitude >> 24) & 0xFF), UInt8((magnitude >> 16) & 0xFF),
                                 UInt8((magnitude >> 8) & 0xFF), UInt8(magnitude & 0xFF)]); return
            }
            if string == "{No.}" { self = .special([0xFF, 0xFC]); return }
            if string == "{Lv.}" { self = .special([0xFF, 0xFB]); return }
            if string == "{HP}" { self = .special([0xFF, 0xFA]); return }
            if string == "{PP}" { self = .special([0xFF, 0xF9]); return }
        default:
            if string == "{New Line}" { self = .raw("\n"); return }
        }
        
        if string.startsWith("{"), string.endsWith("}") {
            let substring = string.substring(from: 1, to: -1)
            var bytes = [UInt8]()
            let byteStrings = substring.split(separator: " ")
            for byteString in byteStrings {
                if byteString.count == 2,
                   let value = String(byteString).hexValue() {
                    bytes.append(UInt8(value & 0xFF))
                }
            }
            self = .special(bytes); return
        }
        if string.count == 1 {
            self = .raw(string); return
        }
        return nil
    }
}

extension GSCharacter: Equatable {}
