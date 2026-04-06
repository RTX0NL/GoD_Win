/// Format-agnostic relocation information.
/// Produced by ISA-specific relocation analyzers (e.g. PPC lis/consumer pair detection)
/// and consumed by the generic disassembler for data pointer scanning and label generation.
public struct RelocationResult: Equatable {
    /// The full address being referenced by the relocation
    public let targetAddress: UInt32
    /// The label name at that address (either from a symbol map or auto-generated like "lbl_XXXXXXXX")
    public let labelName: String

    public init(targetAddress: UInt32, labelName: String) {
        self.targetAddress = targetAddress
        self.labelName = labelName
    }
}
