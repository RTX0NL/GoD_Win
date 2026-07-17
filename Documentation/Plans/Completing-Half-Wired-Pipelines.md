# Plan: Completing the Half-Wired Pipelines

**Status:** proposed.
**Motivation:** three subsystems currently *look* implemented but silently do
nothing (or always fail), so a user editing the exported artifacts sees no
effect on rebuild. Each needs either wiring-in or honest removal. These are
correctness/UX traps, not round-trip concerns.

There are three independent tracks. They can be done in any order; Track A is
the highest value.

---

## Track A — Consolidate the two JSON→binary importers, and wire the survivor in

**Problem.** Two full JSON→`StructData` implementations exist:
- `StructData.populate` / `writeValue` (`Structs/Data/StructData.swift`) — the more complete one; handles enums, sub-structs, lossless floats, strings.
- `Disassembler/Import/TypedDataImporter.swift` + `DataSectionImporter.swift` + `Layout/LabelTable.swift` — **never instantiated anywhere** (dead code), and its `encodeArrayElement` silently drops arrays of enum/substruct/lossless elements (leaves zeros).

And neither is actually used by the assembly ops:
- `DolAssembly` rehydrates `.struct`/`.table` chunks only from the `.bin` sidecar via `renderBinaryChunkAsAssembly` (`DolAssemblyOperation.swift:262-277`) — the typed JSON is ignored; deleting the `.bin` drops the chunk.
- `RelAssembly` reads only `<name>.rel.json`.

So editing a typed struct/table JSON produces **no change** in either pipeline.

**Plan.**
1. **Pick `StructData.populate` as canonical.** First close its known gaps (from the struct audit): array-of-enum, array-of-substruct, and array-of-lossless element coverage; unify the padding-key convention; unify float encoding. Add round-trip tests for each element kind.
2. **Establish whether `LabelTable` provides anything `populate` lacks** (symbol/label resolution for `.data4(.symbol)`-style fields). If yes, fold that capability into the canonical path as an injected label resolver; if no, delete it.
3. **Wire the canonical importer into `DolAssembly`:** for `.struct`/`.table` chunks, prefer the typed JSON over the `.bin` sidecar when both exist; fall back to `.bin` only when no JSON is present. This makes typed edits effective and keeps binary-only chunks working.
4. **Do the same for `RelAssembly`** once its section pipeline is wired (Track B).
5. **Delete `TypedDataImporter` + `DataSectionImporter`** (and `LabelTable` if unused) so there is no second, incomplete implementation to drift.

**Also resolves:** struct-audit findings #5, #9, #11 and audit C14/E6/E9.
**Test:** dump a DOL data section with a struct/table chunk, edit a field in the JSON, rebuild, assert the bytes changed accordingly; assert a binary-only chunk still round-trips.

---

## Track B — Make REL edits actually take effect

**Problem.** `RelAssembly` (`RelAssemblyOperation.swift:18-33`) reconstructs the
binary solely from `<name>.rel.json`. The `.s` text sections, per-chunk
`.bin`/`.json`, and `sections.txt` that `RelDisassembly` emits are decorative —
edits to them are silently discarded. A user who edits a REL function in
assembly and rebuilds gets the unmodified original back, no warning.

**Plan (staged).**
1. **Stop lying first (small, ship immediately):** either don't emit the
   editable-looking `.s`/chunk artifacts, or emit a top-of-file banner in each
   (`# NOT re-assembled on build — JSON is authoritative`) and document that JSON
   is currently the sole edit surface. Removes the silent-no-op trap.
2. **Then reach DOL parity:** parse the `.s` text back through
   `PPCSectionAssembler` and reconcile the assembled bytes into the section model
   before serialization, so REL assembly edits round-trip the same way DOL's do.
   This depends on Track A for the typed data chunks.
3. **Recompute the layout fields that an edit invalidates** (`fixSize`,
   `sectionAlign`, `bssAlign`, section sizes/offsets, reloc/import tables) — since
   the project recomputes from scratch by design, ensure edited sizes propagate
   rather than echoing stale parsed values (RELFile serialize). Note: byte-identical
   output is explicitly *not* a goal; the requirement is a correct, loadable module.

**Also resolves:** PPC-audit findings #4, #5 (REL side), #15.
**Test:** disassemble a REL, edit an instruction in a `.s` section, rebuild,
disassemble again, assert the instruction changed and the module still parses.

---

## Track C — Paired file formats (ISF/THP) in the registry

**Problem.** ISF is registered under `"ish"` and THP under `"thh"`
(`FileFormatRegistry+Builtins.swift:24,28`), but `ISFFile.init(binaries:)`
requires ≥2 binaries (the `.ish` header + `.isd` data; `.thh` + `.thd`). The
single-binary convenience path (`FileFormatRegistry.swift:63-77`) always throws,
and there's no `"isd"`/`"thd"` handler. `isRegistered("ish")` returns `true`,
luring generic callers into a guaranteed failure.

**Plan (pick one).**
- **Minimal:** remove the misleading single-extension registrations until paired
  handling exists, so `isRegistered` tells the truth.
- **Full:** add a *paired-format* concept to `FileFormatRegistry`: a format
  declares a set of sibling extensions (`.ish`↔`.isd`, `.thh`↔`.thd`); the
  extension-routing layer, when it sees one sibling, gathers the other from the
  same folder and passes both binaries to `init(binaries:)`. Dump emits both
  siblings; build consumes both.

**Recommendation:** ship Minimal now (one-line honesty fix), schedule Full when
ISF/THP round-tripping is actually needed (note ISF/DSP-ADPCM is inherently lossy
and can never be byte-identical — that's fine under the correctness-first goal,
but it should be excluded from any strict-equality assertions).

**Also resolves:** file-format-audit finding #13.

---

## Suggested order
1. Track C **Minimal** (trivial, removes a false-positive today).
2. Track A (highest value; unblocks typed edits for DOL immediately).
3. Track B (depends on A for typed chunks; stage 1 can ship before A).
4. Track C **Full** and Track B stage 2 when the corresponding formats are prioritized.
