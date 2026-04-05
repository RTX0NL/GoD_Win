# XD Script Decompiler/Compiler

## Overview

Pokemon XD uses a stack-based bytecode VM for scripting (SCD files). This document describes the implementation plan for a from-scratch script decompiler and compiler with proper CFG-based control flow analysis, regex-based tokenization, and dual Python/Swift output syntax.

A follow-up phase will add **Map Interaction JSON files** that tie together scripts, characters, warps, treasures, and other map data into a single editable file per room. Each map JSON will be self-contained — including its filtered common.rel entries inline — and a sequential compile operation will write common table entries back for each map in order.

---

## SCD File Format

### Sections

| Section | Magic | Contents |
|---------|-------|----------|
| TCOD | `0x54434F44` | File header (total size) |
| FTBL | `0x4654424C` | Function table (name + code offset per function) |
| HEAD | `0x48454144` | Function headers (code offsets) |
| CODE | `0x434F4445` | Bytecode instructions |
| GVAR | `0x47564152` | Global variables (type + value) |
| STRG | `0x53545247` | String table (null-terminated) |
| VECT | `0x56454354` | Vector constants (x, y, z floats) |
| GIRI | `0x47495249` | Character references (group ID + resource ID) |
| ARRY | `0x41525259` | Array variables |

Each section has a common header: `[magic:4][size:4][padding:4][count:4][extra:4][padding:4]` followed by entries padded to 16-byte alignment.

### Instruction Encoding

Each instruction is 1-2 UInt32 words:

```
Word 1: [opcode:8][subopcode:8][parameter:16]
Word 2: [extended value:32]  (optional — for loadImmediate, jumps)
```

The subopcode splits into two 4-bit fields: `upper = subopcode >> 4`, `lower = subopcode & 0xF`. The lower nibble encodes the variable level for load/store instructions.

### Opcodes

| Code | Name | Description |
|------|------|-------------|
| 0 | nop | No operation |
| 1 | operator | Execute unary/binary operator |
| 2 | loadImmediate | Push constant (int, float, string, vector, etc.) |
| 3 | loadVariable | Push variable value onto stack |
| 4 | setVariable | Pop stack and store to variable |
| 5 | setVector | Set vector component (vx, vy, vz) |
| 6 | pop | Pop N items from stack |
| 7 | call | Call script function |
| 8 | return | Return from function |
| 9 | callStandard | Call built-in class method |
| 10 | jumpIfTrue | Conditional jump if stack top is true |
| 11 | jumpIfFalse | Conditional jump if stack top is false |
| 12 | jump | Unconditional jump |
| 13 | reserve | Reserve stack space for locals |
| 14 | release | Release stack space |
| 15 | exit | Exit script execution |
| 16 | setLine | Debug line number info |
| 17 | loadNonCopyableVariable | Load pointer to non-copyable object |

### Variable Levels

The lower nibble of the subopcode determines where a variable lives:

| Level | Storage | Encoding |
|-------|---------|----------|
| 0 | Global | Index into GVAR section |
| 1 | Stack | Positive = arguments, negative = locals |
| 2 | Last result | Return value from previous call |
| 3+ | Objects | `<0x80` = script class, `0x80` = player, `0x81-0x120` = NPCs, `0x200-0x300` = arrays |

### Constant Types

| Index | Type | Size | Notes |
|-------|------|------|-------|
| 0 | void | - | NULL |
| 1 | integer | 4 bytes | Int32 |
| 2 | float | 4 bytes | IEEE 754 |
| 3 | string | 2 bytes | String table offset |
| 4 | vector | 2 bytes | Vector table offset |
| 5 | matrix | 4 bytes | Unused |
| 6 | object | 4 bytes | Object instance ID |
| 7 | array | 2 bytes | Array table offset |
| 8 | text | 2 bytes | Message table ID (XD only) |
| 35 | character | 4 bytes | Character reference (XD only) |
| 37 | pokemonIndex | 4 bytes | Pokemon index (XD only) |
| 53 | codePointer | 4 bytes | Function location |

### Operators

**Unary (16-25):** `!`(NOT), `-`(negate), `hex`, `string`, `integer`, `float`, `getvx`, `getvy`, `getvz`, `zerofloat`

**Binary arithmetic (32-39):** `^`(XOR), `or`, `and`, `+`, `-`, `*`, `/`, `%`

**Comparison (48-53):** `==`, `>`, `>=`, `<`, `<=`, `!=`

---

## Architecture

### Module Location

The script engine lives in the XD engine module:

