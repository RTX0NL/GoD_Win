import GoDFoundation
import Structs

/// Reads a data section manifest and its files, producing binary output.
/// Orchestrates TypedDataImporter for struct/table chunks,
/// delegates assembly .s files to an ISA-specific assembler,
/// and reads raw .bin files directly.
public struct DataSectionImporter {

    private let typedImporter = TypedDataImporter()

    public init() {}

    /// Callback type for assembling .s files (ISA-specific, injected by caller)
    public typealias AssemblyCallback = (
        _ files: [(name: String, content: String)],
        _ baseAddress: UInt32,
        _ externalSymbols: [String: UInt32]
    ) throws -> GoDData

    /// Compute the size of each chunk without resolving labels.
    /// Used during the address allocation pass.
    ///
    /// - Parameters:
    ///   - manifest: The data section manifest
    ///   - sectionFolder: Folder containing the chunk files
    ///   - fileSystem: Filesystem for reading files
    ///   - structResolver: Resolves struct type names to definitions
    ///   - assemblySizeCallback: Computes size of an .s file without encoding
    /// - Returns: Array of (label, size) pairs in manifest order
    public func computeChunkSizes(
        manifest: DataSectionManifest,
        sectionFolder: Folder,
        fileSystem: FileSystemTree,
        structResolver: (String) -> StructDefinition?,
        assemblySizeCallback: ((_ files: [(name: String, content: String)]) -> Int)?
    ) -> [(label: String, size: Int)] {
        var sizes = [(label: String, size: Int)]()

        for chunk in manifest.chunks {
            let size: Int
            switch chunk.type {
            case .struct:
                if let structType = chunk.structType,
                   let definition = structResolver(structType) {
                    size = definition.length
                } else {
                    size = 0
                }

            case .table:
                if let structType = chunk.structType,
                   let definition = structResolver(structType),
                   let count = chunk.count {
                    size = definition.length * count
                } else {
                    size = 0
                }

            case .assembly:
                let file = sectionFolder.file(chunk.file)
                if let data = fileSystem.readFile(at: file)?.allData,
                   let callback = assemblySizeCallback {
                    let content = data.string(format: .utf8)
                    size = callback([(chunk.file, content)])
                } else {
                    size = 0
                }

            case .binary, .file:
                if let declaredSize = chunk.size {
                    size = declaredSize
                } else {
                    let file = sectionFolder.file(chunk.file)
                    size = fileSystem.readFile(at: file)?.allData?.length ?? 0
                }
            }

            sizes.append((label: chunk.label, size: size))
        }

        return sizes
    }

    /// Assemble a data section from its manifest and files.
    ///
    /// - Parameters:
    ///   - manifest: The data section manifest
    ///   - sectionFolder: Folder containing the chunk files
    ///   - baseAddress: RAM address of this section
    ///   - fileSystem: Filesystem for reading files
    ///   - labelTable: For resolving label names to addresses
    ///   - structResolver: Resolves struct type names to definitions
    ///   - byteOrder: Byte order for the output binary
    ///   - assemblyCallback: ISA-specific assembler for .s files
    /// - Returns: Binary data for the entire section
    public func assemble(
        manifest: DataSectionManifest,
        sectionFolder: Folder,
        baseAddress: UInt32,
        fileSystem: FileSystemTree,
        labelTable: LabelTable,
        structResolver: (String) -> StructDefinition?,
        byteOrder: ByteOrder,
        assemblyCallback: AssemblyCallback
    ) throws -> GoDData {
        let result = GoDData(length: 0, byteOrder: byteOrder)
        var currentAddress = baseAddress

        for chunk in manifest.chunks {
            let file = sectionFolder.file(chunk.file)

            switch chunk.type {
            case .struct:
                guard let structType = chunk.structType,
                      let definition = structResolver(structType),
                      let jsonData = fileSystem.readFile(at: file)?.allData else {
                    continue
                }
                // Decode JSON → StructData. The dump-side wrapping (DOL
                // `BulkTableJSON`-style) optionally puts the field map
                // under a "data" key; accept both shapes by trying the
                // root dict first and falling back to `obj["data"]`.
                let structData: StructData = {
                    if let obj = try? JSONSerialization.jsonObject(
                        with: Data(jsonData.rawBytes)) as? [String: Any] {
                        let payload = (obj["data"] as? [String: Any]) ?? obj
                        return typedImporter.decodeStruct(
                            from: payload,
                            definition: definition,
                            byteOrder: byteOrder
                        )
                    }
                    return StructData(definition: definition, byteOrder: byteOrder)
                }()
                let imported = typedImporter.importStruct(
                    structData: structData,
                    labelTable: labelTable,
                    byteOrder: byteOrder
                )
                result.append(imported)
                currentAddress += UInt32(definition.length)

            case .table:
                guard let structType = chunk.structType,
                      let definition = structResolver(structType),
                      let count = chunk.count else {
                    continue
                }
                let entries: [LabeledData]
                if let jsonData = fileSystem.readFile(at: file)?.allData,
                   let decoded = typedImporter.decodeTable(
                    jsonBytes: jsonData,
                    definition: definition,
                    byteOrder: byteOrder
                   ) {
                    entries = decoded
                } else {
                    entries = []
                }
                // Pad-or-truncate to the manifest's declared count so
                // section size stays stable even if the JSON has been
                // hand-edited to add/remove rows. Surplus entries are
                // dropped; missing ones are filled with a zero StructData.
                var normalized = Array(entries.prefix(count))
                while normalized.count < count {
                    normalized.append(LabeledData(
                        label: nil,
                        data: StructData(definition: definition, byteOrder: byteOrder)
                    ))
                }
                let tableData = typedImporter.importTable(
                    entries: normalized,
                    definition: definition,
                    labelTable: labelTable,
                    byteOrder: byteOrder
                )
                result.append(tableData)
                currentAddress += UInt32(definition.length * count)

            case .assembly:
                guard let fileData = fileSystem.readFile(at: file)?.allData else { continue }
                let content = fileData.string(format: .utf8)
                let assembled = try assemblyCallback(
                    [(chunk.file, content)],
                    currentAddress,
                    labelTable.allLabels
                )
                result.append(assembled)
                currentAddress += UInt32(assembled.length)

            case .binary, .file:
                guard let binData = fileSystem.readFile(at: file)?.allData else { continue }
                result.append(binData)
                currentAddress += UInt32(binData.length)
            }
        }

        return result
    }
}
