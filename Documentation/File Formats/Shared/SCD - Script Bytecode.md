# SCD - Script Bytecode

SCD is the compiled script bytecode format used by the Genius Sonority script engine in Pokemon Colosseum and Pokemon XD. Each SCD file contains a complete script program with functions, bytecode instructions, global variables, string references, 3D vectors, character references, and arrays. Scripts drive all in-game events including NPC dialog, cutscenes, battle triggers, item interactions, and map transitions.

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x0E` |
| Extension | `.scd` |
| Byte Order | Big-endian |

## File Structure (XD)

XD SCD files use a sectioned layout where each section has a 0x20-byte header with identifying magic bytes:

```
+------------------+
| TCOD Header      |  0x10 bytes
+------------------+
| FTBL Section     |  Function table
+------------------+
| HEAD Section     |  Function headers
+------------------+
| CODE Section     |  Bytecode instructions
+------------------+
| GVAR Section     |  Global variables
+------------------+
| STRG Section     |  String data
+------------------+
| VECT Section     |  3D vectors
+------------------+
| GIRI Section     |  Character references
+------------------+
| ARRY Section     |  Array data
+------------------+
```

### TCOD Header (0x10 bytes)

The top-level header identifying this as a script file.

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | char[4] | Magic | `TCOD` |
| 0x04 | 4 | UInt32 | Unknown | |
| 0x08 | 4 | UInt32 | Unknown | |
| 0x0C | 4 | UInt32 | Unknown | |

### Section Headers (0x20 bytes each)

Each subsequent section begins with a standardized header:

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | char[4] | Magic | Section identifier (e.g. `FTBL`, `CODE`) |
| 0x04 | 4 | UInt32 | Entry count | Number of entries in this section |
| 0x08 | 24 | - | Reserved | |

## Sections

### FTBL - Function Table

Defines the script's callable functions. Each entry is 8 bytes:

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | UInt32 | Code offset | Byte offset into the CODE section |
| 0x04 | 4 | UInt32 | Name offset | Byte offset into the STRG section for the function name |

### HEAD - Function Headers

Contains metadata for each function (parameter counts, local variable counts, etc.). Detailed layout is function-specific.

### CODE - Bytecode Instructions

The executable bytecode. Each instruction is 1 or 2 UInt32 words (4 or 8 bytes).

### GVAR - Global Variables

Global variable declarations. Each entry is 8 bytes:

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | UInt32 | Type | Variable type identifier |
| 0x04 | 4 | UInt32 | Value | Initial value |

### STRG - String Data

Null-terminated strings used by the script for function names, debug labels, and string literals.

### VECT - 3D Vectors

3D coordinate vectors. Each entry is 12 bytes:

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | Float32 | X | |
| 0x04 | 4 | Float32 | Y | |
| 0x08 | 4 | Float32 | Z | |

### GIRI - Character References

Group ID / Resource ID pairs identifying characters and assets. Each entry is 8 bytes:

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | UInt32 | Group ID | FSYS archive group ID |
| 0x04 | 4 | UInt32 | Resource ID | File index within the archive |

### ARRY - Arrays

Array data used by the script. Layout depends on the array element type.

## Opcodes

The script VM uses 18 opcodes:

| Value | Name | Operands | Description |
|-------|------|----------|-------------|
| 0 | nop | 0 | No operation |
| 1 | operator | 1 | Arithmetic/comparison operator (subtype in operand) |
| 2 | loadImmediate | 1 | Push immediate value onto stack |
| 3 | loadVariable | 1 | Push variable value onto stack |
| 4 | setVariable | 1 | Pop stack and store to variable |
| 5 | setVector | 1 | Set a 3D vector variable |
| 6 | pop | 0 | Discard top of stack |
| 7 | call | 1 | Call a script function |
| 8 | return | 0 | Return from function |
| 9 | callStandard | 1 | Call a built-in engine function |
| 10 | jumpIfTrue | 1 | Conditional branch (pop stack, jump if nonzero) |
| 11 | jumpIfFalse | 1 | Conditional branch (pop stack, jump if zero) |
| 12 | jump | 1 | Unconditional branch |
| 13 | reserve | 1 | Allocate local stack frame |
| 14 | release | 0 | Deallocate local stack frame |
| 15 | exit | 0 | Terminate script execution |
| 16 | setLine | 1 | Set source line number (debug) |
| 17 | loadNonCopyableVariable | 1 | Load variable by reference (not by value) |

Instructions with operands use 2 UInt32 words (8 bytes total). Instructions without operands use 1 UInt32 word (4 bytes).

## Game-Specific Differences

### XD

- Full sectioned format with TCOD header and per-section magic bytes
- Section headers are 0x20 bytes each
- Richer set of `callStandard` built-in functions
- More complex script programs (cutscenes, Shadow Pokemon mechanics)

### Colosseum

- Simpler header format: 0x18 bytes, no per-section magic bytes
- Sections are laid out sequentially but identified by offset rather than magic
- Fewer `callStandard` built-in functions
- Script system is less fully featured compared to XD

### callStandard Functions

The `callStandard` opcode dispatches to engine built-in functions. The operand encodes both a function class and function index. Each game has its own set of standard function classes (battle, movement, dialog, camera, sound, etc.) with different function counts and semantics. These are the primary interface between scripts and the game engine.

## Relationship to MSG

SCD scripts reference MSG (message table) entries by string ID to display dialog text. A script function typically calls a `callStandard` dialog function with a message ID parameter, which the engine resolves against the current room's MSG file or the global common.rel message table.