```
Sources/Shared/Core/Engines/XD/
├── File Formats/
│   └── SCDScript.swift            — SCD file parse/serialize (FileFormat)
├── Script/
│   ├── ScriptInstruction.swift    — Instruction decode/encode
│   ├── ScriptOpcode.swift         — Opcode enum
│   ├── ScriptConstant.swift       — Typed constants
│   ├── ScriptVariable.swift       — Variable levels/scopes
│   ├── ScriptIR.swift             — Intermediate representation
│   ├── ControlFlowGraph.swift     — Basic blocks, edges, dominators
│   ├── StructuredAST.swift        — if/else/while/return/call nodes
│   ├── Decompiler.swift           — IR → CFG → AST pipeline
│   ├── ASTFormatter.swift         — AST → text (syntax-agnostic)
│   ├── Lexer.swift                — Regex-based tokenizer
│   ├── Parser.swift               — Recursive descent → AST
│   ├── Compiler.swift             — AST → IR → bytecode → SCD
│   └── ScriptClassDefs.swift      — Built-in class/function definitions
```

### Decompiler Pipeline

```
SCD binary
  → SCDScript (parse sections)
    → ScriptIR (decode instructions per function)
      → ControlFlowGraph (basic blocks + edges)
        → StructuredAST (pattern-match if/while/etc)
          → Text (pretty-print with macros)
```

**Step 1: SCD → IR**
- Parse all SCD sections into typed Swift structs
- Decode each instruction into `ScriptInstruction` values
- Group by function using FTBL/HEAD offsets

**Step 2: IR → Control Flow Graph**
- Split instruction sequences into basic blocks at jump targets and sources
- Build directed edges: fallthrough, conditional branch, unconditional jump, back-edge
- Compute dominators to identify loop headers

**Step 3: CFG → Structured AST**
- Pattern-match structured constructs from the CFG:
  - **if**: block ends with `jumpIfFalse(cond, endLabel)` → block → `endLabel`
  - **if-else**: `jumpIfFalse(cond, elseLabel)` → ifBlock → `jump(endLabel)` → `elseLabel` → elseBlock → `endLabel`
  - **if-elseif-else**: chain of the above
  - **while**: back-edge target has `jumpIfFalse(cond, exitLabel)` at top
  - **do-while**: back-edge with condition at bottom
  - **break/continue**: jumps to loop exit/header within a loop body
- Irreducible control flow (goto): fall back to labeled jumps

**Step 4: AST → Text**
- Pretty-print the structured AST with proper indentation
- Resolve macro types for known function parameters (pokemon IDs → names, etc.)
- Output function signatures, global declarations, string table references
- Syntax determined by formatter implementation (Swift or Python)

### Compiler Pipeline

```
Text
  → Lexer (tokens)
    → Parser (AST)
      → IR (lower control flow to jumps)
        → Bytecode (encode instructions)
          → SCD binary (build all sections)
```

**Lexer:** Regex-based tokenizer producing typed tokens:
- Keywords: `if`, `else`, `while`, `function`/`def`, `return`, `var`, `global`
- Identifiers, integers (decimal/hex), floats, quoted strings
- Operators: `+`, `-`, `*`, `/`, `%`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `!`, `and`, `or`
- Punctuation: `(`, `)`, `{`, `}`, `:`, `,`, `=`, `.`

**Parser:** Recursive descent with operator precedence climbing for expressions.

**IR lowering:**
- `if(cond) { A }` → eval cond → jumpIfFalse(end) → A → end:
- `if(cond) { A } else { B }` → eval cond → jumpIfFalse(else) → A → jump(end) → else: → B → end:
- `while(cond) { A }` → loop: → eval cond → jumpIfFalse(exit) → A → jump(loop) → exit:
- Function calls → push args → call/callStandard
- Assignments → eval expr → setVariable

---

## Output Syntax

Per-project setting in `GoddessSettings` controls whether decompiled scripts use **Python-subset** or **Swift-subset** syntax. Both parse to the same AST — only the formatter and lexer differ.

### Swift-subset

```swift
func character_0_interact() {
    if Flag.get(.talkedToLady) {
        Character.talk(.normal, msg(3))
    } else {
        Character.talk(.normal, msg(2))
        Flag.set(.talkedToLady, true)
    }
}
```

### Python-subset

```python
def character_0_interact():
    if Flag.get(talkedToLady):
        Character.talk(NORMAL, msg(3))
    else:
        Character.talk(NORMAL, msg(2))
        Flag.set(talkedToLady, True)
```

### Common Elements

Both syntaxes use **method-style** dot notation on class names for built-in calls: `Character.talk(...)`, `Flag.get(...)`, `Camera.setAngle(...)`.

Key differences between syntaxes:
- Function declaration: `func name()` vs `def name():`
- Block delimiters: `{ }` vs `:` + indentation
- Enum values: `.camelCase` vs `UPPER_SNAKE` or bare names
- Booleans: `true`/`false` vs `True`/`False`

The formatter and lexer are pluggable via a `ScriptSyntax` protocol with `.swift` and `.python` implementations.

---

## Script Class Definitions

