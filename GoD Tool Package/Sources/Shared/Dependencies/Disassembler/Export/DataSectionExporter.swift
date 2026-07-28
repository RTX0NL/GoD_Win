import GoDFoundation
import Structs

/// Exports a chunked data section to files and generates a manifest.
/// Orchestrates TypedDataExporter and AssemblyTextExporter for different chunk types.
public struct DataSectionExporter {

    private let typedExporter = TypedDataExporter()
    private let assemblyExporter = AssemblyTextExporter()

    public init() {}

    /// Export a list of data chunks to an in-memory filesystem, producing a manifest.
    ///
    /// - Parameters:
    ///   - chunks: Ordered data chunks from the DataChunker
    ///   - sectionName: Section name (e.g. "data0")
    ///   - addressToLabel: Reverse lookup for resolving addresses to label names
    ///   - byteOrder: Byte order for the data
    ///   - outputFolder: Where to write the output files
    ///   - fileSystem: Filesystem to write to
    /// - Returns: The generated manifest
    public func export(
        chunks: [DataChunk],
        sectionName: String,
        addressToLabel: [UInt32: String],
        byteOrder: ByteOrder,
        outputFolder: Folder,
        fileSystem: FileSystemTree
    ) -> DataSectionManifest {
        var manifest = DataSectionManifest(section: sectionName)

        for chunk in chunks {
            switch chunk.kind {
            case .typedStruct(let definition):
                let fileName = "\(chunk.label).json"
                let data = GoDData(byteStream: chunk.data, byteOrder: byteOrder)
                let structData = typedExporter.exportStruct(
                    data: data,
                    definition: definition,
                    addressToLabel: addressToLabel
                )

                if let json: GoDData = try? JSONEncoder.pokemon.encode(structData) {
                    try? fileSystem.writeFile(json, at: outputFolder.file(fileName), overwrite: true)
                }

                manifest.chunks.append(.init(
                    label: chunk.label,
                    type: .struct,
                    file: fileName,
                    structType: definition.name
                ))

            case .table(let definition, let count, let countLabel):
                let fileName = "\(chunk.label).json"
                let data = GoDData(byteStream: chunk.data, byteOrder: byteOrder)

                let entryLabels = chunk.labels.sorted(by: { $0.key < $1.key }).map {
                    (offset: $0.key, name: $0.value)
                }

                let entries = typedExporter.exportTable(
                    data: data,
                    definition: definition,
                    count: count,
                    entryLabels: entryLabels,
                    addressToLabel: addressToLabel
                )

                // Encode as bulk JSON: { "type": "...", "count": N, "entries": [...] }
                let tableJSON = TableJSON(
                    type: definition.name,
                    count: entries.count,
                    entries: entries
                )
                if let json: GoDData = try? JSONEncoder.pokemon.encode(tableJSON) {
                    try? fileSystem.writeFile(json, at: outputFolder.file(fileName), overwrite: true)
                }

                manifest.chunks.append(.init(
                    label: chunk.label,
                    type: .table,
                    file: fileName,
                    structType: definition.name,
                    countLabel: countLabel,
                    count: count
                ))

            case .assembly:
                let fileName = "\(chunk.label).s"
                let baseAddress = UInt32(chunk.offset) // relative to section, will be adjusted
                let text = assemblyExporter.format(
                    data: chunk.data,
                    baseAddress: baseAddress,
                    labels: chunk.labels,
                    pointers: chunk.pointers,
                    addressToLabel: addressToLabel,
                    sectionName: ".\(sectionName)"
                )
                let textData = GoDData(string: text, format: .utf8)
                try? fileSystem.writeFile(textData, at: outputFolder.file(fileName), overwrite: true)

                manifest.chunks.append(.init(
                    label: chunk.label,
                    type: .assembly,
                    file: fileName
                ))

            case .binary:
                let fileName = "\(chunk.label).bin"
                let binData = GoDData(byteStream: chunk.data, byteOrder: byteOrder)
                try? fileSystem.writeFile(binData, at: outputFolder.file(fileName), overwrite: true)

                manifest.chunks.append(.init(
                    label: chunk.label,
                    type: .binary,
                    file: fileName,
                    size: chunk.size
                ))
            }
        }

        // Write manifest
        if let manifestJSON: GoDData = try? JSONEncoder.pokemon.encode(manifest) {
            try? fileSystem.writeFile(manifestJSON, at: outputFolder.file("manifest.json"), overwrite: true)
        }

        return manifest
    }
}

// MARK: - Table JSON encoding

/// Bulk JSON format for table entries
struct TableJSON: Encodable {
    let type: String
    let count: Int
    let entries: [LabeledData]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(count, forKey: .count)

        var entriesContainer = container.nestedUnkeyedContainer(forKey: .entries)
        for entry in entries {
            var entryContainer = entriesContainer.nestedContainer(keyedBy: EntryCodingKeys.self)
            if let label = entry.label {
                try entryContainer.encode(label, forKey: .label)
            }
            try entryContainer.encode(entry.data, forKey: .data)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, count, entries
    }

    enum EntryCodingKeys: String, CodingKey {
        case label = "_label"
        case data
    }
}

// MARK: - JSONEncoder convenience

private extension JSONEncoder {
    static let pokemon: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
