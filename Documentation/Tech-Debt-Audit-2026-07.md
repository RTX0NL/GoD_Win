# GoD-Tool Tech-Debt Audit — 2026-07-05

Full-project analysis for fragility, incorrect implementations, and work-in-progress.
Build state at audit time: **`swift build` passes** (13 warnings), **`swift test` passes** (672 tests, 1 skipped).
So nothing is *broken to compile* — the debt is behavioral/architectural. Paths are relative to `GoD Tool Package/`.

Findings are grouped by root-cause theme. Severity in brackets. `[H]`/`[M]`/`[L]`.

---

## Theme A — "Re-derive instead of preserve" (the dominant systemic issue)

The single biggest source of debt. Almost every format writer **recomputes** layout/offsets/order from a
model on rebuild instead of **replaying** what it parsed. This silently breaks the project's core
"bit-identical rebuild" guarantee the moment the original file has any padding, ordering, or encoding
choice the recompute logic doesn't reproduce. The uniform fix: *preserve the original bytes/layout for
unedited entities; only regenerate the parts that actually changed.*

| # | Loc | Sev | Problem | Fix |
|---|-----|-----|---------|-----|
| A1 | RELFile.swift:536-548 / 404 | H | Section bodies tight-packed on serialize; original `fileOffset`/inter-section alignment discarded (only `.empty` sections keep offset). XD/Colo align text sections → non-identical. | Capture each section's on-disc offset + trailing pad on parse; replay verbatim, recompute only when edited. |
| A2 | RELFile.swift:479-517, 686-701 | H | `splitData` only models `addr32` relocations as `.pointer` chunks; every non-ADDR32 edge, out-of-range, or out-of-order edge is silently dropped and permanently lost from the rebuilt reloc table. | Represent every data-section relocation in the model (carry raw edge list per section), not just ADDR32 slots. |
| A3 | PPCFormatter.swift:184-225 | H | `splitByFunction` emits only `[symbol, symbol+size)` ranges; instructions in un-symboled gaps (trailing nops, padding) land in no file → missing on reassembly → section shifts. | Tile the whole section: emit uncovered spans as anonymous filler chunks, or assert full coverage and fail loudly. |
| A4 | LZSSCompressor.swift:88-331 (via FSYSArchive.swift:263) | H | Generic greedy LZSS re-encode produces *a* valid stream, not the game's original bytes. Any compressed FSYS entry can't rebuild byte-identically. | Cache & re-emit original compressed blob for unmodified entries; only recompress changed payloads. |
| A5 | FSYSArchive.swift:112-127 vs 226 | H | Full-filename suffix stripping (`_col/_cam/_scd`) is lossy — stored name is the stripped form and written back on rebuild; original suffix bytes lost → whole string table diverges. | Preserve raw on-disk filename verbatim for rebuild; keep stripped "pretty" name display-only. |
| A6 | FSYSArchive.swift:219-227 vs 173 | H | Full-filename emission driven by archive-level `debugFlag`, ignoring the per-entry `includesFullFilename` recorded on parse (dead field). Mixed archives get wrong string set → all pointers shift. | Drive emission from each entry's `includesFullFilename`. |
| A7 | ATXFile.swift:221-319, 582-653 | H | FileFormat rebuild discards preserved `animation.offset`/`frameTable`/`trailing`, repacks contiguously & rebuilds frame table (writes 12 of 28 bytes). Contradicts `GXTexture.encodeATX` which *does* preserve them. | Route rebuild through offset-preserving `encodeATX`; preserve frameTable/trailing when frames unedited. |
| A8 | GXTexture.swift:700-727 | M | GTX encoder synthesizes a minimal 0x80 header, zeroing all other fields (mip count, wrap/filter, LOD…). Even a no-op decode→encode changes bytes. | Preserve original raw header; patch only fields that legitimately change. |
| A9 | MSGFile.swift:150 | M | Rebuild sorts entries by ID ("match legacy tool") — but must reproduce the *original ROM*, which may be unsorted; `sorted` also unstable for equal IDs. | Preserve original entry order captured on parse. |
| A10 | MSGFile.swift:157-184 | M | String pool re-laid sequentially/uniquely; can't represent shared (deduped) offsets or non-2-byte padding. | Capture each entry's raw `stringOffset` + exact pool layout for rebuild. |
| A11 | FsysTOC.swift:14,55,82-84 | M | `[String:Int]` keyed by filename loses order & can't hold duplicate names; rebuild re-sorts by groupID (nondeterministic on ties). | Store ordered `(filename, groupID)` array; rebuild in original order. |
| A12 | FsysTOC.swift:58-63, 66-75, 111-117 | M | Padding derived assuming exactly one null trailer + 0x20 align; `init(enumeration:)` uses a fixed global padding constant → can't match real file. | Persist measured trailing padding through the enum/registry path. |
| A13 | FSYSArchive.swift:260-272 | M | LZSS header's 4th word (`unknown`) never read on parse, written as 0 on rebuild. | Read & store per entry; write back. |
| A14 | RELFile.swift:550-572, 293 | M | File-layout order (header→sectable→bodies→import→reloc) and reloc-table offset (0x24) hard-coded/recomputed; original discarded. | Preserve original import/reloc table order & offsets; recompute only when edited. |
| A15 | RELFile.swift:710-735, 355-380 | M | `encodeChain` canonicalizes reloc chains (always leading SECTION, NOP only >0xFFFF, strict sort, single END) — diverges from linker's original encoding. | Validate vs real corpus; preserve raw chain command stream if divergent. |
| A16 | XDSaveSlot.swift:189-196, 232-342 | M | Repack recomputes every section offset via a heuristic alignment lattice instead of preserving loaded offsets (PKHeX-style). No-edit rebuild only byte-identical if real allocator used exactly that rule; unproven. | Reuse original absolute offset for unchanged sections; recompute only downstream of a resized section. Add no-override `repacked()==raw` test on a real slot. |
| A17 | PPCFormatter.swift:258-262 | M | `formatDataSection` symbolizes any data word equal to a known symbol address (not relocation-driven) → non-pointer constants rewritten. (Latent: live path uses confirmed pointers.) | Symbolize only relocation-backed words; deprecate this helper. |
| A18 | ISFFile.swift:483-490 | L | `byteOffsetToSample`/`sampleToByteOffset` integer divs aren't mutual inverses → loop points drift on round-trip. | Preserve raw `loopStartByte`/`loopEndByte`, re-emit verbatim. |

