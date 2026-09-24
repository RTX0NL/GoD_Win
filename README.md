# GoD-Tool — GODDESS

**GODDESS** is a command-line tool for unpacking, editing, and rebuilding
GameCube and Wii ROM files. Instead of patching bytes inside a disc image, it
exports a ROM into a structured, human-readable project filesystem — binary
formats become JSON, PNG, WAV, and PowerPC assembly — and rebuilds a working
image from those sources.

Primary targets are **Pokémon XD: Gale of Darkness**, **Pokémon Colosseum**,
and **Pokémon Battle Revolution**, but the architecture is deliberately
general: game-specific knowledge lives in data-driven *engine* definitions
(JSON struct/enum layouts), not hardcoded logic, so mods and rom hacks can still be supported by the tool as long as the variables are updated to match.

See [Credits & References](Documentation/Credits%20%26%20References.md) for
the reference implementations and specifications this project builds on.

## How to use

GODDESS is driven by the type of file you pass it:

```bash
GODDESS path/to/game.iso        # set up an editing project from a disc image
GODDESS path/to/my-archive.fsys # unpack a standalone FSYS archive
GODDESS path/to/my-config.json  # run the operations specified in a config file
GODDESS path/to/save.gci        # set up a save-editing project
```

Multiple arguments are processed in order.

### 1. Set up a project from a disc image

```bash
GODDESS "Pokemon XD.iso"
```

Raw `.iso`/`.gcm` and `.ciso` are fully supported (CISO is converted to raw
ISO automatically). NKit GameCube images are partially supported
(trailing-truncated only); NKit Wii and `.wia`/`.rvz` are recognised but not
yet decodable — convert those to a raw `.iso` first. The game is auto-detected
and a project folder is created next to the input:

```
Pokemon XD project/
├── Build/          # the unpacked disc + rebuilt output
├── Config/         # generated config files (see below)
├── Engines/        # exported engine definitions (constants, parameters, specifications)
│   └── Version.txt # the GODDESS version that wrote the project
├── Scripts/        # Dump.sh / Build.sh one-line launchers
└── Settings/       # Settings.json (logging, Wii common key path)
```

> Wii discs additionally need the Wii common key, referenced from
> `Settings/Settings.json` (`wiiCommonKeyFile`). The key is not distributed
> with this project.

### 2. Unpack a standalone FSYS archive

```bash
GODDESS common.fsys
```

Extracts every entry (LZSS-compressed entries are decompressed) into a
`common_fsys/` folder next to the file.

### 3. Run a config file

```bash
GODDESS "Pokemon XD project/Config/Dump-Config.json"
```

A config file is an ordered list of operations. Each operation is
individually enabled/disabled, so one file can describe a whole pipeline and
you toggle just the steps you need:

```json
{
  "name": "Dump ISO",
  "rootFolder": "..",
  "settingsFile": "./Settings/Settings.json",
  "operations": [
    {
      "enabled": "YES",
      "operation": { "gamecubeDump": { "config": { "operations": [ … ] } } }
    },
    {
      "enabled": "NO",
      "operation": { "dolDisassembly": { "config": { … } } }
    }
  ]
}
```

- `rootFolder` is resolved relative to the config file itself; every path
  inside the operations resolves from there.
- `enabled` is `"YES"` or `"NO"` — disabled operations stay in the file as
  ready-to-enable templates.
- Operations run in the listed order.

Project setup generates default configs (`Config/Dump-Config.json`,
`Config/Build-Config.json`, and the save variants) with every relevant
operation already wired to the project's folder layout — common steps
enabled, optional ones present but disabled. **Copy these as the starting
point for your own configs** rather than writing one from scratch; they
double as canonical examples of the path conventions.

### 4. Set up a save-editing project from a GCI save

```bash
GODDESS "01-GXXE-PokemonXD.gci"
```

The game is detected from the GCI's gamecode (`GXX*` → Pokémon XD, `GC6*` →
Colosseum; other games are rejected) and a `"<name> save project"` folder is
created next to the input, mirroring the disc-image layout:

```
01-GXXE-PokemonXD save project/
├── Build/Save/     # mirror of the original .gci; rebuilds land here too
├── Config/         # Save-Dump-Config.json / Save-Build-Config.json
├── Engines/        # exported engine definitions
│   └── Version.txt # the GODDESS version that wrote the project
├── Scripts/        # Save-Dump.sh / Save-Build.sh launchers
└── Settings/       # Settings.json
```