Configurable via XD engine data. Class/method definitions are loaded from JSON files in the engine's `Constants/` directory, not hardcoded:

```
Engines/XD Engine/
  Constants/
    ScriptClasses/
      Standard.json         — class 0: pause, yield, getFlag, setFlag...
      Character.json        — class 35: talk, walk, setPosition...
      Pokemon.json          — class 37: ...
      Camera.json           — class 33: ...
      ...
    ScriptOperators.json    — operator definitions
```

This means:
- Different game versions can have different class definitions
- Users can add/correct definitions without code changes
- The engine ships with XD defaults

### Definition Structure

```swift
struct ScriptClassDef: Codable {
    let id: Int
    let name: String
    let methods: [ScriptMethodDef]
}

struct ScriptMethodDef: Codable {
    let id: Int
    let name: String
    let parameters: [ScriptParameterDef]
    let returnType: String?
}

struct ScriptParameterDef: Codable {
    let name: String
    let type: String  // macro type name
}
```

### Key Classes

| ID | Name | Methods | Purpose |
|----|------|---------|---------|
| 0 | Standard | ~70 | Core functions (flags, variables, timers, arrays) |
| 33 | Camera | ~20 | Camera control |
| 35 | Character | ~35 | NPC movement, animation, dialogue |
| 37 | Pokemon | ~30 | Pokemon data queries |
| 38 | Map | ~15 | Map/room operations |
| 39 | Tasks | ~10 | Thread/task management |
| 40 | Menu | ~20 | UI menus and prompts |
| 42 | Battle | ~25 | Battle initiation and configuration |
| 43 | Player | ~15 | Player character control |
| 47 | Sound | ~15 | Music and sound effects |

---

## GODSDK Operations

```swift
case scriptDecompile(config: ScriptDecompile.Config)
case scriptCompile(config: ScriptCompile.Config)
```

### ScriptDecompile.Config

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| scripts | [File] | all SCD files | List of SCD files to decompile |
| outputFolder | Folder | required | Where to write decompiled text files |
| xdEngine | Folder | required | Engine folder with class definitions |

Syntax comes from `GoddessSettings.scriptSyntax` (`.swift` or `.python`).

### ScriptCompile.Config

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| scripts | [File] | all in output folder | List of script text files to compile |
| outputFolder | Folder | required | Where to write compiled SCD files |
| xdEngine | Folder | required | Engine folder with class definitions |

Default behavior: decompile/compile ALL scripts found in the project.

---

## Implementation Order

1. **ScriptOpcode + ScriptInstruction + ScriptConstant** — instruction encoding/decoding with unit tests
2. **SCDScript** — SCD file format parse/serialize with round-trip tests
3. **ScriptIR** — decoded instruction sequences grouped by function
4. **ControlFlowGraph** — basic blocks and edge classification
5. **StructuredAST** — control flow pattern matching
6. **ASTFormatter** — text output (Swift syntax first, Python second)
7. **ScriptClassDefs** — built-in function/class definitions (JSON-driven)
8. **Lexer** — regex-based tokenizer with tests
9. **Parser** — recursive descent with tests
10. **Compiler** — AST → IR → bytecode → SCD
11. **GODSDK operations** — thin wrappers
12. **Round-trip validation** — decompile real XD scripts → compile → compare bytecode

## Verification

1. **Instruction round-trip:** encode → decode → re-encode = identical bytes
2. **SCD round-trip:** parse → serialize = identical file
3. **Decompile → compile round-trip:** SCD → text → SCD → compare bytecode
4. **Control flow:** manually verify if/else/while detection on known scripts
5. **Unit tests:** instruction encoding, lexer tokens, parser AST, CFG construction
6. **Integration:** decompile all XD map scripts, verify no crashes, compile back

---

## Reference (Old Tool)

The legacy implementation spans ~10K lines across these files:

| File | Lines | Purpose |
|------|-------|---------|
| `XGScript.swift` | 2490 | SCD format parsing, decompilation flow |
| `XDSScriptCompiler.swift` | 1069 | Compilation flow |
| `XDSExpr.swift` | 1716 | Expression tree representation |
| `XGScriptClassFunctionsData.swift` | 841 | Class/function definitions and operators |
| `XGScriptInstruction.swift` | 319 | Instruction encoding/decoding |
| `XDSExtensions.swift` | 1854 | Tokenization and parsing extensions |
| `XDSMacroTypes.swift` | 490 | Type annotation system |
| `XDSConstant.swift` | 276 | Constant types and values |
| `XGScriptOps.swift` | 91 | Opcode enumeration |

Known issues in old tool:
- While loops: `// TODO: if else statements, while loops` — not fully implemented
- Else-if chains: not detected, output as nested if/else
- Tokenizer: string splitting instead of regex — fragile
- Character data: `//TODO: complete handle assignments character data`
- Some built-in functions marked as "possibly broken" or "buggy"