---

## Theme B — Crashes / hangs on edge cases (force-unwraps, ranges, bounds, traps)

Recoverable conditions that currently abort the whole process (or hang) instead of erroring cleanly.

| # | Loc | Sev | Problem | Fix |
|---|-----|-----|---------|-----|
| B1 | Colo/XD ScriptExpressionBuilder (Colo:203,222) | M | `argCount==0` → `1..<0` / `0..<(-1)` range trap kills the whole decompile pass. | `for _ in 0..<max(0, Int(argc)-1)`; guard `argc>0`. |
| B2 | XDSaveSlot.swift:281-283, 306-311 | M | `output[cursor+i]=byte` with no bounds check; an enlarged edited section shifts later ones past `output.count` → OOB trap on the feature's happy path. | Validate `cursor+newSize` fits `bodyEndOffset`; throw `.repackOverflow`. |
| B3 | NKitGapEncoding.swift:217-248 | M | `.repeatPrevious` before any `.nonJunk` (or `count:0` blocks) advances `emitted` by 0 → infinite loop (DoS on malformed data). | Require forward progress each iteration; throw on zero-progress; reject `repeatPrevious` with no prior nonJunk. |
| B4 | WiiCrypto.swift:18,20,37,41,44 | M | `read(...)!` force-unwraps on ticket/group data; truncated input crashes instead of parse error. Doc says "≥0x1D0 bytes" but title ID read needs ≥0x1E4. | Return optionals/throw on short read; fix doc length to 0x1E4. |
| B5 | ColoSaveCipher.swift:62,75 / XDSaveCipher.swift:64,80 | M | `precondition(count==slotSize)` traps the whole tool on a wrong-sized/corrupt slot. | Convert to thrown errors so ops can log & continue. |
| B6 | LZSSCompressor.swift:46-49,58-83 | M | `readChar()` unindexed; a flag demanding more bytes than remain → OOB crash on truncated stream. `expectedSize` never used as terminator. | Bounds-check every read; stop/validate at `expectedSize`. |
| B7 | StructData.swift:565,568,571,574,580 | M | Single-value encoder force-unwraps (`readPrimtive(...)!`, `readString(...)!`); malformed slice → crash (580 also crashes on the string over-read of C4). | `guard let`; skip key or throw with context. |
| B8 | StructData.swift:359 | M | `description` unconditionally `result.removeLast()`; all-padding/empty struct → trap on empty string. | Guard `if !result.isEmpty`. |
| B9 | StructDefiniton.swift:126,162 | L | `keypath.split(".")[0]` traps on empty keypath. | `guard let first = parts.first else { return nil }`. |
| B10 | MSGFile.swift:142 / ATXFile.swift:272 | L | `UInt16(count)` traps >65535; frame idx `UInt8(clamping:)` silently truncates to 255. | Validate against field max; throw descriptive encode error. |
| B11 | InMemoryFST.swift:147-160 | M | `moveFolder` is a shallow rename — descendant keys keep old prefix; `readFile` on moved children returns nil, tree left inconsistent. | Recursively rekey all descendants, or forbid non-empty folder moves. |

