import GoDFoundation

/// Compiles a parsed Colosseum script back to .scd binary, reproducing the
/// Genius Sonority compiler's layout byte-for-byte:
/// header, function table (source order defines emission order; stubs are
/// null entries), string relocation table, zero-filled globals arena,
/// contiguous code runs (each closed by an implicit `returnOp` terminator),
/// string data in the tail, and zero padding to a 32-byte boundary.
public struct ColoScriptCompiler {

    public enum CompileError: Error, CustomStringConvertible {
        case missingFunction(index: Int)
        public var description: String {
            switch self {
            case .missingFunction(let index):
                return "function_\(index) has no declaration (every table slot needs a function or stub)"
            }
        }
    }

    /// Sentinel immediates marking unresolved string-literal references
    /// (patched to real file offsets after layout)
    private static let stringSentinelBase: UInt32 = 0xFF00_0000

    public init() {}

    public func compile(_ parsed: ColoScriptTextParser.ParsedScript) throws -> GoDData {
        let functionCount = (parsed.functions.map(\.index).max() ?? -1) + 1

        var byIndex = [Int: ColoScriptTextParser.ParsedFunction]()
        for function in parsed.functions { byIndex[function.index] = function }
        for index in 0..<functionCount where byIndex[index] == nil {
            throw CompileError.missingFunction(index: index)
        }

        let relocSiteCount = parsed.functions.reduce(0) { $0 + stringSiteCount(in: $1.body) }
        let relocTableOffset = ColoScript.headerSize + 4 * functionCount
        let globalsOffset = relocTableOffset + 4 * relocSiteCount
        let codeStart = globalsOffset + 4 * parsed.gvarTypes.count

        // Lower every non-stub function in source (emission) order.
        // Code size does not depend on string offsets (immediates are fixed
        // width), so one pass with sentinels determines the layout.
        let uncompounder = ColoExprUncompound()
        let lowering = ColoExprLowering()

        var functionOffsets = [UInt32](repeating: 0, count: functionCount)
        var loweredRuns = [(instructions: [ColoScriptInstruction], offset: Int)]()
        var offset = codeStart

        for function in parsed.functions where !function.isStub {
            var body = withStringSentinels(function.body)
            // Re-append the implicit terminating returnOp (before a trailing exit)
            if case .exit = body.last {
                body.insert(.returnVoid, at: body.count - 1)
            } else {
                body.append(.returnVoid)
            }
            let flattened = uncompounder.uncompound(body)
            let instructions = try lowering.lower(flattened, startOffset: offset)
            functionOffsets[function.index] = UInt32(offset)
            loweredRuns.append((instructions, offset))
            offset += instructions.reduce(0) { $0 + $1.length }
        }
        let codeEnd = offset

        // Assign string offsets in the tail and patch sentinel immediates,
        // recording each patched operand's file offset as a relocation site
        // Strings start on the next 8-byte boundary after the code
        var stringOffsets = [Int]()
        var stringCursor = parsed.strings.isEmpty ? codeEnd : (codeEnd + 7) & ~7
        let stringBase = stringCursor
        for text in parsed.strings {
            stringOffsets.append(stringCursor)
            stringCursor += text.utf8.count + 1
        }

        var relocationSites = [UInt32]()
        for runIndex in loweredRuns.indices {
            for (i, instruction) in loweredRuns[runIndex].instructions.enumerated() {
                guard case .pushImmediate(let type, let value) = instruction.opcode,
                      value >= Self.stringSentinelBase,
                      let stringIndex = Optional(Int(value - Self.stringSentinelBase)),
                      stringIndex < stringOffsets.count else { continue }
                relocationSites.append(UInt32(instruction.offset + 2))
                loweredRuns[runIndex].instructions[i] = ColoScriptInstruction(
                    offset: instruction.offset,
                    opcode: .pushImmediate(type: type, value: UInt32(stringOffsets[stringIndex])))
            }
        }

        var bytes = [UInt8]()
        appendU16(&bytes, parsed.scriptTypeID)
        appendU16(&bytes, parsed.headerField2)
        appendU16(&bytes, UInt16(functionCount))
        appendU16(&bytes, UInt16(relocSiteCount))
        appendU16(&bytes, parsed.compilerMetadata)
        appendU16(&bytes, 0)                          // runtime relocated flag
        appendU32(&bytes, UInt32(relocTableOffset))
        appendU32(&bytes, UInt32(globalsOffset))
        appendU32(&bytes, 0)                          // runtime next pointer

        for functionOffset in functionOffsets { appendU32(&bytes, functionOffset) }
        for site in relocationSites { appendU32(&bytes, site) }
        bytes += [UInt8](repeating: 0, count: 4 * parsed.gvarTypes.count)

        for run in loweredRuns {
            for instruction in run.instructions {
                bytes += instruction.opcode.encode()
            }
        }

        if parsed.strings.isEmpty {
            // Zero-pad the file to a 32-byte boundary
            let remainder = bytes.count % 32
            if remainder != 0 {
                bytes += [UInt8](repeating: 0, count: 32 - remainder)
            }
        } else {
            // Align to the string base, then end exactly at the last NUL
            bytes += [UInt8](repeating: 0, count: stringBase - bytes.count)
            for text in parsed.strings {
                bytes += Array(text.utf8) + [0]
            }
        }

        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    // MARK: - Strings

    private func stringSiteCount(in body: [ColoExpr]) -> Int {
        var count = 0
        walkPrintfs(body) { format, _ in
            if format.hasPrefix("stringlit:") { count += 1 }
        }
        return count
    }

    /// Replace `stringlit:<i>` printf formats with sentinel `string@` offsets
    private func withStringSentinels(_ body: [ColoExpr]) -> [ColoExpr] {
        body.map { rewritePrintfs($0) }
    }

    private func rewritePrintfs(_ expr: ColoExpr) -> ColoExpr {
        switch expr {
        case .printf(let format, let args) where format.hasPrefix("stringlit:"):
            let index = Int(format.dropFirst(10)) ?? 0
            let sentinel = Self.stringSentinelBase + UInt32(index)
            return .printf("string@\(sentinel)", args.map { rewritePrintfs($0) })
        case .printf(let format, let args):
            return .printf(format, args.map { rewritePrintfs($0) })
        case .ifStatement(let branches):
            return .ifStatement(branches.map { ($0.0, $0.1.map { rewritePrintfs($0) }) })
        case .whileLoop(let condition, let body):
            return .whileLoop(condition, body.map { rewritePrintfs($0) })
        default:
            return expr
        }
    }

    private func walkPrintfs(_ body: [ColoExpr], _ visit: (String, [ColoExpr]) -> Void) {
        for expr in body {
            switch expr {
            case .printf(let format, let args): visit(format, args)
            case .ifStatement(let branches): branches.forEach { walkPrintfs($0.1, visit) }
            case .whileLoop(_, let loopBody): walkPrintfs(loopBody, visit)
            default: break
            }
        }
    }

    // MARK: - Byte helpers

    private func appendU16(_ bytes: inout [UInt8], _ value: UInt16) {
        bytes.append(UInt8(value >> 8))
        bytes.append(UInt8(value & 0xFF))
    }

    private func appendU32(_ bytes: inout [UInt8], _ value: UInt32) {
        bytes.append(UInt8((value >> 24) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8(value & 0xFF))
    }
}
