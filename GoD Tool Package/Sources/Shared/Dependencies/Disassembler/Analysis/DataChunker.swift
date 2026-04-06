import GoDFoundation
import Structs

/// The type of a data chunk identified by the chunker
public enum DataChunkKind: Equatable {
    /// A single struct instance with a known type
    case typedStruct(definition: StructDefinition)
    /// A table of consecutive same-typed entries
    case table(definition: StructDefinition, count: Int, countLabel: String?)
    /// Untyped data that contains pointer labels (needs .4byte assembly format)
    case assembly
    /// Untyped data with no labels (raw binary)
    case binary
}

/// A chunk of data within a data section
public struct DataChunk {
    /// Label at the start of this chunk
    public let label: String
    /// What kind of data this chunk contains
    public let kind: DataChunkKind
    /// Byte offset within the section
    public let offset: Int
    /// Size in bytes
    public let size: Int
    /// The raw bytes for this chunk
    public let data: [UInt8]
    /// Labels within this chunk (offset relative to chunk start → label name)
    public let labels: [Int: String]
    /// Pointer values within this chunk (offset relative to chunk start → target address)
    public let pointers: [Int: UInt32]

    public init(
        label: String,
        kind: DataChunkKind,
        offset: Int,
        size: Int,
        data: [UInt8],
        labels: [Int: String] = [:],
        pointers: [Int: UInt32] = [:]
    ) {
        self.label = label
        self.kind = kind
        self.offset = offset
        self.size = size
        self.data = data
        self.labels = labels
        self.pointers = pointers
    }
}

/// Splits data section bytes into typed and untyped chunks
/// based on the type map, label map, and pointer scan results.
public struct DataChunker {

    public init() {}

    /// Split a data section into chunks.
    ///
    /// - Parameters:
    ///   - data: Raw bytes of the section
    ///   - baseAddress: RAM address of the section start
    ///   - labels: Map of byte offset → label name for all known labels in this section
    ///   - pointers: Map of byte offset → target address for confirmed pointer values
    ///   - typeMap: Type information for labels (already resolved to definitions)
    ///   - tables: Table definitions from the type map (already resolved)
    /// - Returns: Ordered list of data chunks
    public func chunk(
        data: [UInt8],
        baseAddress: UInt32,
        labels: [(offset: Int, name: String)],
        pointers: [Int: UInt32],
        resolvedTypes: [String: StructDefinition],
        resolvedTables: [(name: String, definition: StructDefinition, count: Int, countLabel: String?)]
    ) -> [DataChunk] {
        guard !data.isEmpty else { return [] }

        // Sort labels by offset
        let sortedLabels = labels.sorted(by: { $0.offset < $1.offset })

        // Build a set of offsets that are table starts
        var tableStartOffsets = [Int: (name: String, definition: StructDefinition, count: Int, countLabel: String?)]()
        for table in resolvedTables {
            if let labelEntry = sortedLabels.first(where: { $0.name == table.name }) {
                tableStartOffsets[labelEntry.offset] = table
            }
        }

        // Build label name → offset lookup
        var labelNameToOffset = [String: Int]()
        for label in sortedLabels {
            labelNameToOffset[label.name] = label.offset
        }

        var chunks = [DataChunk]()
        var currentOffset = 0

        // Walk through the section creating chunks at label boundaries
        while currentOffset < data.count {
            // Find the current label (if any)
            let currentLabel = sortedLabels.first(where: { $0.offset == currentOffset })

            // Determine the end of this chunk
            let nextLabelOffset: Int
            if let currentLabel {
                // Check if this is a table start
                if let table = tableStartOffsets[currentOffset] {
                    let tableSize = table.definition.length * table.count
                    nextLabelOffset = min(currentOffset + tableSize, data.count)

                    let chunkData = Array(data[currentOffset..<nextLabelOffset])
                    let chunkLabels = labelsInRange(sortedLabels, from: currentOffset, to: nextLabelOffset)
                    let chunkPointers = pointersInRange(pointers, from: currentOffset, to: nextLabelOffset)

                    chunks.append(DataChunk(
                        label: table.name,
                        kind: .table(definition: table.definition, count: table.count, countLabel: table.countLabel),
                        offset: currentOffset,
                        size: nextLabelOffset - currentOffset,
                        data: chunkData,
                        labels: chunkLabels,
                        pointers: chunkPointers
                    ))
                    currentOffset = nextLabelOffset
                    continue
                }

                // Check if this is a typed struct
                if let definition = resolvedTypes[currentLabel.name] {
                    let structSize = definition.length
                    nextLabelOffset = min(currentOffset + structSize, data.count)

                    let chunkData = Array(data[currentOffset..<nextLabelOffset])
                    let chunkLabels = labelsInRange(sortedLabels, from: currentOffset, to: nextLabelOffset)
                    let chunkPointers = pointersInRange(pointers, from: currentOffset, to: nextLabelOffset)

                    chunks.append(DataChunk(
                        label: currentLabel.name,
                        kind: .typedStruct(definition: definition),
                        offset: currentOffset,
                        size: nextLabelOffset - currentOffset,
                        data: chunkData,
                        labels: chunkLabels,
                        pointers: chunkPointers
                    ))
                    currentOffset = nextLabelOffset
                    continue
                }

                // Untyped chunk — find next label boundary
                let nextLabel = sortedLabels.first(where: { $0.offset > currentOffset })
                nextLabelOffset = nextLabel?.offset ?? data.count
            } else {
                // No label at current offset — scan forward to next label
                let nextLabel = sortedLabels.first(where: { $0.offset > currentOffset })
                nextLabelOffset = nextLabel?.offset ?? data.count
            }

            // Create untyped chunk (assembly if it has pointers, binary otherwise)
            let chunkData = Array(data[currentOffset..<nextLabelOffset])
            let chunkLabels = labelsInRange(sortedLabels, from: currentOffset, to: nextLabelOffset)
            let chunkPointers = pointersInRange(pointers, from: currentOffset, to: nextLabelOffset)
            let hasPointers = !chunkPointers.isEmpty

            let label = currentLabel?.name ?? "lbl_\(String(format: "%08X", baseAddress + UInt32(currentOffset)))"

            chunks.append(DataChunk(
                label: label,
                kind: hasPointers ? .assembly : .binary,
                offset: currentOffset,
                size: nextLabelOffset - currentOffset,
                data: chunkData,
                labels: chunkLabels,
                pointers: chunkPointers
            ))
            currentOffset = nextLabelOffset
        }

        return chunks
    }

    // MARK: - Helpers

    private func labelsInRange(
        _ sortedLabels: [(offset: Int, name: String)],
        from start: Int,
        to end: Int
    ) -> [Int: String] {
        var result = [Int: String]()
        for label in sortedLabels where label.offset >= start && label.offset < end {
            result[label.offset - start] = label.name
        }
        return result
    }

    private func pointersInRange(
        _ pointers: [Int: UInt32],
        from start: Int,
        to end: Int
    ) -> [Int: UInt32] {
        var result = [Int: UInt32]()
        for (offset, target) in pointers where offset >= start && offset < end {
            result[offset - start] = target
        }
        return result
    }
}