---

## Theme C — Correctness bugs affecting current use

| # | Loc | Sev | Problem | Fix |
|---|-----|-----|---------|-----|
| C1 | ColosseumSaveSlot.swift:20 | H | `slotSize=0x28000` (XD's) but whole Colo pipeline uses `0x1E000` → `guard raw.length==0x28000` **always throws**. Colo save dump is dead on arrival. | Set `0x1E000`; add real-slot round-trip test. |
| C2 | ColosseumSaveSlot.swift:25,52-55 | H | Colo magic hardcoded to XD's `[01,01,01]` with hard guard; unverified against a real save → likely rejects valid slots even after C1. | Verify real Colo plaintext magic; warn (don't throw) until confirmed. |
| C3 | StructData.swift:261-285 | H | `set(_:to:GoDData?)` deletes width chunks from index 0 → correct only big-endian; little-endian drops the significant bytes (sets 2-byte LE field to `[0,0]`). Grow branch prepends zeros (wrong side for LE). | Route all integer stores through `writeInteger(value:width:byteOrder:)` (the new correct path); delete hand-rolled block. |
| C4 | StructData.swift:193-200, 373-376 | H | int24/uint24: (a) `get` sign-detects at byte 0 / fills at 0 → only big-endian; (b) `encode` writes at `address:1` & reads Int32 → negative int24 encodes as large positive (no sign extend). read & encode disagree. | Explicit sign-extend on top bit in field byte order, shared read/encode/decode (reuse `writeInteger`). |
| C5 | StructData.swift:456, 580 (+ GoDReadable.swift:130-140) | H | Non-GS/UTF string fields: `readString` over-reads by 1 char for utf16/unicode/ascii → returns nil → field silently omitted from JSON (array path) or force-unwrap **crash** (single path). Only gs*/utf8 work end-to-end. | Read exact `count*charLen` bytes in the struct encoder; remove force-unwrap. |
| C6 | StructData.swift:576-578, 447-454 | H | Booleans collapse any non-zero to `true`, decode writes `0x01`; a flag byte holding `0x02/0xFF` round-trips to `0x01` → not bit-identical. | Store raw underlying byte, or add a strict raw-byte type; forbid bool where 1:1 required. |
| C7 | PPCRelocAnalyzer.swift:76-86,148-173 | M | `lis`/consumer mis-paired: (a) `getWrittenGPR` writer list omits `lwzx/lhzx/lmw/lswi/lwarx…` so a clobbered `lis` reg isn't invalidated; (b) `bl` doesn't clear volatile regs → `lis r3; bl foo; addi r3,…` mis-paired → wrong `@ha/@l` reloc. | Invalidate pending `lis` on *any* GPR-dest write (drive off operand model); clear volatiles on `bl/bla/bctrl/blrl`. |
| C8 | PPCDecoder.swift:240-287 / PPCEncoder.swift:105-108,794-838 | M | (a) Absolute conditional branch (AA=1) loses absoluteness — encoder always emits PC-relative. (b) `bsol/bnsl` decodable but missing from encoder dispatch → `encodingFailed`. | Preserve AA in decoded form; add missing `bsol/bnsl`/`*lrl` mnemonics. |
| C9 | PPCSectionAssembler.swift:119-134,177 | M | `.data4(.symbol)` writes absolute address — wrong for REL (needs section-relative + ADDR32 reloc). `.memory` narrowed via `Int16(clamping:)` silently corrupts offsets >±32767. | REL path: emit relocation not absolute word; replace clamping with checked conversion that throws. |
| C10 | ColoXDDumpOperation.swift:479 / ColoXDBuildOperation.swift:404-412 | M | Archive with header groupID 0 and no TOC name → registry stores `0`; build's `guard groupID != 0` silently drops it from rebuilt `GSfsys.toc`. | Preserve original TOC membership explicitly in registry, don't re-derive from sentinel 0. |
| C11 | FSYSArchive.swift:214-227,256-257 | M | Name-offset dicts keyed by `entry.filename` → duplicate filenames clobber → both entries' pointers resolve to last occurrence. Key is `filename` but string written is `metadata.name` (mismatch). | Track offsets per entry index. |
| C12 | GSWFile.swift:62-69 / GSWFile+FileFormat.swift / GSWParser.swift:70-93 | M | PNG names derived from marker `id`, not unique; same id in >1 texture → two refs map to one PNG (dump overwrites, build loads same image → corruption). | Name PNGs by unique sequential index; keep `id` as metadata. |
| C13 | ColoSaveDumpOperation.swift:103 vs ColoSaveCardFile.swift:90-106 | L | Latest-slot picked by `UInt32` counter vs `detectLatestIndex`'s signed `Int32` (PKHeX) → disagree near wraparound. | Compare as `Int32` consistently. |
| C14 | StructData.swift:379, 1064-1070 | M | uint64 (and full-range uint32) encoded as JSON numbers → `JSONSerialization` routes >2^53 through Double → silent rounding. | Encode as strings or add `lossless_integer` (mirror lossless-float). |
| C15 | StructDefiniton.swift:182-187 | M | `keyFor` lowercases + strips `_`/spaces → `maxHP`/`max_hp`/`maxhp` collide; `offset(for:)`/`property(for:)` return first match → silent aliasing. Undermines "add games via data" goal. | Match names exactly, or reject colliding normalized names at build time. |

