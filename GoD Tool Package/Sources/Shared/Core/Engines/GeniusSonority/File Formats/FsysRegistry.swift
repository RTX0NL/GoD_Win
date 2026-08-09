import GoDFoundation
import GoDEngine
import Structs
import GTX

public struct FSYSRegistry: Codable {
    
    /// Binds a struct-typed data-table entry (a `common.fsys` table) to the
    /// editable files it was dumped to and the structs that reconstruct it.
    /// The entry's `file` is the row CSV; this carries the rest. The struct
    /// names are resolved against definitions supplied at pack time (they
    /// live in a game engine, not here), so this stays game-agnostic.
    public struct DataTableMetadata: Codable {
        public let tableName: String
        public let entryStructName: String
        public let headerStructName: String
        public let headerFile: File
        /// Raw string-pool bytes (with padding), if the table has one.
        public let leadingExtraFile: File?
        /// Raw name-table + relocation-table bytes, if the table has them.
        public let trailingExtraFile: File?

        public init(
            tableName: String, entryStructName: String, headerStructName: String,
            headerFile: File, leadingExtraFile: File?, trailingExtraFile: File?
        ) {
            self.tableName = tableName
            self.entryStructName = entryStructName
            self.headerStructName = headerStructName
            self.headerFile = headerFile
            self.leadingExtraFile = leadingExtraFile
            self.trailingExtraFile = trailingExtraFile
        }
    }

    public struct Entry: Codable {
        /// For THP-pair entries, this is the THH metadata (the "primary"
        /// of the pair). `thdMetadata` below carries the THD sibling.
        public let metadata: FSYSArchive.Entry.MetaData
        public let file: File
        /// For GTX entries: texture metadata needed for re-encoding from PNG
        public let textureMetadata: GXTextureMetadata?
        /// For ATX entries: wrapper prefix + inner texture metadata for 1:1 rebuild from PNG
        public let atxMetadata: ATXMetadata?
        /// For THP-pair entries (THH + THD fused into one `.thp`): the
        /// THD sibling's FSYS metadata. Present only when `file` points
        /// at a combined `.thp`. On pack, the `.thp` is split back into
        /// THH + THD bytes and two FSYS entries are emitted using
        /// `metadata` and `thdMetadata` respectively.
        public let thdMetadata: FSYSArchive.Entry.MetaData?
        /// For struct-typed data tables (`common.fsys`): the CSV/header/extras
        /// and the structs that rebuild the table binary. When set, `file` is
        /// the row CSV.
        public let dataTable: DataTableMetadata?

        public init(
            metadata: FSYSArchive.Entry.MetaData,
            file: File,
            textureMetadata: GXTextureMetadata? = nil,
            atxMetadata: ATXMetadata? = nil,
            thdMetadata: FSYSArchive.Entry.MetaData? = nil,
            dataTable: DataTableMetadata? = nil
        ) {
            self.metadata = metadata
            self.file = file
            self.textureMetadata = textureMetadata
            self.atxMetadata = atxMetadata
            self.thdMetadata = thdMetadata
            self.dataTable = dataTable
        }
    }
    
    public let groupID: Int
    public let metaData: FSYSArchive.MetaData
    public let entries: [Entry]
    
    public init(groupID: Int, metaData: FSYSArchive.MetaData, entries: [Entry]) {
        self.groupID = groupID
        self.metaData = metaData
        self.entries = entries
    }
}
