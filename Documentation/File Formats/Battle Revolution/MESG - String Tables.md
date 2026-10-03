# MESG — Battle Revolution String Tables

Every piece of text in Pokémon Battle Revolution lives in a `MESG` string
table. Game data never names a table: a field holds a **global string id**,
and a directory in `common.fsys` says which table holds that string and
where in it.

**This is not the Colosseum/XD `.msg` format.** The two share an extension
and nothing else — different header, different string addressing, different
terminator, unrelated control-code vocabularies. `MSGFile` rejects a `MESG`
outright rather than misparsing it.

Measurements below are from the PAL disc (RPBP01) unless stated; the US
and JP discs differ in ways the sections below call out.

## The directory — `common.fsys` member 91

A dense array over the string ids. Member **91** on US and PAL discs,
**119** on JP (the JP disc orders `common.fsys` differently).

| Offset | Size | Field |
|---|---|---|
| 0x00 | 4 | Number of string tables (4 on every retail disc) |
| 0x04 | 4 | Number of string ids |
| 0x08 | 4 × N | One record per id, in id order starting at 1 |

Each record:

| Offset | Size | Field |
|---|---|---|
| 0x00 | 2 | Table id — the `MESG`'s own id at its +0x08, **not** a file index |
| 0x02 | 2 | Index within that table, 1-based |

The file is exactly `8 + 4N` bytes; the PAL disc's is 21,812 ids over four
tables (10011 + 9235 + 173 + 2393), which accounts for every string in every
table exactly once. The mapping is a **bijection** — no string is
unreachable and no id is shared.

The table count is what the game loads, not what the disc ships: **JP
declares four tables and ships three**, having dropped the battle tutorial,
and no id points at the fourth. The missing table still occupies its slot,
or every table after it would be renumbered.

Both halves of a lookup are array indexing, so nothing depends on a table's
strings being in id order. Retail happens to be, but a rebuild is free to
place a string at any index as long as the directory follows it.

## A table

| Offset | Size | Field |
|---|---|---|
| 0x00 | 4 | Magic `MESG` |
| 0x04 | 2 | High bits a string id is matched against. Zero on every retail table |
| 0x06 | 2 | String count |
| 0x08 | 4 | Table id — what the directory addresses |
| 0x0C | 4 | Language code, four ASCII characters |
| 0x10 | 4 × N | Absolute offset of each string |
| | | String bodies |

Bodies **tile exactly**: the first starts where the offset table ends, each
ends where the next begins, and the last ends at EOF. No padding, no gaps.

### Language codes

| Code | Language | Archive suffix |
|---|---|---|
| `USUK` | English | *(none)* |
| `FRFR` | French | `_f` |
| `GRGR` | German | `_g` |
| `ITIT` | Italian | `_i` |
| `SPSP` | Spanish | `_s` |
| `JPJP` | Japanese | *(JP disc)* |

German is `GRGR` and Spanish is `SPSP` — confirmed by decoding the files
(`mes_common_g` reads BISASAM, H2O-Absorber). The legacy GoD tool had these
two swapped.

### Where the tables live

PAL (30 entries, 20 distinct files):

| Table id | Strings | Archives |
|---|---|---|
| 1 | 10011 | `mes_common{,_f,_g,_i,_s}`[1] |
| 2 | 9235 | `mes_bpass_*`[2] **and** `mes_fight_*`[1] |
| 3 | 173 | `mes_bpass_*`[3] **and** `mes_name_*`[1] |
| 4 | 2393 | `menu_btutorial{,_f,_g,_i,_s}`[1] |