---

## Theme D — Half-wired / WIP pipelines (look done, do nothing)

| # | Loc | Sev | Problem | Fix |
|---|-----|-----|---------|-----|
| D1 | WiiPartition.swift:383-404, 430 | H | Rebuild encrypts with all-zero H1/H2, writes original H3 verbatim, never calls `calculateH1/H2/H3Hash` or `fakesignTicket/TMD` — yet logs `completed(true)`. Produces cryptographically invalid, non-booting discs while reporting success. | Compute full H0→H1→H2→H3 chain + fakesign TMD; until then surface as "experimental", not success; gate behind flag. |
| D2 | TypedDataImporter.swift / DataSectionImporter.swift / LabelTable.swift + StructData.populate | H | **Two full JSON→binary importers exist**; the one wired to data sections silently drops array-of-enum/substruct/lossless elements (leaves zeros), and disagrees with `StructData` on padding keys & float encoding. Also: all three modules are never instantiated (dead) — both assembly ops bypass them. Editing typed JSON produces **no change**. | Collapse to a single schema-driven path (prefer `StructData.populate`); wire it into DOL/REL assembly (prefer JSON over `.bin` sidecar); delete the dead variant. |
| D3 | RelAssemblyOperation.swift:18-33 | M | REL rebuild reads only `.rel.json`; the `.s`/chunk/`sections.txt` artifacts it emits are decorative — asm edits silently discarded, user gets original back. | Wire `.s` back through `PPCSectionAssembler`, or stop emitting editable-looking sources and document JSON as sole edit surface. |
| D4 | FileFormatRegistry+Builtins.swift:24,28 / ISFFile.swift:103-105 | M | ISF/THP registered under single ext (`ish`/`thh`) but `init(binaries:)` needs ≥2 → single-binary `dump` always throws; no `isd`/`thd` handler. `isRegistered("ish")` lures callers into guaranteed failure. | Remove misleading single-ext registration, or add a paired-format concept (`.ish` implies reading `.isd` sibling). |
| D5 | ATXFile.swift:488-492 | L | Multi-sprite ATX throws on `count != 1` — only the surveyed poke_dance single-sprite subset supported. | Correctly gated WIP; extend to multi-sprite when needed. |
| D6 | RELFile.swift:598-604 | L | `fixSize`/`sectionAlign`/`bssAlign` echoed verbatim, never recomputed → stale & subtly broken after any size-changing edit. | Recompute on serialize when model diverges from parsed layout. |
| D7 | XDSaveSlot.swift:35-39 | L | Header doc describes `applySubBlock`/`assemble()` rebuild that doesn't exist (`assemble()` just `return raw`); real path is `repacked(sectionOverrides:)`. | Update stale comment to the real flow. |

