# GoD_Win — GODDESS on Windows

A Windows port of **GODDESS**, the CLI and MCP server from
[StarsMmd/GoD-Tool](https://github.com/StarsMmd/GoD-Tool). The port is the
upstream code base plus a small set of Windows fixes on top of upstream
`c39f010`. The Windows fixes are behind `#if os(Windows)` or are
Windows-neutral. A few further fixes change behaviour on every platform;
they are listed under [Fixes beyond the port](#fixes-beyond-the-port).

The upstream README follows [below](#god-tool--goddess) and still applies.
This section covers only what is different in this fork.

> No game data is included. Use GODDESS only with discs you have dumped
> yourself.

## Status

Verified on 2026-10-14 on Windows 11 with Swift 6.4.1, using the US discs of
Pokémon Colosseum and Pokémon XD.

| Area | Result |
|---|---|
| Build | `GODDESS.exe` builds with SwiftPM, both debug and release, including from a fresh clone of this repo with Git for Windows' default settings. |
| Tests | 2,385 cases: 2,253 pass, 132 skip, **0 fail**, also from a fresh clone. |
| Project setup + dump | Both games dump completely: 0 case collisions, CRLF-free text output, and per-archive file counts match the FSYS registries. |
| Rebuild | Both games rebuild. `DolphinTool verify` reports no problems, and the rebuilt discs boot in Dolphin (Colosseum to the title screen, XD to the health-and-safety screen). |
| Edit → rebuild | Edited title-screen textures in Colosseum. The rebuilt disc changed only the two archives that contain them, and the edits show in Dolphin. |
| MCP server | `GODDESS mcp` runs over stdio, and `setup_project`, `unpack_fsys` and `run_config` accept native `C:\...` paths. |
| Disc containers | ISO, RVZ (zstd), uncompressed WIA, CISO and GameCube NKit all decode to the original disc's SHA-256. `nkitBuild` output was also checked with Nanook's NKit 3, which expands it to the original disc. |
| Saves | Colosseum `.gci` saves (two samples) round-trip byte for byte, and a rebuilt save loads in-game. Datel `.sav` saves convert with `sav_to_gci.py` in Shadow Saga's tools. |
| Patches | `createPatch` and `applyPatch` reproduce an edited disc exactly as UPS, BPS and xdelta. Use xdelta for disc patches: about 1 MB, against about 1.46 GB for UPS/BPS, because a rebuild moves files. |
| Paths | Non-ASCII names, `%` and `&` in folder names (including the `.cmd` launchers), `subst` drives, forward slashes and relative CLI paths. |
| Wii / Battle Revolution | From a full RVZ dump, GODDESS decodes the disc to **the same SHA-1 as Dolphin** (Wii partitions re-encrypted and hash trees rebuilt exactly). From a scrubbed WBFS: decrypt, asset dump and DOL disassembly work, and repack, re-encrypt and fakesign gives a disc that verifies without data errors and boots in Dolphin. 29 of 30 fonts round-trip byte for byte. |
| Coverage | Of the 47 operations: 21 tested on real data on Windows, 24 by unit tests (2 of them, PBR strings, blocked on the US disc by an upstream bug), and 2 single-file font forms covered by their bulk forms. |

## Requirements

- Windows 10 or 11, x64.
- The Swift toolchain for Windows (tested with 6.4.1) and the Visual Studio
  components it needs. See [swift.org/install/windows](https://www.swift.org/install/windows/).
- **Long paths enabled.** DOL disassembly writes files named after mangled
  C++ symbols, so paths reach 270+ characters. `GODDESS.exe` embeds a
  `longPathAware` manifest, but Windows only honours it when the machine
  setting is on. Run this once in an elevated PowerShell:

  ```powershell
  New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
    -Name LongPathsEnabled -Value 1 -PropertyType DWORD -Force
  ```

  Without it, a write past 260 characters fails with an error that names
  `MAX_PATH` and this setting.

## Build

```powershell
cd "GoD Tool Package"
swift build -c release --product GODDESS   # .build\release\GODDESS.exe
swift test                                 # optional: the full suite
```

On Windows, SwiftPM rewrites `Package.resolved`. The vendored MCP SDK replaces
the upstream package, so the macOS-only pins drop out. That's expected; don't
commit the change.

## Use

```powershell
GODDESS.exe "C:\Games\Pokemon XD.iso"
```

This creates `Pokemon XD project\` next to the disc, with `Dump.cmd` and
`Build.cmd` launchers that run the dump and build configs. Every other
command in the upstream README works the same, with native Windows paths.

To register the MCP server with Claude Code:

```powershell
claude mcp add goddess -- "C:\path\to\GODDESS.exe" mcp
```

## What the port changes

| Commit | Change |
|---|---|
| `489d800` | Build GoDFoundation on Windows: no SIGPIPE, no CoreFoundation, and an `autoreleasepool` stub. |
| `e239ac7` | Build GODDESS and run its MCP server: a Windows stdio transport, stdout kept protocol-only, and a vendored swift-sdk 0.12.1 with a one-line `os(Windows)` fix (see `Vendored/swift-sdk/README.md`). |
| `a9e1840` | Write `.cmd` project launchers instead of POSIX `sh` scripts. |
| `547bd5c` | Skip `RunExecutable` tests cleanly when a utility is missing. |
| `75626e3`, `ada481e` | Accept native `C:\...` paths in MCP tool arguments (previously the server crashed on the first call), with tests. |
| `b1a6f5b`, `956cec9` | Embed the `longPathAware` manifest, with a test that it stays embedded. |
| `82c6678` | Decode native Windows paths in config JSON instead of crashing. |
| `0c9dbb8` | Name `MAX_PATH` and `LongPathsEnabled` when a long write fails. |
| `0b77301` | Make a fresh clone build and test cleanly: `.gitattributes` keeps the byte-exact fixtures as LF despite `core.autocrlf=true`, and the resource copies that `swift build` leaves in the package root are ignored. |

### Fixes beyond the port

These fix behaviour that is the same on every platform. They live in this
fork and haven't been sent upstream.

| Commit | Change |
|---|---|
| `652f163`, `88dae96` | **XD Pokémon cries convert to WAV.** The 388 cry headers and streams in `stm_se_nakigoe_archive` are paired at unpack by FSYS identifier, confirmed by each channel's ADPCM predictor/scale byte. On the US disc all 388 pair (9 by content alone, listed in a warning), giving 515/515 WAVs. Checked against an independent decode, and the archive still rebuilds byte for byte. |
| `dc3be4b` | `dumpAudios` says why it skips a header: `x.ish has no matching x.isd`. |
| `c13ffea` | Invalid folder paths in config JSON, and relative MCP path arguments, return an error instead of crashing the process. |
| `8df9261` | MCP tool errors are one clean `Error: …` line, without a source trace and with native Windows paths. |
| `c74bc09` | DOL disassembly manifests use sorted JSON keys, so two dumps of the same disc are identical. |
| `1e40b45` | Four tests left stale by intentional upstream changes are updated. One real codec gap (rebuilding a truncated MSG control code byte for byte) is kept as an explicit skip. |

## Known issues

These come from upstream and fail the same way on every platform.

- **Rebuilds are not byte-identical to the retail disc.** Textures are
  re-encoded from PNG, FSYS group IDs that aren't in the TOC reset to 0, and
  files are packed tightly instead of at retail offsets. Rebuilds are
  deterministic, though: the same project always gives the same disc.
- **WIA/RVZ decode only `none` and `zstd` compression.** RVZ works, but WIA
  made with Dolphin's usual LZMA setting is rejected. The upstream note below
  that says WIA/RVZ aren't decodable at all is out of date.
- **Colosseum audio (MusyX) has no WAV export.**
- **XD scripts have no decompile operation** (Colosseum's do).
- **PBR strings can't be dumped from the US disc.** String table 1 sits in
  untyped `mes_common.fsys` entries, which unpack writes as `.bin`, so
  `pbrStringsDump` finds only tables 2–4 and stops.
- **One PBR 3D font is misnamed.** `common_034.fnt` is really `.f3d`, so the
  bulk font dump skips it. The data is untouched.
- **Untested:** XD saves (the only sample found was malformed; see the verification notes).

## Staying in sync with upstream

This fork tracks [StarsMmd/GoD-Tool](https://github.com/StarsMmd/GoD-Tool) as
the `origin` remote; this repo is a second remote. Checked 2026-10-15:
upstream `main` is still `c39f010`, the commit the port is based on.

1. `git fetch origin`, then `git log --oneline HEAD..origin/main` to see what's
   new.
2. **Merge, don't rebase:** `git merge origin/main`. This repo's `main` is
   published, so its history must not be rewritten. Conflicts are most likely
   in this README and in `Package.swift` (the `#if os(Windows)` block at the
   bottom).
3. Check the merge before pushing:
   - `swift test` gives 0 failures;
   - a fresh clone of this repo builds and passes the same suite;
   - one disc dump of each game still works, with the release exe.
4. Push. The Windows workflow runs the suite again on GitHub.

Never commit `Package.resolved`: on Windows, SwiftPM rewrites it without the
macOS-only pins, and that change is local. To keep it out of `git status`, mark
it with `git update-index --skip-worktree "GoD Tool Package/Package.resolved"`.
If a merge then stops with "would be overwritten" for that file, run
`git update-index --no-skip-worktree "GoD Tool Package/Package.resolved"` and
`git checkout -- "GoD Tool Package/Package.resolved"`, merge, run
`swift build` (which rewrites it again), and set `--skip-worktree` again.

## License

GPL-3.0, the same as upstream (see `LICENSE`). `Vendored/swift-sdk` keeps its
own license (MIT / Apache-2.0, see its `LICENSE`). All credit for GODDESS goes
to StarsMmd and the upstream contributors.

---

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

### Windows

The same commands build `GODDESS.exe` with the Swift toolchain for Windows
(tested with Swift 6.4.1 on Windows 11).

A dump writes paths longer than Windows' 260-character `MAX_PATH`. The exe
embeds a `longPathAware` manifest, but Windows only honours it when long
paths are enabled for the machine. Set the DWORD `LongPathsEnabled` to `1`
under `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem` (needs admin
rights), or keep projects in a short folder such as `C:\gd`. A write that
fails past `MAX_PATH` says which of the two is missing.

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
