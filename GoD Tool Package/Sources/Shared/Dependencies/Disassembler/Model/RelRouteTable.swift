import GoDFoundation

/// Which type map and symbol index describe each REL a project unpacks.
///
/// A game ships a few hundred RELs and only a handful of layouts, so the
/// table has two halves: a small set of named **matchers** — a type map plus
/// a pointer-index symbol index, either optional — and a **route** for every
/// REL naming the matcher that describes it. Many routes share one matcher.
///
/// This replaced two mechanisms that each answered the question partially:
/// map "plans" that picked RELs by filename prefix or by a runtime layout
/// heuristic, and a list of one-off files with their own maps. A prefix or a
/// heuristic decides the layout of a file nobody has looked at; a route says
/// which layout a file was *found* to have, and a REL no route names is
/// reported rather than typed by guesswork.
///
/// Paths inside a matcher are relative to the engine folder the table ships
/// in. Route keys are paths relative to the unpacked project root — the full
/// path, because a stem alone is not unique: every disc carries `pda_menu.rel`
/// once per language folder, and `worldmap_menu.rel` in two archives' folders.
/// One table serves every region, so a route naming a file this disc doesn't
/// ship is skipped rather than fatal.
public struct RelRouteTable: Codable, Equatable {

    public struct Matcher: Codable, Equatable {
        /// Type map for the module's data sections. Absent = untyped: the
        /// module still disassembles, with every data chunk left raw.
        public var typeMap: File?
        /// Pointer index → symbol name for the module's relocation targets.
        /// Absent = targets keep their positional `sym_N` names.
        public var symbolIndex: File?

        public init(typeMap: File? = nil, symbolIndex: File? = nil) {
            self.typeMap = typeMap
            self.symbolIndex = symbolIndex
        }
    }

    /// One REL the table names, resolved against a project root.
    public struct Route: Equatable {
        /// The REL's path relative to the unpacked root.
        public let path: String
        /// The REL's file name without `.rel` — the name of its manifest.
        public let stem: String
        /// Where the REL's source lives, relative to a source root: its path
        /// with `.rel` dropped, so the source tree mirrors the unpacked one
        /// and two RELs sharing a stem can't share a folder.
        public let sourcePath: String
        public let matcherName: String
        public let matcher: Matcher
    }

    public var matchers: [String: Matcher]
    /// REL path relative to the unpacked project root → matcher name.
    public var routes: [String: String]
    /// RELs another operation owns (`common.rel`), relative to the unpacked
    /// root. Listed so that "no route" means *forgotten* and can be warned
    /// about, rather than being the normal state of a file handled elsewhere.
    public var ignored: [String]

    public init(matchers: [String: Matcher] = [:], routes: [String: String] = [:], ignored: [String] = []) {
        self.matchers = matchers
        self.routes = routes
        self.ignored = ignored
    }

    private enum CodingKeys: String, CodingKey {
        case matchers, routes, ignored
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchers = try container.decode([String: Matcher].self, forKey: .matchers)
        routes = try container.decode([String: String].self, forKey: .routes)
        // A table that ignores nothing needn't say so.
        ignored = try container.decodeIfPresent([String].self, forKey: .ignored) ?? []
    }

    /// Every route with its matcher, sorted by path.
    ///
    /// Throws if a route names a matcher the table doesn't define, or doesn't
    /// name a `.rel` — its source path is the route with the extension
    /// dropped, so anything else could land on another route's folder.
    public func resolvedRoutes() throws -> [Route] {
        try routes.keys.sorted().map { path in
            let matcherName = routes[path] ?? ""
            guard let matcher = matchers[matcherName] else {
                throw RelRouteTableError.unknownMatcher(route: path, matcher: matcherName, .init())
            }
            guard File(path).fileType == "rel" else {
                throw RelRouteTableError.notARel(route: path, .init())
            }
            return Route(
                path: path,
                stem: File(path).fileName.withoutExtensions,
                sourcePath: String(path.dropLast(".rel".count)),
                matcherName: matcherName,
                matcher: matcher
            )
        }
    }

    /// Every file a matcher points at, for installing the table's resources.
    public var matcherFiles: [File] {
        Set(matchers.values.flatMap { [$0.typeMap, $0.symbolIndex].compactMap { $0 } })
            .sorted()
    }
}

public enum RelRouteTableError: Error, CustomStringConvertible {
    case unknownMatcher(route: String, matcher: String, ErrorTrace)
    case notARel(route: String, ErrorTrace)

    public var description: String {
        switch self {
        case let .unknownMatcher(route, matcher, trace):
            return "REL route \(route) names matcher '\(matcher)', which the table doesn't define\n\(trace)"
        case let .notARel(route, trace):
            return "REL route \(route) doesn't name a .rel file\n\(trace)"
        }
    }
}