---

## Theme E — Architecture / extensibility debt

| # | Loc | Sev | Problem | Fix |
|---|-----|-----|---------|-----|
| E1 | ColoXDDumpOperation.swift (765) / ColoXDBuildOperation.swift (711) | H | Fat operations: FSYS parse, THH/THD→THP pairing, texture routing, font dedup, FST assembly, pack/repack, TOC reconstruction all live in the operation layer — violates "operations are thin wrappers, domain logic in engines." Not reusable/testable. | Move `processFsys`/pack/repack/pairing/routing into `GeniusSonorityEngine`/`FSYSArchive`; operation becomes a config→engine→write loop. |
| E2 | ProjectSetupOperation.swift (81-84,116-199,355-550,614-832) + main.swift:59-109 | H | Per-game logic open-coded across a dozen `if isXD/isColo/isPBR` branches; Colo & XD config-builder blocks ~95% duplicated; engine names hardcoded as string literals (`"XD Engine"`) that can drift from `engine.name`. Adding a game = editing many scattered sites. | Introduce a per-game descriptor (extend `GSGame`) carrying IDs, engine factory, layout, symbol-map resolver, op templates; iterate the matched descriptor. Reference `engine.name`, not literals. |
| E3 | ColoXDDumpOperation.swift:52-87 (`unpackFSYS`) vs 471-582 (`processFsys`) | M | Two divergent FSYS-unpack paths produce incompatible registries (raw bytes vs decoded PNG/THP/dedup + metadata); mixing them breaks the build path. | Route both through the single engine-level unpack (per E1). |
| E4 | GamecubeBuildOperation.swift:37-43 | M | `fillISO` uses `FileSystem.shared` directly, bypassing the injected `fileSystem` → can't target `InMemoryFST`, untestable. `Gamecube.build` also omits the `logger:` param every sibling takes. | Use the injected `fileSystem`; add `logger`. |
| E5 | ColoXDDumpOperation.swift:659-683 / BuildOperation:655-681 | M | `DispatchQueue.concurrentPerform` shares one engine + `FileSystemTree`; "pure/thread-safe" is asserted, not verified. `InMemoryFST` dictionaries are **not** write-safe under concurrency. | Verify & document engine/FST thread-safety; give each worker its own decoder snapshot or guard shared state. |
| E6 | StructDefiniton.swift:283-285 vs Engine.swift:78-79 | M | Padding has two representations: code helper `padding(length:)` → `.array(.uint8)` (emitted verbosely as `padding_<i>`), map `void[N]` → real `.padding` case (skipped, no key). Same logical field serializes two ways. | Make `padding(length:)` produce the real `.padding` case; drop the `padding_<i>` machinery. |
| E7 | StructDefiniton.swift:35-58,129-154 / StructData.swift:515-523,733-741 | L | cStyle alignment/offset walk duplicated in 4 places; any future change must be mirrored or offsets silently diverge across read/write/encode/decode. | Extract one `layout() -> [(property, offset)]` consumed by all four. |
| E8 | StructData.swift:117-124 | L | String enum setter: unknown case silently skipped (`try?`); default branch writes raw UTF-8 text into non-enum integer fields. | Surface unknown enum cases as error; restrict string setter to character/string fields. |
| E9 | StructData writeArray:890-912 / TypedDataImporter:232 | M | Array length mismatch handled 4 inconsistent ways (zero-fill tail / truncate / throw / silent no-op) depending on field type. | One policy (recommend: reject count mismatch with clear error for tables). |

