import GoDFoundation

extension DolAssembly {
    struct Config: Codable {
        let codeFolder: Folder
        let outputDolPath: File
        let symbolMapPath: File?
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

        init(
            codeFolder: Folder,
            outputDolPath: File,
            symbolMapPath: File? = nil,
            dolphinEngine: Folder,
            typeMapPath: File? = nil,
            engines: [Folder]? = nil,
            bssEntryListPath: File? = nil,
            sdaBase: UInt32? = nil,
            sda2Base: UInt32? = nil
        ) {
            self.codeFolder = codeFolder
            self.outputDolPath = outputDolPath
            self.symbolMapPath = symbolMapPath
            self.dolphinEngine = dolphinEngine
            self.typeMapPath = typeMapPath
            self.engines = engines
            self.bssEntryListPath = bssEntryListPath
            self.sdaBase = sdaBase
            self.sda2Base = sda2Base
        }
    }
}
