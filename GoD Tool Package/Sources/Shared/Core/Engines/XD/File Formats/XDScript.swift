import GoDFoundation

/// XD script file format (.scd)
///
/// Multi-section binary format:
/// TCOD, FTBL (function table), HEAD, CODE, GVAR, STRG, VECT, GIRI, ARRY
public final class XDScript {

    public static let sectionHeaderSize = 0x20

    public struct FunctionEntry {
        public let codeOffset: Int   // word offset into CODE section
        public let nameOffset: Int   // byte offset into STRG section
        public let name: String?
    }

    public struct GlobalVar {
        public let type: Int         // constant type ID
        public let value: UInt32
    }

    /// Character reference (GIRI section)
    public struct CharacterRef {
        public let groupID: Int
        public let resourceID: Int
    }

    public let functions: [FunctionEntry]
    public let code: [UInt32]           // raw CODE words
    public let globalVars: [GlobalVar]
    public let strings: [String]        // STRG entries
    public let vectors: [(Float, Float, Float)]  // VECT entries
    public let characterRefs: [CharacterRef]     // GIRI entries

    /// Decoded instructions grouped by function index
    public let functionInstructions: [[XDScriptInstruction]]

    public let rawData: GoDData

    public init(data: GoDData) throws {
        data.setByteOrder(.big)
        rawData = data.copy

        // TCOD is at 0x0 (hidden section, 0x10 bytes)
        // Then sections follow sequentially, each with a 0x20 header
        var offset = 0

        // TCOD section (0x10 bytes)
        offset = 0x10

        let ftblOffset = offset
        let ftblSize: UInt32 = data.readSafely(atAddress: ftblOffset + 4)
        let ftblCount: UInt32 = data.readSafely(atAddress: ftblOffset + 0x10)
        offset = ftblOffset + Int(ftblSize)

        let headOffset = offset
        let headSize: UInt32 = data.readSafely(atAddress: headOffset + 4)
        offset = headOffset + Int(headSize)

        let codeOffset = offset
        let codeSize: UInt32 = data.readSafely(atAddress: codeOffset + 4)
        let codeDataStart = codeOffset + Self.sectionHeaderSize
        let codeWordCount = (Int(codeSize) - Self.sectionHeaderSize) / 4
        offset = codeOffset + Int(codeSize)

        let gvarOffset = offset
        let gvarSize: UInt32 = data.readSafely(atAddress: gvarOffset + 4)
        let gvarCount: UInt32 = data.readSafely(atAddress: gvarOffset + 0x10)
        offset = gvarOffset + Int(gvarSize)

        let strgOffset = offset
        let strgSize: UInt32 = data.readSafely(atAddress: strgOffset + 4)
        offset = strgOffset + Int(strgSize)

        let vectOffset = offset
        let vectSize: UInt32 = data.readSafely(atAddress: vectOffset + 4)
        let vectCount: UInt32 = data.readSafely(atAddress: vectOffset + 0x10)
        offset = vectOffset + Int(vectSize)

        let giriOffset = offset
        let giriSize: UInt32 = data.readSafely(atAddress: giriOffset + 4)
        let giriCount: UInt32 = data.readSafely(atAddress: giriOffset + 0x10)
        offset = giriOffset + Int(giriSize)

        // ARRY section (variable length, last section)

        var parsedFunctions = [FunctionEntry]()
        let ftblDataStart = ftblOffset + Self.sectionHeaderSize
        for i in 0..<Int(ftblCount) {
            let entryOffset = ftblDataStart + i * 8
            let codeOff: UInt32 = data.readSafely(atAddress: entryOffset)
            let nameOff: UInt32 = data.readSafely(atAddress: entryOffset + 4)

            // Read name from STRG section
            let strgDataStart = strgOffset + Self.sectionHeaderSize
            let nameAddr = strgDataStart + Int(nameOff)
            let name = data.readString(atAddress: nameAddr, format: .utf8, maxCharacters: 100)

            parsedFunctions.append(FunctionEntry(
                codeOffset: Int(codeOff),
                nameOffset: Int(nameOff),
                name: name
            ))
        }
        functions = parsedFunctions

        // Parse CODE section (raw words)
        var codeWords = [UInt32]()
        for i in 0..<codeWordCount {
            let word: UInt32 = data.readSafely(atAddress: codeDataStart + i * 4)
            codeWords.append(word)
        }
        code = codeWords

        var gvars = [GlobalVar]()
        let gvarDataStart = gvarOffset + Self.sectionHeaderSize
        for i in 0..<Int(gvarCount) {
            let entryOffset = gvarDataStart + i * 8
            let type: UInt16 = data.readSafely(atAddress: entryOffset)
            let value: UInt32 = data.readSafely(atAddress: entryOffset + 4)
            gvars.append(GlobalVar(type: Int(type), value: value))
        }
        globalVars = gvars

        // Parse STRG section (null-terminated strings)
        var strs = [String]()
        let strgDataStart = strgOffset + Self.sectionHeaderSize
        let strgDataEnd = strgOffset + Int(strgSize)
        var strOffset = strgDataStart
        while strOffset < strgDataEnd {
            if let str = data.readString(atAddress: strOffset, format: .utf8, maxCharacters: 500) {
                strs.append(str)
                strOffset += str.utf8.count + 1 // +1 for null terminator
            } else {
                break
            }
        }
        strings = strs

        var vects = [(Float, Float, Float)]()
        let vectDataStart = vectOffset + Self.sectionHeaderSize
        for i in 0..<Int(vectCount) {
            let entryOffset = vectDataStart + i * 12
            let x: Float = data.readSafely(atAddress: entryOffset)
            let y: Float = data.readSafely(atAddress: entryOffset + 4)
            let z: Float = data.readSafely(atAddress: entryOffset + 8)
            vects.append((x, y, z))
        }
        vectors = vects

        var giris = [CharacterRef]()
        let giriDataStart = giriOffset + Self.sectionHeaderSize
        for i in 0..<Int(giriCount) {
            let entryOffset = giriDataStart + i * 8
            let gid: UInt32 = data.readSafely(atAddress: entryOffset)
            let rid: UInt32 = data.readSafely(atAddress: entryOffset + 4)
            giris.append(CharacterRef(groupID: Int(gid), resourceID: Int(rid)))
        }
        characterRefs = giris

        let sortedFuncs = parsedFunctions.enumerated().sorted { $0.element.codeOffset < $1.element.codeOffset }
        var funcInstructions = [[XDScriptInstruction]](repeating: [], count: parsedFunctions.count)

        for (sortIdx, entry) in sortedFuncs.enumerated() {
            let funcIndex = entry.offset
            let startWord = entry.element.codeOffset
            let endWord: Int
            if sortIdx + 1 < sortedFuncs.count {
                endWord = sortedFuncs[sortIdx + 1].element.codeOffset
            } else {
                endWord = codeWordCount
            }

            var instructions = [XDScriptInstruction]()
            var wordIdx = startWord

            while wordIdx < endWord {
                let word1 = codeWords[wordIdx]
                let word2 = wordIdx + 1 < codeWordCount ? codeWords[wordIdx + 1] : nil
                let inst = XDScriptInstruction.decode(word1: word1, word2: word2, codeOffset: wordIdx)
                instructions.append(inst)
                wordIdx += inst.wordCount
            }

            funcInstructions[funcIndex] = instructions
        }
        functionInstructions = funcInstructions
    }

    public var functionCount: Int { functions.count }

    public var totalInstructionCount: Int {
        functionInstructions.reduce(0) { $0 + $1.count }
    }
}

public enum XDScriptError: Error, CustomStringConvertible {
    case fileTooSmall(Int)

    public var description: String {
        switch self {
        case .fileTooSmall(let size):
            return "XD script file too small: \(size) bytes"
        }
    }
}
