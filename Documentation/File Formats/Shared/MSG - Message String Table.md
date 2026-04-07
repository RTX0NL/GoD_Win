# MSG - Message String Table

MSG is the message/string table format used in Pokemon Colosseum and Pokemon XD for all in-game text including dialog, menu labels, item descriptions, Pokemon names, and system messages. Strings use a game-specific character encoding (GS format) with special control characters for text effects such as color changes, text speed, speaker names, and variable insertion (e.g., player name, Pokemon name, item counts).

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x0A` |
| Extension | `.msg` |
| Magic | `MESG` (optional, at offset 0x00) |
| Byte Order | Big-endian |

## Header

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | char[4] | Magic | `MESG` (may not be present in all variants) |
| 0x04 | 2 | UInt16 | String count | Number of strings in the table |
| 0x06 | 10 | - | Unknown / Reserved | |

The header is approximately 0x10 bytes, followed by the string offset table.

## String Offset Table

Immediately following the header is an array of `string_count` entries, each providing the offset to a string's data. The exact entry size and layout may vary slightly between games.

## String Data

Strings are stored as null-terminated sequences in the GS character encoding. Each string is referenced by its index (string ID) in the offset table.

### String ID Range

Maximum string ID is `0xFFFFF` (20 bits), allowing up to 1,048,575 strings per table. In practice, individual MSG files contain far fewer strings; the 20-bit range accommodates global string ID allocation across all MSG files.

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

- **Colosseum and XD** use the same general MSG layout but differ in their control code sets and character encoding tables
- **XD** has a larger set of control codes supporting additional text effects introduced for that game
- The `MESG` magic may or may not be present depending on the specific MSG file variant and game version