---

## Theme F — Silent failures / error handling

| # | Loc | Sev | Problem | Fix |
|---|-----|-----|---------|-----|
| F1 | main.swift:116-118, 26-31 | H | Whole dispatch wrapped in `do{…}catch{print}` → any op aborts the rest of the batch **and process still exits 0**; wrappers/CI/randomizer can't detect failure. `guard arguments.count>0` is dead (argv[0] always present). | `catch { print; exit(EXIT_FAILURE) }`; guard `>1`; isolate per-op errors so one failure doesn't drop the batch. |
| F2 | main.swift:49-51 / Toggle.swift:16-20 | M | Malformed `Settings.json` silently reverts to defaults (drops `wiiCommonKeyFile` → confusing later error). `Toggle.init` never throws — any unrecognized `enabled` value → `.no`, silently disabling an op. | Distinguish "no file" from "file failed to decode" (throw/warn); have `Toggle` throw or warn on unrecognized values. |
| F3 | ColoXDDumpOperation.swift:96-100,305-340,376-429,527-562 | L | Font/ATX/MSG/GSW/audio/THP/texture parse failures `log(.warning)` + `continue` → a run that fails half the assets still "succeeds" (exit 0), no skip count. | Track & report skipped-file count per batch; add strict mode escalating skips to errors for 1:1 validation. |
| F4 | FileFormatRegistry.swift:161-178 | L | `collectNested` silently skips unreadable files; format then throws a confusing `missingOutput` downstream. | Distinguish "listed but unreadable" from "absent"; propagate read error. |
| F5 | GXTexture.swift:465-483,519,528 | L | Indexed GTX with `palOff==0` → empty palette, every index → `(0,0,0,0)` → silently all-black texture, no error. | Treat indexed-without-palette as decode failure (return nil). |
| F6 | GXTexture.swift:700-727 / FSYSArchive.swift:252-253 | L | GTX bytes 0x04/0x05 written on unverified assumptions (never read back). FSYS `fileTypeIndex = raw/2` is an undocumented invariant; unknown type silently → index 0. | Verify meaning of those bytes; document the `/2` parity coupling; fail loudly on unresolved type. |
| F7 | RELFile.swift:605,614,639 + parse readSafely | L | Layout invariants checked with `assert` (stripped in release) → malformed REL ships silently. `readSafely` returns 0 past EOF → truncated file parses into plausible-but-wrong structure. | Use `guard…else{throw}` for invariants; validate declared offsets/sizes vs `binary.length`. |

