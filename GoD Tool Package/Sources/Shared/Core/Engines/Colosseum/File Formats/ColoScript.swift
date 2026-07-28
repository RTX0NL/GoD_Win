import GoDFoundation

/// Colosseum script file format (.scd)
///
/// Binary layout (big-endian), confirmed against the US engine disassembly
/// (loader `zz_800f76e4_`, task spawn `zz_800f6d18_`, interpreter `zz_800f6bc4_`):
///
/// | Offset | Size | Field |
/// |--------|------|-------|
/// | 0x00   | 2    | Script kind ID (0x0100) — matched against the high half of runtime handles |
/// | 0x02   | 2    | 0x0101 in all US scripts (meaning unknown) |
/// | 0x04   | 2    | Function count |
/// | 0x06   | 2    | Relocation count |
/// | 0x08   | 2    | Compiler metadata — never read by the engine (correlates with function count) |
/// | 0x0A   | 2    | Runtime "already relocated" flag byte — 0 on disk |
/// | 0x0C   | 4    | Relocation table offset (= 0x18 + functionCount × 4) |
/// | 0x10   | 4    | Globals arena offset (= reloc table end = 0x0C value + relocCount × 4) |
/// | 0x14   | 4    | Runtime linked-list next pointer — 0 on disk |
/// | 0x18   | 4×N  | Function table: function index → bytecode offset |
///
/// After the function table: the relocation table (u32 file offsets of fixup
/// sites — each site holds a u32 file offset, typically a `pushImmediate`
/// string-pointer operand, converted to an absolute pointer at load time),
/// then the zero-filled global-variable arena (4 bytes per script global,
/// shared by every task running the script), then bytecode.
///
/// The function table is *not* sorted by offset (code emission order differs
/// from function index order), entries may be 0 (null function), and two
/// entries may share one offset. Code runs are contiguous; the file is
/// zero-padded to a 32-byte boundary after the last run (string data
/// referenced by relocations may sit in that tail region).
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

    /// One contiguous run of bytecode starting at a function-table offset.
    /// `trailingData` holds the bytes between the last decoded instruction and
    /// the start of the next run (zero padding after `exit`, or relocated
    /// string data at the file tail).
    public struct CodeRun: Equatable {
        public let start: Int
        public let instructions: [ColoScriptInstruction]
        public let trailingData: GoDData

        public init(start: Int, instructions: [ColoScriptInstruction], trailingData: GoDData) {
            self.start = start
            self.instructions = instructions
            self.trailingData = trailingData
        }

        /// Byte length of the run including trailing data
        public var length: Int {
            instructions.reduce(0) { $0 + $1.length } + trailingData.length
        }

        public static func == (lhs: CodeRun, rhs: CodeRun) -> Bool {
            lhs.start == rhs.start
                && lhs.instructions == rhs.instructions
                && lhs.trailingData.rawBytes == rhs.trailingData.rawBytes
        }
    }

    // MARK: Header

    public let scriptTypeID: UInt16       // 0x00
    public let headerField2: UInt16       // 0x02 — 0x0101 in all US scripts
    public let numberOfFunctions: UInt16  // 0x04
    public let relocationCount: UInt16    // 0x06
    public let compilerMetadata: UInt16   // 0x08 — never read by the engine; preserved verbatim
    public let relocatedFlag: UInt16      // 0x0A — runtime flag, 0 on disk
    public let relocTableOffset: UInt32   // 0x0C
    public let globalsOffset: UInt32      // 0x10 — globals arena start (reloc table end)
    public let runtimeNextPointer: UInt32 // 0x14 — runtime field, 0 on disk

    /// Function table: function index → bytecode offset (0 = null function)
    public let functionOffsets: [UInt32]

    /// Relocation table: file offsets of u32 fixup sites (usually
    /// `pushImmediate` operands holding string offsets)
    public let relocations: [UInt32]

    /// Zero-filled global-variable arena between the relocation table and the
    /// first code run — 4 bytes per script global
    public let globalsArena: GoDData

    /// Number of 4-byte script-global slots in the arena
    public var globalVariableCount: Int { globalsArena.length / 4 }

    /// Code runs in ascending file order (one per unique non-zero offset)
    public let codeRuns: [CodeRun]

    /// Decoded instructions grouped by function index. Null functions
    /// (offset 0) are empty. Functions sharing an offset share instructions.
    public let functions: [[ColoScriptInstruction]]

    /// Raw binary data (for round-trip comparison and string lookup)
    public let rawData: GoDData

    public init(data: GoDData) throws {
        data.setByteOrder(.big)
        rawData = data.copy

        guard data.length >= Self.headerSize else {
            throw ColoScriptError.fileTooSmall(data.length)
        }

        scriptTypeID = data.readSafely(atAddress: 0x00)
        headerField2 = data.readSafely(atAddress: 0x02)
        numberOfFunctions = data.readSafely(atAddress: 0x04)
        relocationCount = data.readSafely(atAddress: 0x06)
        compilerMetadata = data.readSafely(atAddress: 0x08)
        relocatedFlag = data.readSafely(atAddress: 0x0A)
        relocTableOffset = data.readSafely(atAddress: 0x0C)
        globalsOffset = data.readSafely(atAddress: 0x10)
        runtimeNextPointer = data.readSafely(atAddress: 0x14)

        // Parse function table
        let funcCount = Int(numberOfFunctions)
        var offsets = [UInt32]()
        let ftblStart = Self.headerSize
        for i in 0..<funcCount {
            let off: UInt32 = data.readSafely(atAddress: ftblStart + i * 4)
            offsets.append(off)
        }
        functionOffsets = offsets

        // Relocation table sits between the function table and the globals arena
        var relocs = [UInt32]()
        for i in 0..<Int(relocationCount) {
            relocs.append(data.readSafely(atAddress: Int(relocTableOffset) + i * 4))
        }
        relocations = relocs

        // Unique non-zero offsets in ascending order define the code runs.
        // Offset 0 marks a null function; duplicates share one run.
        let runStarts = Set(offsets.filter { $0 != 0 }).sorted()

        var runs = [CodeRun]()
        var runByStart = [Int: Int]()  // start offset → index into runs

        for (sortIdx, start) in runStarts.enumerated() {
            let startOffset = Int(start)
            let endOffset = sortIdx + 1 < runStarts.count
                ? Int(runStarts[sortIdx + 1])
                : data.length

            var instructions = [ColoScriptInstruction]()
            var pos = startOffset

            decoding: while pos < endOffset {
                guard let (opcode, consumed) = ColoScriptOpcode.decode(from: data, at: pos) else {
                    break
                }
                instructions.append(ColoScriptInstruction(offset: pos, opcode: opcode))
                pos += consumed

                // Stop at exit opcode; anything up to the next run is padding
                if case .exit = opcode { break decoding }
            }

            let trailing = data.read(atAddress: UInt(pos), length: UInt(max(0, endOffset - pos)))
                ?? GoDData(length: 0, byteOrder: ByteOrder.big)

            runByStart[startOffset] = runs.count
            runs.append(CodeRun(start: startOffset, instructions: instructions, trailingData: trailing))
        }
        codeRuns = runs

        // Globals arena: between the relocation table end and the first run
        let firstRunStart = runStarts.first.map(Int.init) ?? data.length
        globalsArena = data.read(atAddress: UInt(globalsOffset), length: UInt(max(0, firstRunStart - Int(globalsOffset))))
            ?? GoDData(length: 0, byteOrder: ByteOrder.big)

        // Map runs back to function indexes
        functions = offsets.map { off in
            guard off != 0, let runIndex = runByStart[Int(off)] else { return [] }
            return runs[runIndex].instructions
        }
    }

    /// Total number of decoded instructions across all code runs
    public var totalInstructionCount: Int {
        codeRuns.reduce(0) { $0 + $1.instructions.count }
    }

    /// Read the NUL-terminated ASCII string at a file offset (used to resolve
    /// relocated string-pointer immediates, e.g. printf format strings)
    public func cString(at offset: Int) -> String? {
        guard offset >= 0, offset < rawData.length else { return nil }
        var bytes = [UInt8]()
        var pos = offset
        let raw = rawData.rawBytes
        while pos < raw.count, raw[pos] != 0 {
            bytes.append(raw[pos])
            pos += 1
        }
        return String(bytes: bytes, encoding: .ascii)
    }

    /// Whether the u32 operand at `fileOffset` is covered by a relocation
    /// entry (i.e. it is a pointer, not a plain integer)
    public func isRelocatedOperand(at fileOffset: Int) -> Bool {
        relocations.contains(UInt32(fileOffset))
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
