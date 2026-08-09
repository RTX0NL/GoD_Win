// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
            name: "GoD Tool CLI",
            targets: ["GoD Tool CLI"]
        ),
        .executable(
            name: "Discord Plays Orre",
            targets: ["Discord Plays Orre"]
        ),
        .executable(
            name: "ColoScriptDecomp",
            targets: ["ColoScriptDecomp"]
        ),
        
        // MARK: - Base Library Products
        
        .library(
            name: "BaseApp",
            targets: ["BaseApp"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/tayloraswift/swift-png", from: "4.0.2"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
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
                .product(name: "MCP", package: "swift-sdk")
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
            name: "GoD Tool CLI",
            dependencies: [
                "GoDFoundation",
                "GoDEngine",
                "GameCube",
                "GoDCLI",
                "Persistence"
            ],
            path: "Sources/Products/GoD Tool CLI"
        ),
        .executableTarget(
            name: "Discord Plays Orre",
            dependencies: [
            ],
            path: "Sources/Products/Discord Plays Orre"
        ),
        .executableTarget(
            // Temporary decompiler-validation harness — remove when done.
            name: "ColoScriptDecomp",
            dependencies: [
                "Colosseum",
                "ScriptDecompiler",
                "GoDFoundation"
            ],
            path: "Sources/Products/ColoScriptDecomp"
        ),
        .executableTarget(
            name: "FixtureGen",
            dependencies: [
                "FixtureCatalog"
            ],
            path: "Sources/Products/FixtureGen"
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
        .target(
            name: "GoDCLI",
            dependencies: [
                "GoDFoundation",
                "Persistence"
            ],
            path: "Sources/Shared/Core/Contexts/CLI"
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
                "ScriptDecompiler"
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
            name: "Orre",
            dependencies: [
                "GoDEngine",
                "GoDFoundation",
                "Structs"
            ],
            path: "Sources/Shared/Core/Engines/Orre"
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
                "Pokemon"
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
                "ScriptDecompiler"
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
        
        // MARK: - Dependency Library Targets
        .target(
            name: "GoDFoundation",
            dependencies: [
                .product(name: "PNG", package: "swift-png"),
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
            dependencies: ["Dolphin", "GoDFoundation", "Structs", "TestSupport"],
            path: "Tests/Shared Tests/Engine Tests/Dolphin Tests",
            exclude: ["Fixtures"]),
        .testTarget(
            name: "WiiTests",
            dependencies: ["Wii", "Dolphin", "GoDFoundation", "Structs", "FixtureCatalog"],
            path: "Tests/Shared Tests/Engine Tests/Wii Tests"),
        .testTarget(
            name: "GameCubeTests",
            dependencies: ["GameCube", "Dolphin", "GoDFoundation", "Structs", "TestSupport"],
            path: "Tests/Shared Tests/Engine Tests/GameCube Tests",
            exclude: ["Fixtures"]),
        .testTarget(
            name: "ColosseumTests",
            dependencies: ["Colosseum", "GeniusSonority", "GoDFoundation", "ScriptDecompiler", "GTX", "TestSupport", "FixtureCatalog"],
            path: "Tests/Shared Tests/Engine Tests/Colosseum Tests",
            exclude: ["Fixtures"]),
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

