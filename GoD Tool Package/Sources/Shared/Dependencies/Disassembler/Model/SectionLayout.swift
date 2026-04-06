import GoDFoundation

/// Represents the layout of all sections in a disassembled executable.
/// Corresponds to the sections.txt file format.
public struct SectionLayout: Equatable {
    public var entryPoint: UInt32
    public var bssAddress: UInt32
    public var bssSize: UInt32
    public var textSections: [SectionInfo]
    public var dataSections: [SectionInfo]

    public init(
        entryPoint: UInt32 = 0,
        bssAddress: UInt32 = 0,
        bssSize: UInt32 = 0,
        textSections: [SectionInfo] = [],
        dataSections: [SectionInfo] = []
    ) {
        self.entryPoint = entryPoint
        self.bssAddress = bssAddress
        self.bssSize = bssSize
        self.textSections = textSections
        self.dataSections = dataSections
    }

    public struct SectionInfo: Equatable {
        public let name: String
        public let address: UInt32
        public let size: UInt32?

        public init(name: String, address: UInt32, size: UInt32? = nil) {
            self.name = name
            self.address = address
            self.size = size
        }
    }

    /// All section address ranges (text + data + BSS), used for pointer scanning
    public var allSectionRanges: [(start: UInt32, end: UInt32)] {
        var ranges = [(start: UInt32, end: UInt32)]()
        for section in textSections {
            if let size = section.size, size > 0 {
                ranges.append((start: section.address, end: section.address + size))
            }
        }
        for section in dataSections {
            if let size = section.size, size > 0 {
                ranges.append((start: section.address, end: section.address + size))
            }
        }
        if bssSize > 0 {
            ranges.append((start: bssAddress, end: bssAddress + bssSize))
        }
        return ranges
    }
}
