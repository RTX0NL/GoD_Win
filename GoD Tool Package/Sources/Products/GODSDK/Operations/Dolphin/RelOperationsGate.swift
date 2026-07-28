import GoDFoundation

/// Temporary kill switch for all REL file operations.
///
/// The typed data reassembly pipeline is being reworked on the DOL side
/// first; REL disassembly/assembly (and the common.rel / map.rel wrappers
/// that route through them) are disabled until they migrate to the same
/// import flow. Flip `enabled` back to `true` to restore them.
enum RelOperationsGate {
    static let enabled = false

    struct DisabledError: Error, CustomStringConvertible {
        let operation: String
        let trace: ErrorTrace

        var description: String {
            "REL operations are temporarily disabled (attempted '\(operation)'). "
            + "They will return once the typed data reassembly rework lands.\n\(trace)"
        }
    }
}
