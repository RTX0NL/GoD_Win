import GoDFoundation

/// Assembles a Colosseum script model back into .scd binary form.
///
/// This is a structural re-emit: the header, function table, relocation
/// table, globals arena, and every instruction are re-encoded from their
/// decoded representations (no raw byte replay of code). Post-run trailing
/// bytes (tail padding and relocated string data) are carried through from
/// the parsed model.
public enum ColoScriptAssembler {

    /// Re-emit a parsed script preserving its original layout.
    /// `parse → assemble` should reproduce the input byte-for-byte.
    public static func assemble(_ script: ColoScript) -> GoDData {
        var bytes = [UInt8]()

        appendU16(&bytes, script.scriptTypeID)
        appendU16(&bytes, script.headerField2)
        appendU16(&bytes, script.numberOfFunctions)
        appendU16(&bytes, script.relocationCount)
        appendU16(&bytes, script.compilerMetadata)
        appendU16(&bytes, script.relocatedFlag)
        appendU32(&bytes, script.relocTableOffset)
        appendU32(&bytes, script.globalsOffset)
        appendU32(&bytes, script.runtimeNextPointer)

        for offset in script.functionOffsets {
            appendU32(&bytes, offset)
        }

        for relocation in script.relocations {
            appendU32(&bytes, relocation)
        }

        bytes += script.globalsArena.rawBytes

        for run in script.codeRuns {
            for instruction in run.instructions {
                bytes += instruction.opcode.encode()
            }
            bytes += run.trailingData.rawBytes
        }

        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    // MARK: - Helpers

    private static func appendU16(_ bytes: inout [UInt8], _ value: UInt16) {
        bytes.append(UInt8(value >> 8))
        bytes.append(UInt8(value & 0xFF))
    }

    private static func appendU32(_ bytes: inout [UInt8], _ value: UInt32) {
        bytes.append(UInt8((value >> 24) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8(value & 0xFF))
    }
}
