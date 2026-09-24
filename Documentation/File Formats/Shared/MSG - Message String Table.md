# MSG - Message String Table

MSG is the message/string table format used in Pokemon Colosseum and Pokemon XD for all in-game text including dialog, menu labels, item descriptions, Pokemon names, and system messages. Strings use a game-specific character encoding (GS format) with special control characters for text effects such as color changes, text speed, speaker names, and variable insertion (e.g., player name, Pokemon name, item counts).

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x0A` |
| Extension | `.msg` |
| Magic | none — the first word is a per-file value, not a signature |
| Byte Order | Big-endian |

There is **no magic**. A file that does start with `MESG` is Battle
Revolution's unrelated string table, which shares the extension and nothing
else; this parser refuses one rather than reading it as empty (PBR keeps its
count at +0x06, where this format has the region code). See
`Documentation/File Formats/Battle Revolution/MESG - String Tables.md`.

## Header

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | UInt32 | Reserved prefix | Varies per file; preserved verbatim |
| 0x04 | 2 | UInt16 | Entry count | |
| 0x06 | 2 | char[2] | Region code | ASCII — `US`, `UK`, `GE`, `FR`, `IT`, `SP`, `JP` |
| 0x08 | 8 | - | Reserved | All-zero in every file measured; preserved verbatim |

## Entry Table

`count` entries of 8 bytes, starting at 0x10:

| Offset | Size | Type | Field |
|--------|------|------|-------|
| 0x00 | 4 | UInt32 | String ID (low 20 bits effective) |
| 0x04 | 4 | UInt32 | Offset of the string, from the start of the file |

The table is not sorted. The game finds a string by scanning the table for
its id, not by binary search, so entry order is free — and a rebuild must
keep whatever order it was given rather than imposing one.

### File extent

The entry table gives every string's start and a string ends at its own
terminator, so a table's total length is derivable: it runs to the end of the
string with the highest offset. That is the only safe way to bound one
embedded in a larger buffer. XD's PAL build is the case that proves it — the
Spanish table at `lbl_803D5654` is ~97.9 KB, but a symbol 31 KB in cut the
DOL chunk there, so 584 of its 859 strings fell outside the dump and were
lost.

### String ID Range

Maximum string ID is `0xFFFFF` (20 bits), allowing up to 1,048,575 strings per table. In practice, individual MSG files contain far fewer strings; the 20-bit range accommodates global string ID allocation across all MSG files.

## String Pool

Strings follow the entry table, each a GS-encoded body terminated by a null
word. Measured across every MSG entry on all six GameCube discs — 2312
entries, 427,420 strings (Colosseum US 168 / PAL 811 / JP 169, XD US 211 /
PAL 770 / JP 183) — and the 9 tables embedded in the two games'
`common.rel`:

- **The pool is contiguous, unpadded and unaligned.** Each string starts
  immediately after the previous one's terminator. Rounding starts up to an
  even address is invisible in Colosseum, where every character is two bytes,
  but XD's encoding is variable-width and the pad byte per odd-length string
  is real growth.
- **The pool is not in entry-table order.** 1339 of the 2312 files lay their
  strings out in some other order. The order is not derivable from anything
  else in the file, so a parser has to record it (GODDESS keeps it per entry
  as `poolOrder`) and a writer has to follow it, or the output is the right
  bytes in the wrong places — same length, different file.
- **No two entries share a string.** Every entry has its own pool slot, even
  where two hold identical text.
- **A string ends where the next one starts.** Because the pool is
  contiguous, the next string's address is the previous one's end, and that
  — not the parser's own reading of the characters — is what bounds a read.
  A parser that trusts its reading runs past the end the moment it misreads
  a control code, and swallows the string after it.
- **A pool can hold strings no entry points at.** XD JP's `M6_tower_1F.msg`
  declares one entry and carries 450 bytes of unreferenced strings ahead of
  it. They have to be carried through a rebuild, or every offset after them
  moves. Only the run before the first referenced string and the run after
  the last can hold them — anything in between belongs to the string it
  follows.
- **A control code is not always complete.** Colosseum's `FFFF 09` carries a
  parameter byte in 239 of its 240 appearances across the three discs; the
  exception ends a string with none, so a parser that always reads one
  consumes the terminating null word instead. A reading that doesn't
  re-encode to the bytes it came from cannot be trusted, and the bytes have
  to win.
- **16 files declare no entries at all**, and are a header and nothing else.
- **A file ends on its last terminator.** There is no trailing padding and no
  file-level alignment. A table *embedded* in a DOL or REL is a different
  matter: its container pads it out to a 4-byte boundary (1-3 zero bytes
  between consecutive tables in XD's `common.rel`), and that padding belongs
  to the chunk, so a rewritten table has to keep it or the chunk shrinks and
  every symbol after it shifts.

## GS Character Encoding

The games use a custom character encoding rather than standard ASCII or Unicode. Characters are encoded as multi-byte sequences with special control codes for:

- **Text effects**: Color changes, font size, text display speed
- **Speaker names**: Control codes that insert the speaking character's name into a dialog box header
- **Variable insertion**: Placeholders for dynamic values such as the player's name, Pokemon names, item names, and numeric quantities
- **Line breaks and page breaks**: Control the flow of text within dialog boxes
- **Sound effects**: Trigger sound cues during text display

## MSG File Distribution

Multiple MSG files exist within a game:

- **Per-room MSG files**: Contained within room FSYS archives, holding dialog and text specific to that map area
- **common.rel global messages**: The common.rel relocatable module contains a global message table with strings shared across the entire game (item names, Pokemon names, menu text, system messages)

## Relationship to SCD Scripts

MSG files are tightly coupled with SCD script files. Scripts reference message IDs to display text:

1. A script function executes a `callStandard` dialog opcode with a message ID parameter
2. The engine resolves the message ID against either the current room's local MSG file or the global common.rel message table
3. The string is decoded from GS format, control codes are processed, and the text is rendered to the dialog box

This separation of text data (MSG) from logic (SCD) allows for localization by swapping MSG files without modifying scripts.

## Game-Specific Differences

- **Colosseum and XD** share the binary layout exactly. They differ only in
  their control code sets and character encoding tables, which is what the
  `variant` on a parse selects.
- **XD** has a larger set of control codes supporting additional text effects introduced for that game
