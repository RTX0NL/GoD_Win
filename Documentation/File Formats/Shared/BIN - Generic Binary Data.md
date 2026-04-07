# BIN - Generic Binary Data

BIN is a catch-all type identifier for generic binary data files that do not fit into a more specific format category. The contents and structure vary entirely by context.

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x34` |
| Byte Order | Big-endian (assumed, context-dependent) |

## Structure

BIN files have no fixed header structure. The interpretation of the data depends on which FSYS archive contains the file and which game code loads it.

## Known Uses

### XD: Gale of Darkness

In XD, BIN files are used to store battle configuration data:

- **Trainer data**: Trainer party definitions, AI settings, and battle parameters.
- **Pokemon deck data**: Pre-built team configurations used for specific battle scenarios (e.g., Mt. Battle, Colosseums).

The game code that loads these files applies the appropriate structure interpretation based on the archive context and internal offsets.

### Colosseum

Colosseum uses BIN entries for similar battle configuration purposes, though the specific data layouts differ from XD.

## Parsing

Because BIN has no self-describing structure, parsing requires external knowledge of what the data represents. This is typically determined by:

1. The FSYS archive the file belongs to.
2. The file's index or identifier within that archive.
3. Cross-referencing with game code that reads from the file.