The generated dump config splits the save envelope into a header manifest +
region binaries (`banner.bin`, `header0.bin`, `header1.bin`, `slot-a.bin`,
`slot-b.bin`) and then runs the game-specific per-slot dump. The build config
reassembles the slots and writes `<name>_rebuilt.gci` — the mirrored original
is left untouched so the two can be diffed to validate the rebuild.

### Available operations

These operations are fully implemented and round-trip end to end:

| Group | Operations | Purpose |
|---|---|---|
| GameCube disc | `gamecubeDump`, `gamecubeBuild` | Unpack / rebuild a GameCube ISO (boot, FST, DOL, apploader, filesystem). |
| Wii disc | `wiiDump`, `wiiBuild` | Decrypt / re-encrypt Wii partitions (AES-128-CBC, hash tree). Rebuild is functionally correct but fakesigned — valid for Dolphin/homebrew loaders, not retail-signed. |
| CISO images | `cisoDump`, `cisoBuild` | Compressed disc image ↔ raw ISO. |
| Colo/XD assets | `coloXDDump`, `coloXDBuild` | FSYS archives ↔ organized asset folders: fonts, flash menus, messages (Colo/XD), textures, audio. Re-packs (re-compresses) on build. |
| DOL executable | `dolDisassembly`, `dolAssembly` | `main.dol` ↔ PowerPC assembly. Instruction round-trip is byte-exact. |
| GCI saves | `gciDump`, `gciBuild` | Memory-card save envelope ↔ header manifest + region binaries (byte-identical). |

Every operation's JSON fields are documented in the
[GODDESS Configuration Reference](Documentation/GODDESS%20Configuration%20Reference.md)
(which catalogs the full config surface, including operations still in progress
below).

### Partial support

These run but don't yet round-trip fully — dumping works, rebuilding is
incomplete:

- **Save editing** (`xdSaveDump`/`xdSaveBuild`, `coloSaveDump`/`coloSaveBuild`)
  — decryption and per-slot dumps are solid. On rebuild, XD applies edits to
  the four struct-backed sections (Config, Trainer, PC box, Daycare) via their
  JSON sidecars but ignores `.bin` sub-block edits; Colosseum currently
  re-encrypts the raw slot verbatim, so only whole-slot edits survive.
- **Animated textures (ATX)** within `coloXDDump`/`coloXDBuild` — single-sprite
  frames round-trip; frames with multiple sprites are skipped on dump and
  rejected on build.

### Not yet operational

Recognised by the config/dispatch layer but not functional — listed for
transparency:

- **REL disassembly & reassembly** (`relDisassembly`/`relAssembly`,
  `commonRelDump`/`commonRelBuild`, `mapRelDump`/`mapRelsDump`/`mapRelBuild`/`mapRelsBuild`)
  — the underlying `RELFile` parse/serialize core is complete and tested, but
  the operations are gated off pending the disassembly↔reassembly workflow.
- **Battle Revolution** (`pbrDump`) — stub only; no PBR asset extraction or
  rebuild yet.
- **NKit Wii / WIA / RVZ disc images** — detected but not decodable (no
  bzip2/lzma/zstd decompressor); convert to raw ISO first.

### 5. Run as an MCP server