US ships the same four tables in the same five languages, but with four
extra English copies — 34 entries for 20 distinct files. Table 2's English
text is in `mes_bpass_e`[2], `mes_fight_e`[1], `menu_bpass2`[3] **and**
`menu_fight_s`[1]; table 3's in `mes_bpass_e`[3], `mes_name_e`[1],
`menu_bpass2`[2] **and** `menu_name2`[1]. (PBRHex's hardcoded file list is
the US one, which is why it doesn't match a PAL disc.)

JP is different again — **no `mes_*` archives at all**. Its five entries are
one language (`JPJP`):

| Table id | Strings | Archives |
|---|---|---|
| 1 | 12212 | `common.fsys`[35] |
| 2 | 8737 | `menu_bpass2`[3] **and** `menu_fight_s`[1] |
| 3 | 148 | `menu_bpass2`[2] **and** `menu_name2`[1] |
| 4 | — | not shipped; the directory declares it and nothing points at it |

Whichever disc, a rebuild must write **every** copy, or the game reads stale
text from whichever it happens to load.

### Languages don't all reach the end

A table's languages share one index per id, but they need not all be the
same length. On the US disc the English tables run past the others:

| Table | English | Other languages |
|---|---|---|
| 1 | 9995 | 9991 |
| 2 | 9233 | 8737 |
| 3 | 157 | 157 |
| 4 | 2389 | 2389 |

The shorter copies are **prefixes**: their trailing entries are empty
strings and they simply stop, with only four ids in table 1 reaching past
the French end (21275, 21276, 21773, 21774 → indices 9992–9995, all
English-only Wi-Fi and Friend Pass text). Index N still means the same id in
every language, so a language can end early but cannot skip and resume. PAL
has every language at the same length.

## String encoding

UTF-16 big-endian code units, terminated by `FFFFFFFF`. A unit of `FFFF`
introduces a control word: the next 16 bits are its id, followed by that
id's parameter, if it has one.

| Id | Parameter | Meaning |
|---|---|---|
| `0001` | 2 bytes + characters | Furigana: kana count, kanji count, then that many kana followed by that many kanji (JP only — 6,255 markers, none on US or PAL) |
| `0002` | 2 bytes | Pause |
| `0003` | 2 bytes | Alignment |
| `0005` | 2 bytes | Colour |
| `8011` | 4 bytes | Vertical offset (signed) |
| `F0xx` | — | Font size, in the low byte |
| `F1xx` | — | Letter spacing, in the low byte (signed) |
| `FFF9` | — | "PP" |
| `FFFA` | — | "HP" |
| `FFFB` | — | "Lv." |
| `FFFC` | — | "No." |
| `FFFE` | — | Line break |
| `FFFF` | — | End of string |

Every other id takes no parameter. That set of parameter lengths is what
makes the bodies tile exactly across all 21,812 strings — a wrong length
would desynchronise the walk — so the table above is measured, not assumed.

The remaining ~90 ids (`0006`–`006C`) are variable substitutions — player
name, Pokémon name, and so on — and are not individually identified. They
round-trip as `{xx xx}` hex tokens.

In the document a control word is a `{…}` token: `{Size: 1}`, `{Spacing: 1}`,
`{Align: 3}`, `{Color: 5}`, `{VerticalOffset: -8}`, `{No.}`, `{Lv.}`,
`{HP}`, `{PP}`, and a newline as an actual line break. Furigana is
`{Furigana:<kana>:<kanji>}` — reading first, then what it annotates. The
separator has to be a character the runs never contain, which rules out a
space: 58 of the JP disc's markers have a space as their kana or kanji.
None of its 6,441 markers contains a colon, and one that did would fall back
to its raw bytes rather than round-trip wrongly.

## The project artifacts

`pbrStringsDump` writes every string into one document
(`Source/Text/Strings.json`), and `pbrStringsBuild` writes it back to the
`.msg` binaries and regenerates the directory. See the
[Configuration Reference](../../GODDESS%20Configuration%20Reference.md).

The document is organised by table, then by id, with each id's text in
every language on one row — which makes the cross-language constraint
(one index per id, shared by every language) structural rather than
something a build has to check.

Everything derivable is derived: a table's id is its position, a string's
index is its row's position, the string count is the number of rows, and the
directory is rebuilt from the rows. **Ids are the only stable reference.**
Consequently:

- a row can be inserted anywhere without changing what an existing id means;
- ids must run from 1 with no gaps, because the directory is an array
  indexed by id — new strings go at the end, and a string is retired by
  blanking its text rather than deleting its row;
- an id belongs to exactly one table;
- a row carries text for the languages that reach it, which on a US disc is
  not always all of them. A language may stop before the table ends, but its
  text has to be an unbroken run from the start — a gap would put every
  later string at the wrong index for that language, so the build refuses
  it by name.

## Verification

`PBRStringRealCorpusTests` (format) and `PBRStringsRealCorpusTests`
(operations) read a real disc's files and write them back. Verified on all
three regions — every entry and the directory byte-identical, including the
whole disc → document → disc round trip through the operations:

| Disc | Entries | Strings repacked |
|---|---|---|
| PAL (RPBP01) | 30 | 156,100 |
| US (RPBE01) | 34 | 170,616 |
| JP (RPBJ01) | 5 | 29,982 |

Both tests skip without a disc dump and are region-agnostic;
`GODDESS_PBR_FILES` points them at a `DATA/files` folder.
