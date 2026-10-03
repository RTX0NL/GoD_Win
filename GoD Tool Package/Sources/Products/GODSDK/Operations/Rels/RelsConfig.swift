import GoDFoundation

/// Disassembles every REL a `RelRouteTable` names, each with the type map and
/// symbol index of the matcher its route points at. Each REL's source lands
/// at its route path with `.rel` dropped, under `outputFolder`, so the source
/// tree mirrors the unpacked one.
///
/// This is how a project dumps its maps, menu modules and one-off typed RELs
/// alike — `common.rel` keeps its own operation, because it needs
/// region-keyed maps rather than a route.
enum RelsDump {
    struct Config: Codable {
        /// The route table (`rel_routes.json`).
        let routesPath: File
        /// Folder the matchers' `typeMap` / `symbolIndex` paths resolve
        /// against — the game engine the table ships in.
        let routesEngine: Folder
        /// Root the route keys are relative to — the unpacked project tree.
        let inputFolder: Folder
        /// Root of the source tree: `D2_out.rel` routed at
        /// `/Data/Relocatable Modules/D2_out.rel` lands in
        /// `outputFolder/Data/Relocatable Modules/D2_out/`.
        let outputFolder: Folder
        /// Replace a REL's source folder if it already holds a manifest.
        /// `false` leaves already-dumped (and possibly edited) RELs alone.
        let overwrite: Bool
        let dolphinEngine: Folder
        /// DOL symbol map for naming cross-module relocation targets.
        let dolSymbolMapPath: File?
        /// Engine folders whose structs resolve the type maps' chunk types,
        /// combined in order. Absent = just `routesEngine`.
        let engines: [Folder]?

        init(
            routesPath: File,
            routesEngine: Folder,
            inputFolder: Folder,
            outputFolder: Folder,
            overwrite: Bool,
            dolphinEngine: Folder,
            dolSymbolMapPath: File? = nil,
            engines: [Folder]? = nil
        ) {
            self.routesPath = routesPath
            self.routesEngine = routesEngine
            self.inputFolder = inputFolder
            self.outputFolder = outputFolder
            self.overwrite = overwrite
            self.dolphinEngine = dolphinEngine
            self.dolSymbolMapPath = dolSymbolMapPath
            self.engines = engines
        }
    }
}

/// Reassembles every routed REL whose source folder `relsDump` wrote, back
/// to the path its route names. The manifests carry each chunk's type, so the
/// build needs the route table only for *where* each REL goes.
enum RelsBuild {
    struct Config: Codable {
        /// The route table (`rel_routes.json`).
        let routesPath: File
        /// Root of the source tree `relsDump` wrote.
        let inputFolder: Folder
        /// Root the route keys are relative to — the unpacked project tree.
        let outputFolder: Folder
        let overwrite: Bool
        /// Engine folders whose structs resolve typed chunks in the sources,
        /// game definitions first. Absent = none.
        let engines: [Folder]?

        init(
            routesPath: File,
            inputFolder: Folder,
            outputFolder: Folder,
            overwrite: Bool = true,
            engines: [Folder]? = nil
        ) {
            self.routesPath = routesPath
            self.inputFolder = inputFolder
            self.outputFolder = outputFolder
            self.overwrite = overwrite
            self.engines = engines
        }
    }
}
