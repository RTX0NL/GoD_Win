import Structs
import GoDFoundation

/// Native script built-in ("callStandard") dispatch table entry.
///
/// The engine's builtin table lives in the DOL data section (US: 0x802E1CF0,
/// 247 entries) and is installed into the script manager at init. The
/// `callStandard` opcode handler indexes it directly by the script-side
/// function ID and marshals stack arguments according to the type bytes:
/// 0 = end of argument list, 2 = float, any other value = int.
public extension ColosseumStructDefaults {

    static let scriptBuiltinFunctionStruct = StructMap(
        name: "ScriptBuiltinFunction",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // Offset 0x00: Native handler function pointer (0 = unimplemented ID)
            .label(name: "handler"),
            // Offset 0x04: Argument type bytes (0 = end, 2 = float, else int)
            .array(name: "arg_types", count: 8, of: .uint8),
        ]
    )
}
