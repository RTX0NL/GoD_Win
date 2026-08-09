# U8 / NARC — Nintendo Archives

Two of Nintendo's own container formats, both handled by the **Nintendo
engine** (`Sources/Shared/Core/Engines/Nintendo`). Neither is
game-specific: an archive's layout is the same whether it came from Battle
Revolution or an unrelated Wii title, so the engine carries no game
knowledge and the per-game routing of what comes *out* of an archive stays
in the game engines.

Battle Revolution ships both — 24 `.arc` and 6 `.narc` in the PAL disc — and
all 30 repack byte-identically (`NintendoArchiveRealCorpusTests`).

## Byte order is read off the magic

Nintendo's tooling writes a format's four-character code as a machine word,
so porting a format to a platform of the opposite endianness reverses the
spelling of its own magic. That reversal is the discriminator, not a
corruption check, and every scalar in the file follows it.

| Format | Native to | Forward magic | Reversed magic |
|---|---|---|---|
| U8 | GameCube (big-endian) | `55 AA 38 2D` → **big** | `2D 38 AA 55` → **little** |
| NARC | DS (little-endian) | `NARC` → **little** | `CRAN` → **big** |

The two run opposite ways round, which is the trap: `NARC` forwards means
*little*-endian, and PBR's big-endian port is the one that reads `CRAN`.
NARC's section codes flip with it, so `BTAF`/`BTNF`/`GMIF` on the DS read
`FATB`/`FNTB`/`FIMG` in a big-endian file.

`NintendoArchiveSignature.detect` answers both questions from those four
bytes. Everything downstream — `ArchiveReader`, `ArchiveWriter` — takes the
byte order as a parameter, so neither format has a "native" code path that
the other is bolted onto.

## U8 (`.arc`)

A flat preorder table of nodes plus a string table, then the file data.
Header:

| Offset | Size | Field |
|--------|------|-------|
| 0x00 | 4 | Magic |
| 0x04 | 4 | Offset of the root node (0x20 in everything seen) |
| 0x08 | 4 | Size of the node table + string table |
| 0x0C | 4 | Offset of the file data |
| 0x10 | 16 | Reserved |

A node is 12 bytes: a packed word of `u8 type` + `u24 name offset`, then two
words whose meaning depends on the type.

| Type | Second word | Third word |
|---|---|---|
| 0 — file | data offset (absolute) | byte length |
| 1 — directory | index of its parent | index one past its last descendant |

Node 0 is the root: an unnamed directory whose "one past last" is the node
count, which is how the count is discovered in the first place. Because the
table is preorder and each directory records where its subtree ends, the
tree *is* a flat ordered list — which is how `U8Archive` models it, so the
ordering survives a round trip untouched.

**Everything the writer needs is derivable.** Measured across all 24 PBR
archives:

- The data region begins at the first `dataAlignment` boundary after the
  tables: `align32(rootOffset + headerSize)`.
- Every file starts on that same boundary; gaps are zero.
- Names are written in node order with **no de-duplication** — the string
  table's length is exactly the sum of each name plus its terminator.
- The string table opens with the root's own empty name, i.e. a lone NUL.

Only the alignment and pad byte are engine data (`Data.U8`); the rest falls
out of the entry list.

## NARC (`.narc`)

Header, then three sections laid end to end, each `magic (4) + size (4)`
followed by its body.

| Offset | Size | Field |
|--------|------|-------|
| 0x00 | 4 | Magic |
| 0x04 | 2 | Byte-order mark |
| 0x06 | 2 | Version (`0x0100`) |
| 0x08 | 4 | Total file size |
| 0x0C | 2 | Header length (0x10) |
| 0x0E | 2 | Section count (3) |

| Section | Body |
|---|---|
| FAT | `u16` file count, `u16` reserved, then a start/end offset pair per file, both relative to the start of the image body |
| FNT | The name table, or a degenerate root-only entry when files are addressed by index |
| IMG | The file data |

Sections are located by magic rather than assumed to be in order. The
header's declared total size accounts for every byte, which is the
cheapest integrity check available and what the corpus test leans on.

### Index is identity

Most real NARCs carry no names. PBR's three are all like this, and there
the entry's index *is* its meaning: `waza_seq_rev.narc` holds 501 entries
addressed by move ID, of which 480 are the same 4-byte stub. So entry order
is the one thing a round trip must never disturb, and the unpack names
nameless entries `0000.bin`, `0001.bin`, … — zero-padded so a directory
listing stays in index order.

### The one un-derived field

A nameless FNT body is 8 bytes, and its two 16-bit fields appear in the
**opposite order** on the two platforms: a big-endian archive stores `1`
then `0` where the DS convention is `0` then `1`. Nothing in the corpus
disambiguates which field is which, so the parser keeps the original bytes
(`rawNameTable`, carried through the manifest) and replays them. A NARC
built from scratch gets the spelling measured for big-endian and the DS
convention for little-endian. This is the only place either format is not
fully re-derived.

## Project layout

Unpacking follows the FSYS pattern: a manifest plus ordinary editable
files. For `homeBtn.arc` unpacked into `<folder>`:

```
<folder>/homeBtn.arc.json      the manifest (NintendoArchiveRegistry)
<folder>/homeBtn/…             the contents
```

A U8's contents keep the directory tree they had inside the archive. A
NARC's are flat — by name where it has one, by index where it doesn't.

The manifest holds what the contents don't imply: the format, the byte
order, entry order, U8 directory nodes (an empty one leaves no other
trace), and the raw name table above. Paths are stored relative to the
manifest's own folder, so an unpacked archive can be moved and still pack.

## Disc integration

`FSTRegistry.EntryType` has a `nintendoArchive` case. Its `file` points at
the manifest, and the FST rebuild repacks the archive from it rather than
copying bytes back — so an archive's contents are editable in the project
tree like anything else on the disc.

## Operations

| Operation | Config | Does |
|---|---|---|
| `nintendoArchiveDump` | `SingleConfig` | Unpack one archive |
| `nintendoArchiveBuild` | `SingleConfig` | Repack one archive from its manifest |
| `nintendoArchivesDump` | `BatchConfig` | Scan a folder, unpack everything matching |
| `nintendoArchivesBuild` | `BatchConfig` | Repack every manifest under a folder |

One pair of ops covers both formats rather than one pair each: the archive's
magic says which format and byte order it is, so a caller that had to name
the format up front could only get it wrong. The bulk dump identifies by
magic, not extension — a NARC named `.arc` still unpacks as a NARC — and
gives each archive its own subfolder so two archives holding the same
internal filename can't collide. `recursive` is off by default on the dump
so pointing it at one folder can't quietly walk a whole disc.

## Validation

- `NintendoArchiveRealCorpusTests` — all 30 PBR archives repack
  byte-identically. Skips cleanly without a dump; point it elsewhere with
  `GODDESS_NINTENDO_ARCHIVES`.
- `U8ArchiveTests` / `NARCArchiveTests` — the shapes the real corpus
  doesn't contain: little-endian archives, empty directories, deep nesting,
  named NARCs, unaligned sizes, empty payloads, and the malformed-input
  errors.
- `NintendoArchivePipelineTests` — unpack/pack through an `InMemoryFST`,
  including packing after the folder is moved, and that editing an
  extracted file changes the rebuilt archive.
- `NintendoArchiveOperationTests`, `DispatchRoutingTests` — the operation
  layer and its config routing.
