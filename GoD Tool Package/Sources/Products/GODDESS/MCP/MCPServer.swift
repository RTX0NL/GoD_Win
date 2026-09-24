//
//  MCPServer.swift
//  GODDESS
//
//  A stdio Model Context Protocol server that exposes GODDESS's operations to
//  MCP clients. Every tool is a thin dispatch into the shared `GODOps`
//  facade, so the server drives the exact same code paths as the CLI.
//
//  The server also sends MCP "instructions" in its initialize result —
//  server-wide guidance a client may place in the model's system prompt. It
//  carries what no single tool description can: how a project relates to the
//  GODDESS version that dumped it, and how to move one between versions.
//
//  Register with a client, e.g.:
//    claude mcp add goddess -- /path/to/GODDESS mcp
//

import Foundation
import System
import GoDFoundation
import MCP
import GODOps

// MARK: - Errors

enum MCPToolError: Error, CustomStringConvertible {
    case unknownTool(String)
    case missingArgument(String)
    case badInput(String)

    var description: String {
        switch self {
        case .unknownTool(let name): return "Unknown tool '\(name)'"
        case .missingArgument(let key): return "Missing required argument '\(key)'"
        case .badInput(let message): return message
        }
    }
}

// MARK: - Schema helper

/// Builds a minimal JSON-Schema object for a tool's inputs.
private func objectSchema(
    properties: [String: (type: String, description: String)],
    required: [String] = []
) -> Value {
    var props: [String: Value] = [:]
    for (name, spec) in properties {
        props[name] = .object([
            "type": .string(spec.type),
            "description": .string(spec.description),
        ])
    }
    return .object([
        "type": .string("object"),
        "properties": .object(props),
        "required": .array(required.map { .string($0) }),
    ])
}

// MARK: - Server instructions

/// Sent to the client in the initialize result (`InitializeResult.instructions`).
/// The MCP spec describes it as a hint the client may add to the model's system
/// prompt, so this is the one place an agent reads before it calls any tool.
let goddessInstructions: String = """
GODDESS edits GameCube and Wii ROMs by exporting a disc image into an editable \
project folder (setup_project), letting you change the exported files, and \
rebuilding a disc from them (run_config on the project's generated \
Build-Config.json). This server is GODDESS \(Version.semanticVersion); the same \
number is printed by `GODDESS --version`.

A project is bound to the GODDESS version that dumped it. Its engine folders, \
registries and manifests are written in that version's layout, and a different \
version cannot be assumed to read them correctly. setup_project records the \
version that wrote a project in its Engines/Version.txt; read that file before \
working on a project you did not create in this session.

To move a project to a different GODDESS version, never point the new version \
at the old project. Instead:
  1. With the version named in the project's Engines/Version.txt, run its \
Build-Config.json so every edit is captured in a rebuilt disc image.
  2. With the new version, call setup_project on that rebuilt disc image to \
dump a fresh project.
  3. Continue editing in the new project.

Do not mix engine folders, registries or configs between projects dumped by \
different GODDESS versions.
"""

// MARK: - Tool catalog

let goddessTools: [Tool] = [
    Tool(
        name: "setup_project",
        description: """
        Set up a GODDESS editing project. Call this FIRST when starting work on \
        a new ROM or save. Accepts a GameCube/Wii disc image (.iso/.gcm/.ciso; \
        .wia/.rvz are recognized but must be converted to raw ISO first) or a \
        memory-card save (.gci). Creates a '<name> project' (disc) or \
        '<name> save project' (save) folder next to the input, containing the \
        unpacked contents, exported engine definitions, and ready-to-run \
        dump/build config files.
        """,
        inputSchema: objectSchema(
            properties: ["path": (type: "string", description: "Absolute path to a disc image (.iso/.gcm/.ciso) or a .gci save")],
            required: ["path"]
        ),
        annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
    ),
    Tool(
        name: "unpack_fsys",
        description: """
        Unpack a standalone Genius Sonority .fsys archive into a '<name>_fsys/' \
        folder next to it, with LZSS-compressed entries decompressed. The game \
        variant (XD/Colosseum/PBR) is auto-detected. Use for a one-off archive; \
        for a whole ROM use setup_project instead.
        """,
        inputSchema: objectSchema(
            properties: ["path": (type: "string", description: "Absolute path to a .fsys archive")],
            required: ["path"]
        ),
        annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
    ),
    Tool(
        name: "run_config",
        description: """
        Run the enabled operations in a GODDESS JSON config file, in order. Use \
        this when a project already has a config (e.g. the generated \
        Dump-Config.json / Build-Config.json). Paths inside the config resolve \
        relative to the config file's own location.
        """,
        inputSchema: objectSchema(
            properties: ["path": (type: "string", description: "Absolute path to a GODDESS .json config file")],
            required: ["path"]
        ),
        annotations: .init(readOnlyHint: false, destructiveHint: true, openWorldHint: false)
    ),
    Tool(
        name: "list_operations",
        description: """
        List every GODDESS operation with its shape (flat or container) and a \
        one-line summary. Call describe_operation for one operation's fields \
        and example JSON before using run_operation.
        """,
        inputSchema: objectSchema(properties: [:]),
        annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
    ),
    Tool(
        name: "describe_operation",
        description: """
        Describe one GODDESS operation: its config fields, the nested \
        operations of a container operation, and example JSON, followed by the \
        JSON conventions every operation object follows. Served from the \
        GODDESS Configuration Reference embedded in the binary.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Operation name, as listed by list_operations"),
                    "enum": .array(OperationName.allCases.map { .string($0.rawValue) }),
                ]),
            ]),
            "required": .array([.string("name")]),
        ]),
        annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
    ),
    Tool(
        name: "run_operation",
        description: """
        Run a single GODDESS operation from an inline JSON object, without \
        authoring a config file. The 'operation' object uses the same shape as \
        one entry's 'operation' field in a config (e.g. \
        {"dolDisassembly": {"config": {...}}}). Optional 'settings' overrides \
        logging/keys. Operations: \(OperationName.allCases.map(\.rawValue).joined(separator: ", ")). \
        Call describe_operation for an operation's fields and an example. Use \
        for one-off steps; use run_config for a pipeline.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "operation": .object([
                    "type": .string("object"),
                    "description": .string("A single operation object, e.g. {\"gamecubeDump\": {\"config\": {...}}}"),
                ]),
                "settings": .object([
                    "type": .string("object"),
                    "description": .string("Optional GoddessSettings overrides (verbose, wiiCommonKeyFile)"),
                ]),
            ]),
            "required": .array([.string("operation")]),
        ]),
        annotations: .init(readOnlyHint: false, destructiveHint: true, openWorldHint: false)
    ),
]

