import GoDFoundation

/// Colosseum script file format (.scd)
///
/// Binary layout:
/// - Header (24 bytes): script type ID, function count, unknown, code pointers
/// - Function table: array of 4-byte offsets (one per function → bytecode start)
/// - Bytecode: variable-length instructions
///
/// Calling convention note (relevant to a future recompiler): the Genius
/// Sonority script compiler appends an implicit terminating `returnOp` to
/// **every** function. A value-returning path emits `local0 = value; returnOp`
/// (which decompiles to `return <value>`) and is then followed by this trailing
/// terminator `returnOp` — so many functions physically end in two returns
/// (e.g. `return 1; return`). The decompiler cosmetically hides the redundant
/// (unreachable) trailing return, but a recompiler MUST re-emit a terminating
/// `returnOp` for every function to reproduce valid bytecode.
public final class ColoScript {

    public static let headerSize = 24

    public let scriptTypeID: UInt16
    public let numberOfFunctions: UInt16
    public let unknown: UInt16
    public let codeStartPointer1: UInt32
    public let codeStartPointer2: UInt32

    /// Function table: function index → bytecode offset
    public let functionOffsets: [UInt32]

    /// Decoded instructions grouped by function index
    public let functions: [[ColoScriptInstruction]]

    /// Raw binary data (for round-trip)
    public let rawData: GoDData

    public init(data: GoDData) throws {
        data.setByteOrder(.big)
        rawData = data.copy

        guard data.length >= Self.headerSize else {
            throw ColoScriptError.fileTooSmall(data.length)
        }

        scriptTypeID = data.readSafely(atAddress: 0x00)
        numberOfFunctions = data.readSafely(atAddress: 0x04)
        unknown = data.readSafely(atAddress: 0x08)
        codeStartPointer1 = data.readSafely(atAddress: 0x0C)
        codeStartPointer2 = data.readSafely(atAddress: 0x10)

        // Parse function table
        let funcCount = Int(numberOfFunctions)
        var offsets = [UInt32]()
        let ftblStart = Self.headerSize
        for i in 0..<funcCount {
            let off: UInt32 = data.readSafely(atAddress: ftblStart + i * 4)
            offsets.append(off)
        }
        functionOffsets = offsets

        // Sort function offsets to determine code ranges
        let sortedEntries = offsets.enumerated()
            .sorted(by: { $0.element < $1.element })

        // Decode instructions for each function
        var parsedFunctions = [[ColoScriptInstruction]](repeating: [], count: funcCount)

        for (sortIdx, entry) in sortedEntries.enumerated() {
            let funcIndex = entry.offset
            let startOffset = Int(entry.element)
            let endOffset: Int
            if sortIdx + 1 < sortedEntries.count {
                endOffset = Int(sortedEntries[sortIdx + 1].element)
            } else {
                endOffset = data.length
            }

            var instructions = [ColoScriptInstruction]()
            var pos = startOffset

            while pos < endOffset {
                guard let (opcode, consumed) = ColoScriptOpcode.decode(from: data, at: pos) else {
                    break
                }
                instructions.append(ColoScriptInstruction(offset: pos, opcode: opcode))
                pos += consumed

                // Stop at exit opcode
                if case .exit = opcode { break }
            }

            parsedFunctions[funcIndex] = instructions
        }

        functions = parsedFunctions
    }

    /// Total number of decoded instructions across all functions
    public var totalInstructionCount: Int {
        functions.reduce(0) { $0 + $1.count }
    }
}

public enum ColoScriptError: Error, CustomStringConvertible {
    case fileTooSmall(Int)

    public var description: String {
        switch self {
        case .fileTooSmall(let size):
            return "Colosseum script file too small: \(size) bytes (minimum \(ColoScript.headerSize))"
        }
    }
}
