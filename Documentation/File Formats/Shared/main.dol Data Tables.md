# Colosseum / XD `main.dol` data tables

Both games keep data tables in `main.dol` as well as in `common.rel`, and they
split them differently. XD's DOL holds 13: the menu-sprite table, status
effects, abilities, TMs and the PKX/WZX model and animation references.
Colosseum's holds 15 — the same nine families, plus items, the two valid-item
lists, types, the menu-sprite draw list and the script builtin dispatch table,
because Colosseum keeps in the DOL much of what XD keeps in `common.rel`.

The type maps (`Resources/dol_typemap_{us,eu,jp}.json` in each game engine)
bind each table to a struct; `dolDisassembly` writes each one as a CSV under
`Source/Code/main/dataN/`. The struct definitions are
`XD/Structs/entries/DolStructs.swift` and
`Colosseum/Structs/entries/DolStructs.swift`.

## Why this is harder than `common.rel`

A `common.rel` chunk is named by **pointer-index symbol** — an ordinal, which
survives a rebuild and is the same idea on every build. A DOL chunk is named
by **address**. So every table has to be located separately on every build,
and there is nothing in the file that says where they are.

Three sources were used, in descending order of trust.

**The symbol map, where the table has a name.** Three of XD's are named on all
three builds, at identical sizes: `joutai_data` (status effects, 0x6CC),
`pokemon_tokusei_data` (abilities, 0x3A8) and `item_waza_machine_no` (TMs,
0x1D0). Colosseum's maps are mostly positional and name none of its tables.

**The game's own accessor.** `menuSpriteBiosGetPtr` is a generated
four-instruction routine:

```
mulli  r4, r3, 0x48        # row stride
lis    r3, 0x8030
addi   r3, r3, 0x01a8      # table address
```

so it gives the address *and* the stride. That is what pinned the menu-sprite
record's two shapes — 0x48 with five languages, 0x18 with one — and settled
which build has which: **XD is multi-language except JP, Colosseum is
single-language except PAL.**

**A content signature**, for a table nothing names and no accessor was found
for. Take every non-pointer column of the build you know and match it against
the others. Colosseum's `ScriptBuiltinFunctions` and `TextureRenderingInfo`
were located on PAL and JP this way, and the check that the match is the whole
table rather than a prefix is that each ends exactly where the Dolphin SDK
version string (`<< Dolphin SDK - OS…`) begins.

## What the legacy tool gets wrong

The legacy tool's per-region constants reproduce the shipped **US** addresses
exactly, which is what makes them worth porting. Six of its other-region
values do not:

| Table | Build | Legacy | Actual | Out by |
|---|---|---|---|---|
| XD `WZXAnimations` | PAL | `0x8044AA0C` | `0x8044AA08` | 4 |
| XD `UnownPKXModels` | PAL | `0x8044A624` | `0x8044A620` | 4 |
| XD `DeoxysPKXModels` | PAL | `0x8044D95C` | `0x8044D958` | 4 |
| XD `DeoxysShinyPKXModels` | PAL | `0x8044D97C` | `0x8044D978` | 4 |
| XD `MenuData` | JP | `0x802F6E1C` | `0x802F6E10` | 12 |
| Colosseum `UnownPKXModels` | PAL | `0x803C22C0` | `0x803C22C8` | 8 |
| Colosseum `ShinyPKXPokemonModels` | JP | `0x80361690` | `0x80361688` | 8 |

Its counts need checking too. Colosseum has **86** status effects, not XD's
87 (entry 86 on a Colosseum disc is already the pointer array that follows, on
all three regions); its second valid-item list is **548** entries, not the
first list's 1220; and it has **247** script builtins, 246 on JP, not 242. Its
count *offsets* are off as well — the PKX/WZX count block is 4 bytes later
than it claims on XD PAL and 8 bytes earlier on Colosseum PAL.

One defect was in this tool's own shipped map rather than the legacy one: XD
`Abilities` was declared at 123 rows where the count word, the symbol size and
the first non-ability byte all say **78**. The extra 45 rows were 540 bytes of
the next object read as abilities.

## How an address is checked

A table must tile its declared count exactly into the space between its own
label and the next one. That single test catches every error above, and it is
the one the tables below have each been held to on the real US, PAL and JP
discs.

Two failure modes make a wrong address hard to see, which is why the check is
mechanical rather than by eye:

- **A type-map chunk whose address has no label is skipped in silence.** So
  "this region declares no tables" and "this region's addresses are four bytes
  out" produce identical output.
- **A count that is merely too large still dumps.** It round-trips, and every
  row that is really there still reads correctly; only the rows past the end
  are nonsense, and the chunks they cover are swallowed. Clamping to the next
  label would not catch it: after XD's `Abilities` the next label is 0x53A8
  bytes away, so a table 540 bytes too long fits in the gap untouched.

Leaving the count out is fine where a label already marks the table's end — it
then runs to the next label, the same rule the REL side uses. Declare it where
the next label is far away, which is most of the tables here.

`DolTableCSVCorpusTests` asserts presence, row count, and — where the symbol
map names the table's start — that `count × stride` equals the symbol's
declared size, which is the assertion that catches a too-large count.

## XD

