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

#### Colosseum binary layout (verified against all 142 US scripts and the US engine disassembly)

| Offset | Size | Field |
|--------|------|-------|
| 0x00 | 2 | Script kind ID (0x0100) — matched against the high half of 32-bit runtime script handles |
| 0x02 | 2 | Constant 0x0101 in all US scripts (meaning unknown) |
| 0x04 | 2 | Function count |
| 0x06 | 2 | Relocation count |
| 0x08 | 2 | Compiler metadata — **never read by the engine** (correlates ~0.99 with function count; possibly total symbol/temporary count). Preserve verbatim. |
| 0x0A | 2 | Runtime "already relocated" flag byte — 0 on disk (loader `zz_800f76e4_` sets it) |
| 0x0C | 4 | Relocation table offset (= 0x18 + functionCount × 4) |
| 0x10 | 4 | Globals arena offset (= relocation table end = 0x0C + relocCount × 4) |
| 0x14 | 4 | Runtime linked-list next pointer — 0 on disk |
| 0x18 | 4×N | Function table: function index → bytecode offset |

After the function table:

- **Relocation table** (relocCount × u32): each entry is the file offset of a
  u32 fixup site — typically a `pushImmediate` operand holding the file offset
  of a NUL-terminated string near the end of the file (printf format strings).
  The loader adds the script base to each fixup at load time.
- **Globals arena**: zero-filled, 4 bytes per script global variable. Task
  contexts get `base + globalsOffset` as their globals base
  (`zz_800f6d18_` stores it at ctx+0x18), so script globals live *inside the
  loaded script image* and are shared by every task running that script.
  The arena size is a compiler-side declaration — scripts index globals with
  computed expressions, so it cannot generally be recovered by static analysis.
- **Bytecode**: contiguous code runs (no inter-run padding). The file is
  zero-padded to a 32-byte boundary after the last run; relocated string data
  sits in that tail region.

Function table facts: it is usually **not** sorted by offset (code emission
order ≠ function index order), and entries can be **0** (null function).

Engine landmarks (US): loader/relocator `zz_800f76e4_`, resource-cache fetch
`zz_800f9318_`, task spawn `zz_800f6d18_` (0x16C-byte VM contexts: +0x14 PC,
+0x18 globals base, +0x28 SP, +0x6C value stack[64]), interpreter fetch/dispatch
`zz_800f6bc4_` (38-entry handler table at 0x803155D0), varargs script-task API
`zz_800f7318_`, script registry insert `zz_800fc39c_`.

#### Colosseum built-in (`callStandard`) dispatch and typing

- **Native builtin table at 0x802E1CF0** (installed into scriptManager+0x10 by
  `zz_800f75fc_` at init): flat array indexed directly by the script-side
  function ID, 12 bytes per entry: `{u32 handlerPointer, u8 argTypes[8]}`.
  Arg type bytes: 0 = end of list, 2 = float, else int. The `callStandard`
  opcode handler (`zz_800f10e8_`, opcode 37) marshals stack values into
  separate int/float argument blocks according to these bytes — i.e. **the
  engine itself declares every builtin's primitive signature**. 246
  implemented entries (IDs 1–246). Extracted listing:
  `Documentation/File Formats/Colosseum/Script Builtin Native Table.json`.
- Corpus discipline: 183 builtin IDs are used by shipped scripts; the 39 whose
  results are consumed are consumed at essentially *every* call site — return
  types are strict, not ad hoc.
- **The tables registered at 0x8027A500 / 0x802BD260 / 0x802C0CB0 are NOT the
  native builtins** — they are DOL-embedded *bytecode* script libraries
  ("common scripts") in registry-record form ({u16 scriptKindID, u32 length,
  payload}); their payloads carry sparse function tables of
  `{u16 functionID, u8, u8, u8, u24 bytecodeOffset}` entries. The `call`
  opcode's 32-bit function ID encodes `scriptKind << 16 | functionIndex` —
  low-half-only IDs are intra-script calls; e.g. `0x05960015` calls function
  0x15 of registered script kind 0x596. Map .scd files are kind 0x0100.
- Script-global typing: every gvar slot in the US corpus is accessed with a
  single consistent primitive mask (455 slots, zero mixed) — variables are
  strongly typed. Value-returning script functions use local 0 as the return
  slot with arguments in locals 1..N; void functions' arguments start at
  local 0. No function-scoped locals exist beyond arguments.

#### Colosseum code-generation conventions (measured corpus-wide)

The GS compiler is deterministic; these rules reproduce its output byte-exactly:

- Variable reads: `pushImmediate(index)` + `pushMultiVar(mask, count: 1)`.
  `pushVar` is a rarer distinct form (73 occurrences; semantics unconfirmed —
  possibly reference/pointer reads). `pushVar2` and `pushMinus1` are never
  used; `-1` is a plain integer immediate.