// MARK: - Tool dispatch

/// Executes a tool call synchronously against `GODOps`. Runs on the request
/// task; the (potentially long) operation blocks it while `logger` streams
/// progress out of band.
private func handleToolCall(_ params: CallTool.Parameters, logger: GoDFoundation.Logger) throws -> String {
    let args = params.arguments ?? [:]

    func requiredFile(_ key: String = "path") throws -> File {
        guard let path = args[key]?.stringValue, !path.isEmpty else {
            throw MCPToolError.missingArgument(key)
        }
        return File(path)
    }

    switch params.name {
    case "setup_project":
        let file = try requiredFile()
        guard let ext = file.fileType?.lowercased() else {
            throw MCPToolError.badInput("Input path has no file extension")
        }
        switch ext {
        case "iso", "gcm", "ciso", "wia", "rvz":
            try GODOps.setupProject(discImage: file, toolVersion: Version.semanticVersion)
            return "Set up editing project from \(file.fileName)."
        case "gci":
            try GODOps.setupSaveProject(gci: file, toolVersion: Version.semanticVersion)
            return "Set up save-editing project from \(file.fileName)."
        default:
            throw MCPToolError.badInput("setup_project expects a disc image or .gci; got .\(ext)")
        }

    case "unpack_fsys":
        let file = try requiredFile()
        try GODOps.unpackFSYS(file)
        return "Unpacked \(file.fileName) into \(file.fileName.withoutExtensions)_fsys/."

    case "run_config":
        let file = try requiredFile()
        try GODOps.runConfig(at: file, logger: logger)
        return "Ran config \(file.fileName)."

    case "list_operations":
        return OperationCatalog.listing

    case "describe_operation":
        guard let name = args["name"]?.stringValue, !name.isEmpty else {
            throw MCPToolError.missingArgument("name")
        }
        guard let text = OperationCatalog.description(of: name) else {
            throw MCPToolError.badInput(
                "Unknown operation '\(name)'. Known operations: "
                + OperationName.allCases.map(\.rawValue).joined(separator: ", ")
            )
        }
        return text

    case "run_operation":
        guard let operationValue = args["operation"] else {
            throw MCPToolError.missingArgument("operation")
        }
        // Explicit `Data` types disambiguate JSONEncoder.encode from
        // GoDFoundation's Encodable convenience overloads.
        let operationData: Data = try JSONEncoder().encode(operationValue)
        let settingsData: Data? = try args["settings"].map { (value: Value) -> Data in
            try JSONEncoder().encode(value)
        }
        try GODOps.runOperation(json: operationData, settingsJSON: settingsData, logger: logger)
        return "Ran operation."

    default:
        throw MCPToolError.unknownTool(params.name)
    }
}

// MARK: - Server entry point

/// Runs the GODDESS MCP server on stdio until the client disconnects.
func runMCPServer() async {
    // stdio MCP requires stdout to carry ONLY JSON-RPC. Operations (and
    // PrintLogger, and some engine code) write to stdout with `print`, which
    // would corrupt the protocol stream. Hand the transport a dup of the real
    // stdout, then repoint fd 1 at stderr so every stray print lands on
    // stderr — visible as server logs, harmless to the protocol.
    let transportStdout = dup(STDOUT_FILENO)
    _ = dup2(STDERR_FILENO, STDOUT_FILENO)
    let transport = StdioTransport(output: FileDescriptor(rawValue: transportStdout))

    let server = Server(
        name: "goddess",
        version: Version.semanticVersion,
        instructions: goddessInstructions,
        capabilities: .init(logging: .init(), tools: .init(listChanged: false))
    )

    await server.withMethodHandler(ListTools.self) { _ in
        ListTools.Result(tools: goddessTools)
    }

    await server.withMethodHandler(CallTool.self) { params in
        let logger = MCPLogger(server: server)
        do {
            let message = try handleToolCall(params, logger: logger)
            return CallTool.Result(content: [.text(message)], isError: false)
        } catch {
            return CallTool.Result(content: [.text("Error: \(error)")], isError: true)
        }
    }

    do {
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    } catch {
        FileHandle.standardError.write(Data("goddess mcp: failed to start server: \(error)\n".utf8))
    }
}