---

## Theme G — Build & repo hygiene (found directly)

| # | Loc | Sev | Problem | Fix |
|---|-----|-----|---------|-----|
| G1 | Colosseum/Constants/Data.swift:72,90 (+ XD/Constants/Data.swift:171,190) | M | `common_rel_symbols.json` deleted this session; loader now reads per-region `common_rel_symbols_<suffix>.json` (Colo has _us/_eu/_jp), but the `commonRelSymbolMap` default still points to the deleted non-region path → stale/dead default. | Remove the stale default, or point it at the region-resolved path. (XD still has the single file, so XD's is valid but should align with the region scheme.) |
| G2 | Package.swift:110-307 | L | Several engine targets declare `resources:[.process("Resources")]` for folders that don't exist (e.g. Colosseum after the delete) → 8× "Invalid Resource 'Resources'" warnings; 2 unhandled files; `GoDCLI`/`Orre` stub targets have misplaced sources. | Drop `resources:` from targets with no Resources dir; declare/exclude the 2 unhandled files; fix or remove stub targets. |
| G3 | Tests (Colosseum/XD suites) | M | Many format round-trip tests `XCTSkip` when a real ROM asset isn't present — the byte-identical guarantees (the core requirement) aren't exercised hermetically; a clean checkout skips them silently. | Commit small synthetic/redacted fixtures so round-trip coverage runs without copyrighted assets. |
| G4 | ProjectSetupOperation.swift:875-885 / ProjectSetupGCI.swift:265-275 | L | Generated `.sh` escapes only spaces; ISO-derived paths with `(USA)`, `&`, `'` break the launcher. | Single-quote the whole path (escape embedded `'`). |
| G5 | ProjectSetupOperation.swift:291-303 | L | Wii/PBR DOL disassembly hardcodes `symbolMapPath: nil` even for PBR (a GS game that could have a map like XD/Colo). | Extend `dolSymbolMapFile` to the Wii branch or leave an explicit TODO. |
| G6 | NKitGCConverter.swift:91 | L | ~645 MB NKit body built by per-byte `output.append` → very slow/memory-churny for the large-file case it targets. | Bulk-append the full `Data`/`[UInt8]`. |
| G7 | WiiDecryptedPartitionView.swift:73-76 | L | Cache eviction is clear-all at 64 entries (not LRU) → sequential FST extraction re-decrypts repeatedly. | Single-entry LRU eviction. |
| G8 | main.swift:16-22 | L | Commented-out `RunModes.development` block hardcodes `/Users/stars/…` paths — stale dev cruft in the entry point. | Remove or move to gitignored local/env. |

---

## Recommended sequencing

1. **Correctness-now bugs that block current features** — C1/C2 (Colo save dump is dead on arrival), C3/C4/C5/C6 (struct read/write on little-endian, int24, non-GS strings, booleans), D1 (Wii rebuild reports false success).
2. **Robustness pass** — Theme B (convert all traps/force-unwraps/ranges/infinite-loops in parse/decode paths to thrown errors) + F1 (exit non-zero on failure). Cheap, high leverage, stops one bad file from killing a batch.
3. **The byte-identical foundation (Theme A)** — adopt one rule everywhere: *store the parsed layout and replay it; regenerate only edited entities.* Start with RELFile (A1/A2/A14/A15) and FSYS (A4/A5/A6), since those block the two in-progress milestones (REL disasm/reasm, ColoXD FSYS 1:1).
4. **Consolidate the two importers (D2)** — pick `StructData.populate`, wire it into DOL/REL assembly, delete `TypedDataImporter`; this also resolves C14, E6, E9.
5. **Architecture (Theme E)** — move FSYS domain logic into the engine (E1/E3), introduce the per-game descriptor (E2). Do after 1-3 so the refactor targets correct behavior.
6. **Hygiene (Theme G)** — quick wins any time.
