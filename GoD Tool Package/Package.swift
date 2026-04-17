// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GoD Tool Package",
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
        
        // MARK: - Base Library Products
        
        .library(
            name: "BaseApp",
            targets: ["BaseApp"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/tayloraswift/swift-png", from: "4.0.2"),
    ],
    targets: [
        // MARK: - Executable Targets
        
        .executableTarget(
            name: "GODDESS",
            dependencies: [
                "GoDEngine",
                "GameCube",
                "Dolphin",
                "Wii",
                "PBR",
                "XD",
                "Colosseum",
                "GeniusSonority",
                "GoDFoundation",
                "Disassembler"
            ],
            path: "Sources/Products/GODSDK"
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
            path: "Sources/Shared/Core/Contexts/GUI",
            resources: [.process("Resources")]
        ),
        .target(
            name: "GoDCLI",
            dependencies: [
                "GoDFoundation",
                "Persistence"
            ],
            path: "Sources/Shared/Core/Contexts/CLI",
            resources: [.process("Resources")]
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
            path: "Sources/Shared/Core/Engines/GameCube",
            resources: [.process("Resources")]
        ),
        .target(
            name: "Dolphin",
            dependencies: [
                "GoDEngine",
                "GoDFoundation",
                "Structs"
            ],
            path: "Sources/Shared/Core/Engines/Dolphin",
            resources: [.process("Resources")]
        ),
        .target(
            name: "Orre",
            dependencies: [
                "GoDEngine",
                "GoDFoundation",
                "Structs"
            ],
            path: "Sources/Shared/Core/Engines/Orre",
            resources: [.process("Resources")]
        ),
        .target(
            name: "GeniusSonority",
            dependencies: [
                "GoDEngine",
                "GoDFoundation",
                "Structs",
                "GTX"
            ],
            path: "Sources/Shared/Core/Engines/GeniusSonority",
            resources: [.process("Resources")]
        ),
        .target(
            name: "PBR",
            dependencies: [
                "GoDFoundation",
                "Wii",
                "Pokemon"
            ],
            path: "Sources/Shared/Core/Engines/PBR",
            resources: [.process("Resources")]
        ),
        .target(
            name: "Pokemon",
            dependencies: [
                "GoDFoundation"
            ],
            path: "Sources/Shared/Core/Engines/Pokemon",
            resources: [.process("Resources")]
        ),
        .target(
            name: "Wii",
            dependencies: [
                "GoDEngine",
                "Dolphin",
                "GoDFoundation",
                "Structs"
            ],
            path: "Sources/Shared/Core/Engines/Wii",
            resources: [.process("Resources")]
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
        
        // MARK: - Third Party Dependency Library Targets
        .target(
            name: "xxHash",
            dependencies: [
            ],
            path: "Sources/Shared/Dependencies/Third Party/xxHash",
            resources: []
        ),
        
        // MARK: - Test Targets
        
        .testTarget(
            name: "GoDFoundationTests",
            dependencies: ["GoDFoundation"],
            path: "Tests/Shared Tests/Dependency Tests/GoD Foundation Tests",
            resources: [.process("Resources")]),
        .testTarget(
            name: "GoDStructTests",
            dependencies: ["Structs"],
            path: "Tests/Shared Tests/Dependency Tests/GoD Struct Tests"),
        .testTarget(
            name: "PPCTests",
            dependencies: ["Dolphin", "GoDFoundation"],
            path: "Tests/Shared Tests/Engine Tests/PPC Tests"),
        .testTarget(
            name: "DolphinTests",
            dependencies: ["Dolphin", "GoDFoundation", "Structs"],
            path: "Tests/Shared Tests/Engine Tests/Dolphin Tests"),
        .testTarget(
            name: "WiiTests",
            dependencies: ["Wii", "Dolphin", "GoDFoundation", "Structs"],
            path: "Tests/Shared Tests/Engine Tests/Wii Tests"),
        .testTarget(
            name: "GameCubeTests",
            dependencies: ["GameCube", "Dolphin", "GoDFoundation", "Structs"],
            path: "Tests/Shared Tests/Engine Tests/GameCube Tests"),
        .testTarget(
            name: "ColosseumTests",
            dependencies: ["Colosseum", "GeniusSonority", "GoDFoundation", "ScriptDecompiler", "GTX"],
            path: "Tests/Shared Tests/Engine Tests/Colosseum Tests"),
        .testTarget(
            name: "XDTests",
            dependencies: ["XD", "GoDFoundation"],
            path: "Tests/Shared Tests/Engine Tests/XD Tests"),
    ]
)

