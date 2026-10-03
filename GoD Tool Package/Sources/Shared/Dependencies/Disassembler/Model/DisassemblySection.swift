import GoDFoundation

/// The kind of section in a disassembled binary
public enum SectionKind: String, Codable, Equatable {
    /// Executable code (instructions)
    case text
    /// Initialized static data
    case data
    /// Uninitialized static data (no bytes in binary, just reserved address space)
    case bss
}

/// A section of binary data extracted from a disassembled executable
public struct DisassemblySection {
    /// Section name (e.g. "text0", "data0")
    public let name: String
    public let kind: SectionKind
    /// RAM address where this section is loaded
    public let baseAddress: UInt32
    /// Raw bytes (empty for BSS sections)
    public let data: [UInt8]
    /// Total size in bytes (for BSS, this is the reserved size; for others, data.count)
    public let size: UInt32

    public init(name: String, kind: SectionKind, baseAddress: UInt32, data: [UInt8], size: UInt32) {
        self.name = name
        self.kind = kind
        self.baseAddress = baseAddress
        self.data = data
        self.size = size
    }
}
