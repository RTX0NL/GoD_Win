import GoDFoundation

extension DolAssembly {
    struct Config: Codable {
        let codeFolder: Folder
        let outputDolPath: File
        let symbolMapPath: File?
        /// Where to write the symbol map the assembly produced, with every
        /// symbol at the address it ended up at. Absent = don't write one.
        ///
        /// Normally this is `symbolMapPath` itself: a rebuild that changes a
        /// chunk's size moves every later symbol, and the map is what the
        /// next disassembly reads addresses out of, so leaving the old one
        /// in place makes the project's own type map name the wrong bytes.
        /// Project setup points it at the input map for exactly that reason.
        let outputSymbolMapPath: File?
        let dolphinEngine: Folder
        /// Optional path to a type map file for typed data section import
        let typeMapPath: File?
        /// Engine folders whose structs resolve the type map's chunk types.
        /// Each should point at an engine folder containing `Structs/*.json`.
        /// Absent = none (type-map chunks fall back to the built-in XD structs).
        let engines: [Folder]?
        /// Optional path to the BSS entry list file
        let bssEntryListPath: File?
        /// Optional override for the small data area base (_SDA_BASE_, r13).
        /// When nil, the base is auto-detected from the assembled
        /// __init_registers sequence. Sections in the ±0x8000 window around
        /// it must not change size — r13-relative accesses use fixed
        /// displacements that never relocate.
        let sdaBase: UInt32?
        /// Optional override for the small data area 2 base (_SDA2_BASE_, r2).
        let sda2Base: UInt32?
        /// Accept a chunk or section that rebuilds larger than the size the
        /// disassembly recorded for it. Absent = false, which stops the
        /// assembly and names the chunk.
        ///
        /// A chunk runs from its own symbol to the next, so growing one
        /// pushes every symbol after it along and the addresses the type map
        /// resolves through stop matching the data. Setting this says the
        /// shift is intended; `outputSymbolMapPath` is what then keeps the
        /// next disassembly able to find things. A chunk that rebuilds
        /// *smaller* is always zero-padded back to size and never needs this.
        let allowResizedChunks: Bool?

        init(
            codeFolder: Folder,
            outputDolPath: File,
            symbolMapPath: File? = nil,
            outputSymbolMapPath: File? = nil,
            dolphinEngine: Folder,
            typeMapPath: File? = nil,
            engines: [Folder]? = nil,
            bssEntryListPath: File? = nil,
            sdaBase: UInt32? = nil,
            sda2Base: UInt32? = nil,
            allowResizedChunks: Bool? = nil
        ) {
            self.codeFolder = codeFolder
            self.outputDolPath = outputDolPath
            self.symbolMapPath = symbolMapPath
            self.outputSymbolMapPath = outputSymbolMapPath
            self.dolphinEngine = dolphinEngine
            self.typeMapPath = typeMapPath
            self.engines = engines
            self.bssEntryListPath = bssEntryListPath
            self.sdaBase = sdaBase
            self.sda2Base = sda2Base
            self.allowResizedChunks = allowResizedChunks
        }
    }
}