GODDESS can expose its operations to any [Model Context Protocol](https://modelcontextprotocol.io)
client (Claude Code, Claude Desktop, etc.) over stdio:

```bash
GODDESS mcp        # starts a stdio MCP server; blocks until the client disconnects
```

Register it with a client — for example, Claude Code:

```bash
claude mcp add goddess -- /path/to/GODDESS mcp
```

The server drives the exact same code paths as the CLI and exposes six tools:

| Tool | Purpose |
|---|---|
| `setup_project` | Create an editing project from a disc image or `.gci` (mirrors mode 1 / 4). |
| `unpack_fsys` | Unpack a standalone `.fsys` archive (mirrors mode 2). |
| `run_config` | Run the enabled operations in a config file (mirrors mode 3). |
| `run_operation` | Run a single operation from an inline JSON object, no config file needed. |
| `list_operations` | Every operation with its shape and a one-line summary. |
| `describe_operation` | One operation's fields, nested operations and example JSON, on demand. |

Long operations stream progress to the client via MCP log notifications. The
[Configuration Reference](Documentation/GODDESS%20Configuration%20Reference.md)
is embedded in the binary, so `describe_operation` serves the same text a
reader of that document sees; `run_operation`'s description names every
operation so a client can discover them without reading anything else.

## How to build

Requires Swift 6.0+ on macOS 13+ (Swift Package Manager only — no Xcode
project needed). The package builds in the Swift 5 language mode; the MCP
server is the only component that pulls in an external dependency (the
[MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)).

```bash
cd "GoD Tool Package"
swift build --product GODDESS        # debug build
swift build -c release --product GODDESS
```

The binary lands in `.build/debug/GODDESS` (or `.build/release/GODDESS`).
During development you can also run it directly:

```bash
swift run GODDESS path/to/game.iso
```

## How to develop

The package lives in `GoD Tool Package/`:

- `Sources/Products/GODOps/` (path `Sources/Products/GODSDK/`) — the shared
  operations library: config types, one thin wrapper per operation, and the
  public `GODOps` dispatch facade both front-ends call.
- `Sources/Products/GODDESS/` — the thin `GODDESS` executable: argument
  parsing (`main.swift`) and the stdio MCP server (`MCP/`), both driving
  `GODOps`.
- `Sources/Shared/Core/Engines/` — the engine modules (Dolphin, GameCube,
  Wii, GeniusSonority, Colosseum, XD, PBR, Pokemon). All domain logic —
  parsing, crypto, compression, serialization — lives here.
- `Sources/Shared/Dependencies/` — foundation layers: `GoDFoundation`
  (data/files/logging), `Structs` (binary↔JSON schema mapping), `GTX`
  (texture codec), `Disassembler`, `FixtureCatalog`, `TestSupport`.

Key conventions (see `CLAUDE.md` for the full set):

- **Operations are thin wrappers** — GODSDK operation files only map config
  values to engine function calls. New behavior belongs in an engine module.
- **Data-driven engines** — game structure layouts are JSON definitions, not
  Swift; new games should be addable without code changes.
- **Cross-platform by default** — no Apple-only frameworks in the CLI path;
  algorithms (AES, SHA-1, LZSS) are pure Swift.

### Running the unit test suite

```bash
cd "GoD Tool Package"
swift test                                  # run the whole suite
swift test --filter ColosseumTests          # one test target
swift test --filter FSYSGoldenTests         # one test class
```

The suite is fully self-contained: every test runs on a clean checkout with no
ROMs, environment variables, or setup. Tests that exercise real game files
(absolute paths on the author's machine) skip automatically when those files
are absent — they never fail in CI.

### Golden fixtures

Format encode/decode tests (`*GoldenTests`) assert each direction against
checked-in sample files ("golden fixtures") rather than round-tripping:

- **decode** — parsing the golden binary must produce the golden decoded form
  (a failure blames the reader)
- **encode** — serializing the golden decoded form must reproduce the golden
  binary (a failure blames the writer)

Fixtures live in a `Fixtures/` folder next to the tests that use them, e.g.
`Tests/Shared Tests/Engine Tests/Colosseum Tests/Fixtures/`. They are read
from the source tree directly (not SPM resources) and are part of the regular
suite — `swift test` covers them.

There are two kinds:

1. **Generated** — defined by deterministic model builders in
   `Sources/Shared/Dependencies/FixtureCatalog/` (one `<Format>Fixtures` enum
   per format). Each builder constructs a small sample that exercises as many
   of the format's code paths as possible; the current writer's output is
   frozen as the golden file.
2. **Hand-authored** — written by hand as independent ground truth (e.g.
   `msg_minimal.msg`, `typemap_sample.json`). These are never overwritten by
   the generator.

### Regenerating fixtures

```bash
cd "GoD Tool Package"
swift run FixtureGen            # rewrite generated fixtures that changed
swift run FixtureGen --check    # verify committed fixtures match the catalog
                                # (exits 1 on drift — suitable as a CI step)
```

Regenerate only when a format's serialization is *intentionally* changed —
review the resulting fixture diff before committing, since it redefines the
expected output for that format. If `swift test` fails against the current
fixtures, that is the tests doing their job (a reader/writer regression), not
a signal to regenerate.

### Adding tests for a new format

1. Add a `<Format>Fixtures` enum to `FixtureCatalog` with a deterministic
   `model()` and `files()`, and register it in `FixtureCatalog.allFixtures()`
   — or hand-author the fixture files if the format is simple enough to write
   byte-by-byte (preferred where practical, since that ground truth is
   independent of the tool's own writer).
2. Run `swift run FixtureGen` to materialise the files.
3. Add a `<Format>GoldenTests` class next to the module's other tests with one
   decode and one encode test, using the helpers in `TestSupport`
   (`Fixtures.data/fileData/artifacts`, `assertDecodes`, `assertEncodes`,
   `assertBytesEqual`). Lossy formats pass a tolerance instead of asserting
   byte equality (see `ISFGoldenTests`).