| Table | Struct | Rows | US | PAL | JP |
|---|---|---:|---|---|---|
| `MenuData` | `MenuData` | 288 | `0x802FC8F0` | `0x802FDFB0` | `0x802F6E10` |
| `Textures` | `Texture` / `TextureJP` | 1019 | `0x803001A8` | `0x803018D8` | `0x802FA460` |
| `StatusEffects` | `StatusEffect` | 87 | `0x803FC3E0` | `0x80436CC0` | `0x803D9AA0` |
| `Abilities` | `Ability` | 78 | `0x803FFC50` | `0x8043A530` | `0x803DD310` |
| `TMs` | `TM` | 58 | `0x804053A0` | `0x8043FC80` | `0x803E2A60` |
| `WZXMoveAnimations` | `WZXMoveAnimation` | 373 | `0x8040C5C8` | `0x80446EA8` | `0x803E9C78` |
| `PKXTrainerModels` | `PKXModel` | 68 | `0x8040CE88` | `0x80447768` | `0x803EA538` |
| `PKXPokemonModels` | `PKXModel` | 419 | `0x8040D0A8` | `0x80447988` | `0x803EA758` |
| `UnownPKXModels` | `PKXModel` | 28 | `0x8040FD08` | `0x8044A620` | `0x803ED3B8` |
| `ShinyPKXPokemonModels` | `ShinyPKXModel` | 35 | `0x8040FDE8` | `0x8044A700` | `0x803ED498` |
| `WZXAnimations` | `WZXAnimation` | 1399 | `0x804100F0` | `0x8044AA08` | `0x803ED7A0` |
| `DeoxysPKXModels` | `PKXModel` | 4 | `0x80412F60` | `0x8044D958` | `0x803F0610` |
| `DeoxysShinyPKXModels` | `PKXModel` | 4 | `0x80412F80` | `0x8044D978` | `0x803F0630` |

Counts are the same on all three builds. `Textures` is the only record whose
shape changes: `TextureJP` carries one `TextureInfo` (0x18) where `Texture`
carries five (0x48).

## Colosseum

| Table | Struct | Rows | US | PAL | JP |
|---|---|---:|---|---|---|
| `ValidItems` | `ValidItem` | 1220 | `0x80310E58` | `0x8035DF10` | `0x802FDBF8` |
| `Types` | `Type` | 18 | `0x8035B500` | `0x803A85C0` | `0x80347C40` |
| `StatusEffects` | `StatusEffect` | 86 | `0x8035BBA8` | `0x803A8C50` | `0x803482E8` |
| `Abilities` | `Ability` | 78 | `0x8035F5E0` | `0x803AC688` | `0x8034BD20` |
| `Items` | `Item` | 397 | `0x80363CE8` | `0x803B0DA0` | `0x80350428` |
| `TMs` | `TM` | 58 | `0x80368018` | `0x803B50D0` | `0x80354758` |
| `ValidItems2` | `ValidItem` | 548 | `0x803681E8` | `0x803B52A0` | `0x80354928` |
| `WZXMoveAnimations` | `WZXMoveAnimation` | 356 | `0x8036E150` | `0x803BB248` | `0x8035A8B8` |
| `PKXTrainerModels` | `PKXModel` | 76 | `0x80370840` | `0x803BD938` | `0x8035CFA8` |
| `PKXPokemonModels` | `PKXModel` | 417 | `0x80370BD0` | `0x803BDCC8` | `0x8035D338` |
| `UnownPKXModels` | `UnownPKXModel` | 28 | `0x80374E40` | `0x803C22C8` | `0x803615A8` |
| `ShinyPKXPokemonModels` | `ShinyPKXModel` | 35 | `0x80374F20` | `0x803C23A8` | `0x80361688` |
| `Textures` | `Texture` / `TextureEU` | 986 | `0x802E7CE8` | `0x80329570` | `0x802D4CB8` |
| `TextureRenderingInfo` | `TextureRenderingInfo` | 4818 / 4829 / 4799 | `0x802EF0A8` | `0x8033C028` | `0x802DC058` |
| `ScriptBuiltinFunctions` | `ScriptBuiltinFunction` | 247 / 247 / 246 | `0x802E1CF0` | `0x80323508` | `0x802CF530` |

Where three counts are given they are US / PAL / JP. `TextureEU` is the
five-language menu sprite; every other record is the same on all three builds.

Two records differ from XD's of the same name: Colosseum's `PKXModel` is 0x0C
to XD's 0x08, because its model rows carry the model's name id as well, and
its `WZXMoveAnimation` is 0x1C to XD's 0x06 — XD stores three indices into its
own animation table where Colosseum stores the three fsys references outright.
`Ability`, `StatusEffect`, `TM` and `ShinyPKXModel` are the same records in
both games.

### Shapes worth knowing

- **`Ability` is identical in both games**, down to the message ids: ability 1
  is name 3101 / description 3301 on all six discs. That identity is what
  generated the shared ability enum.
- **`Item` is XD's `common.rel` record, field for field**, so the names come
  from XD's own `itemDataBiosGet*` accessors. The difference is where the two
  function pointers live: a relocation in a REL, a stored address here, which
  the game overwrites at load — an item that carries one on disc keeps it.
  The byte at +0x02 the legacy tool calls padding is `useful_flag`, set on 7
  items, exactly as in XD.
- **`ScriptBuiltinFunction` is a handler pointer and eight argument-type
  bytes** (0 = end of list, 2 = float, anything else = a 32-bit value). Eight,
  not four: builtin 170 takes `01 01 02 02 02 02 02 01`, which is the only row
  that reaches the last two slots and is what fixes the record's width.
- **`TextureRenderingInfo` is a linked list, not a flat table**:
  `next_entry_index` chains the sprites of one screen. Its first byte is a
  flag field (bit 6 terminates the chain) kept whole, because `StructData` has
  no sub-byte support.
