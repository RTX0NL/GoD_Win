// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// The upstream MCP SDK doesn't compile on Windows (it mistakes Windows for an
// Apple platform in one file), so Windows builds use a patched copy — see
// Vendored/swift-sdk/README.md. Every other platform uses upstream.
#if os(Windows)
let mcpSDK: Package.Dependency = .package(path: "Vendored/swift-sdk")
#else
let mcpSDK: Package.Dependency = .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0")
#endif

let package = Package(
    name: "GoD Tool Package",
    // The existing code predates Swift Concurrency's strict checking; keep the
    // whole package in the Swift 5 language mode so the 6.0 toolchain bump
    // (needed for the MCP SDK) doesn't force a repo-wide concurrency migration.
    // New targets can opt into `.v6` individually via swiftSettings.
    platforms: [
        .macOS(.v13),
    ],
    products: [
        // MARK: - Executable Products
        
        .executable(
            name: "GODDESS",
            targets: ["GODDESS"]
        ),
        .executable(
            name: "GoD Tool App",
            targets: ["GoD Tool UI"]
        ),
        .executable(
            name: "Discord Plays Orre",
            targets: ["Discord Plays Orre"]
        ),
        
        // MARK: - Base Library Products
        
        .library(
            name: "BaseApp",
            targets: ["BaseApp"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // swift-png's own dependency, kept because its `LZ77` and `PNG`
        // targets are vendored under Sources/Shared/Dependencies/Third Party.
        .package(url: "https://github.com/rarestype/h", from: "1.0.1"),
        mcpSDK,
        // Already pulled in by swift-sdk; named directly because the Windows
        // stdio transport has to spell `Logger` itself.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        // MARK: - Executable Targets
        
        // Shared operations/config/dispatch library. Both the GODDESS CLI and
        // the MCP server link this — one source of truth for how the tool runs.
        .target(
            name: "GODOps",
            dependencies: [
                "GoDEngine",
                "GameCube",
                "Dolphin",
                "Wii",
                "PBR",
                "XD",
                "Colosseum",
                "Pokemon",
                "GeniusSonority",
                "Nintendo",
                "GoDFoundation",
                "Disassembler"
            ],
            path: "Sources/Products/GODSDK"
        ),
        .executableTarget(
            name: "GODDESS",
            dependencies: [
                "GODOps",
                "GoDFoundation",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/Products/GODDESS"
        ),
        .executableTarget(
            name: "GoD Tool UI",
            dependencies: [
                "BaseApp"
            ],
            path: "Sources/Products/GoD Tool UI"
        ),
        .executableTarget(
            name: "Discord Plays Orre",
            dependencies: [
            ],
            path: "Sources/Products/Discord Plays Orre"
        ),
        
        // MARK: - Tool Targets
        
        // Development tooling, not shipped: materializes the golden fixtures
        // the test targets check against. See Sources/Tools/FixtureGen.
        .executableTarget(
            name: "FixtureGen",
            dependencies: [
                "FixtureCatalog"
            ],
            path: "Sources/Tools/FixtureGen"
        ),
        
        // MARK: - Base Library Targets
        
        .target(
            name: "BaseApp",
            dependencies: [
                "GoDEngine",
                "GameCube",
                "GoDFoundation",
                "GoDGUI",
                "Persistence"
            ],
            path: "Sources/Base/App",
            resources: []
        ),
        
        // MARK: - Core Library Targets
        
        .target(
            name: "GoDGUI",
            dependencies: [
//                .product(name: "TokamakShim", package: "Tokamak")
            ],
            path: "Sources/Shared/Core/Contexts/GUI"
        ),
        
        // MARK: - Core Library Engine Targets

        .target(
            name: "GoDEngine",
            dependencies: [
                "GoDFoundation",
                "Structs"
            ],
            path: "Sources/Shared/Core/Engines/Engine"),
        .target(
            name: "Colosseum",
            dependencies: [
                "GoDEngine",
                "GoDFoundation",
                "Structs",
                "GameCube",
                "Pokemon",
                "ScriptDecompiler",
                // `RelRouteTable`, to install the files its route table names.
                "Disassembler"
            ],
            path: "Sources/Shared/Core/Engines/Colosseum",
            resources: [.process("Resources")]
        ),
        .target(
            name: "GameCube",
            dependencies: [
                "GoDEngine",
                "Dolphin",
                "GoDFoundation",
                "GTX",
                "Structs"
            ],
            path: "Sources/Shared/Core/Engines/GameCube"
        ),
        .target(
            name: "Dolphin",
            dependencies: [
                "GoDEngine",
                "GoDFoundation",
                "Structs",
                // The DOL disassembly/assembly pipeline needs both this
                // module's PowerPC types and the ISA-agnostic section/type-map
                // machinery. The dependency runs this way round so
                // `Disassembler` stays free of any instruction set.
                "Disassembler"
            ],
            path: "Sources/Shared/Core/Engines/Dolphin"
        ),
        .target(
            name: "Nintendo",
            dependencies: [
                "GoDEngine",
                "GoDFoundation",
                "Structs"
            ],
            path: "Sources/Shared/Core/Engines/Nintendo"
        ),
        .target(
            name: "GeniusSonority",
            dependencies: [
                "GoDEngine",
                "GoDFoundation",
                "Structs",
                "GTX",
                // Save-card region and integrity declarations are written
                // in the platform's own terms — see Constants/entries/SaveCard.swift.
                "GameCube",
                // The disc's FST can hold Nintendo containers alongside
                // FSYS archives, and the rebuild repacks them from their
                // manifests — see `FSTRegistry.EntryType.nintendoArchive`.
                "Nintendo"
            ],
            path: "Sources/Shared/Core/Engines/GeniusSonority"
        ),
        .target(
            name: "PBR",
            dependencies: [
                "GoDEngine",
                "GoDFoundation",
                "Structs",
                "Wii",
                "Pokemon",
                // PBR is a Genius Sonority title: it ships FSYS archives and
                // reuses most of the shared file formats. It depends on that
                // engine so it can specialise the parts that differ — most
                // visibly `.fnt`, which names a different format here than it
                // does in Colosseum/XD. GeniusSonority does not depend back.
                "GeniusSonority"
            ],
            path: "Sources/Shared/Core/Engines/PBR"
        ),
        .target(
            name: "Pokemon",
            dependencies: [
                "GoDFoundation",
                "GoDEngine",
                "Structs"
            ],
            path: "Sources/Shared/Core/Engines/Pokemon"
        ),
        .target(
            name: "Wii",
            dependencies: [
                "GoDEngine",
                "Dolphin",
                "GoDFoundation",
                "Structs"
            ],
            path: "Sources/Shared/Core/Engines/Wii"
        ),
        .target(
            name: "XD",
            dependencies: [
                "GoDEngine",
                "GoDFoundation",
                "Structs",
                "GameCube",
                "Pokemon",
                "ScriptDecompiler",
                // `RelRouteTable`, to install the files its route table names.
                "Disassembler"
            ],
            path: "Sources/Shared/Core/Engines/XD",
            resources: [.copy("Resources")]
        ),
        
        // MARK: - Feature Library Targets
        .target(
            name: "Persistence",
            dependencies: [
                "GoDFoundation",
            ],
            path: "Sources/Shared/Dependencies/Persistence",
            resources: []
        ),
        
        // MARK: - Vendored Third Party Targets

        // swift-png 4.5.1, carrying one local fix to its DEFLATE final-flush
        // path — see that folder's README. Vendored rather than depended on
        // because the bug silently truncates encoded images and there is no
        // upstream release with the fix.
        .target(
            name: "LZ77",
            dependencies: [
                .product(name: "CRC", package: "h"),
            ],
            path: "Sources/Shared/Dependencies/Third Party/swift-png/LZ77"
        ),
        .target(
            name: "PNG",
            dependencies: [
                "LZ77",
            ],
            path: "Sources/Shared/Dependencies/Third Party/swift-png/PNG"
        ),

        // MARK: - Dependency Library Targets
        .target(
            name: "GoDFoundation",
            dependencies: [
                "PNG",
            ],
            path: "Sources/Shared/Dependencies/GoDFoundation",
            resources: []
        ),
        .target(
            name: "GoDNetworking",
            dependencies: [
                "GoDFoundation"
            ],
            path: "Sources/Shared/Dependencies/Networking",
            resources: []
        ),
        .target(
            name: "Structs",
            dependencies: [
                "GoDFoundation",
            ],
            path: "Sources/Shared/Dependencies/Structs",
            resources: []
        ),
        .target(
            name: "Disassembler",
            dependencies: [
                "GoDFoundation",
                "Structs",
            ],
            path: "Sources/Shared/Dependencies/Disassembler",
            resources: []
        ),
        .target(
            name: "GTX",
            dependencies: [
                "GoDFoundation",
            ],
            path: "Sources/Shared/Dependencies/GTX",
            resources: []
        ),
        .target(
            name: "ScriptDecompiler",
            dependencies: [
                "GoDFoundation",
            ],
            path: "Sources/Shared/Dependencies/ScriptDecompiler",
            resources: []
        ),
        .target(
            name: "TestSupport",
            dependencies: [
                "GoDFoundation",
            ],
            path: "Sources/Shared/Dependencies/TestSupport",
            resources: []
        ),
        .target(
            name: "FixtureCatalog",
            dependencies: [
                "GoDFoundation",
                "GeniusSonority",
                "Dolphin",
                "GameCube",
                "GTX",
                "Disassembler",
            ],
            path: "Sources/Shared/Dependencies/FixtureCatalog",
            resources: []
        ),
        
        // MARK: - Test Targets
        
        .testTarget(
            name: "GoDFoundationTests",
            dependencies: ["GoDFoundation", "TestSupport"],
            path: "Tests/Shared Tests/Dependency Tests/GoD Foundation Tests",
            exclude: ["Fixtures"]),
        .testTarget(
            name: "GoDStructTests",
            dependencies: ["Structs"],
            path: "Tests/Shared Tests/Dependency Tests/GoD Struct Tests"),
        .testTarget(
            name: "DisassemblerTests",
            dependencies: ["Disassembler", "Structs", "GoDFoundation", "TestSupport", "FixtureCatalog"],
            path: "Tests/Shared Tests/Dependency Tests/Disassembler Tests",
            exclude: ["Fixtures"]),
        .testTarget(
            name: "ScriptDecompilerTests",
            dependencies: ["ScriptDecompiler", "GoDFoundation"],
            path: "Tests/Shared Tests/Dependency Tests/Script Decompiler Tests"),
        .testTarget(
            name: "GoDEngineTests",
            dependencies: ["GoDEngine", "GoDFoundation", "Structs"],
            path: "Tests/Shared Tests/Engine Tests/Core Engine Tests"),
        .testTarget(
            name: "PPCTests",
            dependencies: ["Dolphin", "GoDFoundation"],
            path: "Tests/Shared Tests/Engine Tests/PPC Tests"),
        .testTarget(
            name: "DolphinTests",
            dependencies: ["Dolphin", "GoDFoundation", "Structs", "TestSupport", "FixtureCatalog"],
            path: "Tests/Shared Tests/Engine Tests/Dolphin Tests",
            exclude: ["Fixtures"]),
        .testTarget(
            name: "WiiTests",
            dependencies: ["Wii", "Dolphin", "GoDFoundation", "Structs", "FixtureCatalog"],
            path: "Tests/Shared Tests/Engine Tests/Wii Tests"),
        .testTarget(
            name: "GameCubeTests",
            dependencies: ["GameCube", "Dolphin", "GoDFoundation", "GTX", "Structs", "TestSupport"],
            path: "Tests/Shared Tests/Engine Tests/GameCube Tests",
            exclude: ["Fixtures"]),
        .testTarget(
            name: "ColosseumTests",
            dependencies: ["Colosseum", "GeniusSonority", "Nintendo", "GoDFoundation", "ScriptDecompiler", "GTX", "TestSupport", "FixtureCatalog"],
            path: "Tests/Shared Tests/Engine Tests/Colosseum Tests",
            exclude: ["Fixtures"]),
        .testTarget(
            name: "PokemonTests",
            dependencies: ["Pokemon", "GoDEngine", "GoDFoundation", "Structs"],
            path: "Tests/Shared Tests/Engine Tests/Pokemon Tests"),
        .testTarget(
            name: "XDTests",
            dependencies: ["XD", "GoDFoundation"],
            path: "Tests/Shared Tests/Engine Tests/XD Tests"),
        .testTarget(
            name: "NintendoTests",
            dependencies: ["Nintendo", "GoDFoundation", "TestSupport"],
            path: "Tests/Shared Tests/Engine Tests/Nintendo Tests"),
        .testTarget(
            name: "PBRTests",
            dependencies: ["PBR", "GeniusSonority", "GoDEngine", "GoDFoundation", "Structs"],
            path: "Tests/Shared Tests/Engine Tests/PBR Tests"),
        .testTarget(
            name: "GODOpsTests",
            dependencies: [
                "GODOps",
                "GoDFoundation",
                "GoDEngine",
                "Structs",
                "GameCube",
                "Dolphin",
                "Wii",
                "Colosseum",
                "GeniusSonority",
                "XD",
                "Pokemon",
                "TestSupport",
                "FixtureCatalog"
            ],
            path: "Tests/Products Tests/GODOps Tests"),
    ],
    swiftLanguageModes: [.v5]
)

#if os(Windows)
// SwiftUI doesn't exist on Windows, so the GUI app and the two libraries only
// it uses can never build there. Leaving them in would make `swift build` and
// `swift test` (which build every target) fail before reaching the CLI.
let swiftUIOnlyTargets: Set<String> = ["GoD Tool UI", "BaseApp", "GoDGUI"]
let swiftUIOnlyProducts: Set<String> = ["GoD Tool App", "BaseApp"]
package.targets = package.targets.filter { !swiftUIOnlyTargets.contains($0.name) }
package.products = package.products.filter { !swiftUIOnlyProducts.contains($0.name) }
#endif