- Operator/`setVar` operand masks are carried by the consumer instruction;
  a literal-mask operand pushes only its inner value.
- Every statement's leftover value is discarded with `pop`: mask `0x81`
  count 0 for void, `0x82`/`0x83` count 1 for int/float. An assignment's pop
  mask follows the **target** variable's type.
- Built-in calls (`callStandard`): push object ref (`pushImmediate(0)` +
  `pushMultiVar(0x42, 1)`), then the function ID, then arguments;
  `argCount` = arguments + 1 (the ID). The function ID is *usually* an
  integer immediate but can be any expression (D4_tower_1F_2 computes it via
  a script call). `returnCount` is always 1 and the result pop is always int.
- Script calls (`call`): when `returnCount == 1`, a return-slot reference
  (`pushImmediate(0)` + `pushMultiVar(0x42, 1)`) is pushed **below** the
  arguments; `returnCount == 0` calls have no slot and pop with `(0x81, 0)`.
- `return value` compiles to `pushImmediate(0)`, the value, `setVar` targeting
  local 0 (mask 0x42), an int pop, then `returnOp`. Every function ends with an
  implicit extra `returnOp`.
- Dead conditionals (`if 1 { … }`) and `while(1)` loops exist in shipped data;
  a jump target can simultaneously be an if-end and a loop top.

#### Round-trip pipeline (GODSDK `Colosseum` module)

`ColoScript` (lossless parse) → `ColoExpressionBuilder` (stack sim) →
`ColoExpressionCompound` (if/while structuring) → `ColoExprUncompound`
(structures → jumps with symbolic labels) → `ColoExprLowering` (expressions →
instructions, label fixup) → `ColoScriptAssembler` (binary writer).

`ColoScript` (lossless parse) ⇄ `ColoScriptAssembler`;
`ColoExpressionBuilder` ⇄ `ColoExprLowering`;
`ColoExpressionCompound` ⇄ `ColoExprUncompound`;
`ColoScriptSourceEmitter` (dialect text, Swift or Python flavour) ⇄
`ColoScriptTextParser` + `ColoScriptCompiler`. **All round-trip stages —
including full binary → source text → compile → binary in BOTH dialects —
are byte-exact on the entire 142-file US corpus** (`ColoScriptDecomp --roundtrip`,
`ColoScriptRoundTripTests`).

Dialect rules that make the text lossless:
- Reserved constants `__scriptType`, `__compilerMetadata`; flat typed global
  declarations (`var gvar0 = 0` int / `= 0.0` float / `: Object` for
  0x20-flag slots) whose count sizes the arena; functions in file order;
  null table entries as bodyless stubs; `argN: Float` annotations;
  `-> Int` marks value-returning functions (drives call returnCount and the
  local0-return-slot arg shift).
- Every function's final terminating `returnOp` is implicit; `exit()` is
  explicit; unstructured jumps render as `goto L_xxxx` / `L_xxxx:` labels
  (a dialect extension in both flavours).
- Python flavour: indentation blocks with `def f(arg0) -> int:` / `elif` /
  `else:` / `pass`, `and`/`or`/`not`, `True`/`False`, `# comments`,
  module-level `__SCRIPT_TYPE__`-style constants and bare `gvarN = 0`
  declarations; everything else is shared with the Swift flavour.
- Computed arena access via `globals[expr]` / `globalsF[expr]` /
  `globalsO[expr]` / `locals[expr]` (accessor spells the access mask);
  `&` marks pushVar-form reads; `dup(x, n)` is a count-n pushMultiVar.
- Operand masks: a bare variable reference in operator/assignment positions
  binds directly to the consumer instruction's operand mask; a
  **parenthesized** bare reference is a materialized (pushed) read. Pushed
  reads and assignment/return sources take mask `0x80 | the variable's own
  mask` (locals → 0xC2); other pushed values take `0x80 | value type`.
  Multiplications of two constants fold; additions never fold.
- printf string literals compile to 8-aligned tail data + relocation
  entries; files with strings end at the final NUL, others pad to 32 bytes.

### callStandard Functions

The `callStandard` opcode dispatches to engine built-in functions. The operand encodes both a function class and function index. Each game has its own set of standard function classes (battle, movement, dialog, camera, sound, etc.) with different function counts and semantics. These are the primary interface between scripts and the game engine.

## Relationship to MSG

SCD scripts reference MSG (message table) entries by string ID to display dialog text. A script function typically calls a `callStandard` dialog function with a message ID parameter, which the engine resolves against the current room's MSG file or the global common.rel message table.
