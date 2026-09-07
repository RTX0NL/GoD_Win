import GoDFoundation

/// Kill switch for all REL file operations.
///
/// Held `false` while the typed-data flow was reworked on the DOL side first.
/// The REL data-section walk now emits typed tables the same way — CSV only,
/// verified by decoding it straight back, demoting to a raw binary chunk when
/// it can't round-trip — so the operations are enabled again.
///
/// The switch itself is kept rather than deleted: it is the one place that
/// turns the whole REL family off if a regression shows up mid-migration, and
/// the disabled path is still covered by `RelOperationTests`.
///
/// Known limitation, not a reason to re-disable: `RelAssembly` rebuilds from
/// the lossless `<relName>.rel.json` alone, so edits to the per-chunk
/// artifacts a disassembly emits do not yet feed back into the binary. The
/// chunk artifacts are a read-only view until `.s` parsing lands.
enum RelOperationsGate {
    static let enabled = true

    struct DisabledError: Error, CustomStringConvertible {
        let operation: String
        let trace: ErrorTrace

        var description: String {
            "REL operations are temporarily disabled (attempted '\(operation)'). "
            + "They will return once the typed data reassembly rework lands.\n\(trace)"
        }
    }
}
