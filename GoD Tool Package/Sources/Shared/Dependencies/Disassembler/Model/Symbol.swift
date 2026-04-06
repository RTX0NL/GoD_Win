/// Format-agnostic symbol information.
/// ISA-specific modules (e.g. Dolphin) parse their native symbol map formats
/// into these generic Symbol values for use by the disassembler.
public struct Symbol: Equatable {
    /// The symbol name (e.g. "__start", "gBattleData")
    public let name: String
    /// The RAM address of the symbol
    public let address: UInt32
    /// The size of the symbol in bytes (0 if unknown)
    public let size: UInt32
    /// The source file or object file this symbol came from (e.g. "os.a __start.o")
    public let sourceFile: String?

    public init(name: String, address: UInt32, size: UInt32 = 0, sourceFile: String? = nil) {
        self.name = name
        self.address = address
        self.size = size
        self.sourceFile = sourceFile
    }
}
