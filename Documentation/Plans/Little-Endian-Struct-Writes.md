# Plan: Little-Endian Struct Writes

**Status:** proposed (do after the current error-hardening pass lands).
**Scope:** `Sources/Shared/Dependencies/Structs/` only. No engine changes.
**Goal:** make the binary struct read/write/encode/decode paths correct for
little-endian fields, so the system is genuinely game-general (all current
targets — GameCube/Wii — are big-endian, so LE is currently unexercised and
several paths are silently BE-only).

## Why now / why it matters

`Environment.byteOrder` and every `StructData` accessor already thread a
`byteOrder`, and the JSON decode path (`writeInteger`, below) is already
byte-order-correct — so the infrastructure is 90% there. But the mutation
and read paths hard-code big-endian assumptions. A future DS/3DS/PC title
(or any LE structure) would read and write garbage. This is a
correctness-generality gap, not a round-trip concern.

## The one correct primitive we already have

`StructData.writeInteger(_:width:signed:into:atOffset:byteOrder:)`
(`StructData.swift:1005-1025`) is width-explicit and endian-clean:

```swift
let unsigned = UInt64(bitPattern: Int64(value))
for i in 0..<width {
    let shift = (byteOrder == .big) ? (width - 1 - i) * 8 : i * 8
    bytes[i] = UInt8((unsigned >> shift) & 0xFF)
}
```

It is currently `private static` and only used by JSON `populate`/`writeValue`.
**The plan is to make this (plus a mirror `readInteger`) the single code path
for every integer store and load**, and delete the hand-rolled variants.

## Defects to fix (all BE-only today)

1. **`set(_:to: GoDData?)`** (`StructData.swift:261-285`) — truncates an
   over-wide value by deleting `wordSize` chunks from index 0, then a partial
   run. This drops the *high* bytes (correct for BE) but on LE the significant
   bytes are at the front, so e.g. `set` of `Int 5` into a 2-byte LE field
   yields `[0,0]`. The grow branch `prepend`s zero-padding (wrong side for LE —
   should append). Verified BE-correct, LE-broken.
2. **int24/uint24 read** (`get -> Int?`, `:193-200`) — sign byte read at index 0
   and fill inserted at index 0; correct only for BE. LE int24 gets wrong sign
   and magnitude.
3. **int24/uint24 encode** (`encode`'s `readInt`, `:373-376`) — writes the 3
   field bytes at `address: 1` of a 4-byte buffer and reads `Int32`, so negative
   int24 zero-extends (encodes as large positive) *and* bakes in BE placement.
   `get` and `encode` also disagree on int24 interpretation.
4. **Booleans** (`:576-578`, array `:447-454`) — collapse any non-zero to `true`
   and write `0x01`; a flag byte carrying other bits (`0x02`, `0xFF`) is not
   preserved. Orthogonal to endianness but part of the same "store the real
   bytes" cleanup.
5. **uint64 / full-range uint32** (`encode` `:379`, `coerceToInt` `:1064`) —
   round-tripped through JSON numbers → `Double` (53-bit) rounding above 2^53.

## Work items

### 1. Promote the canonical integer path
- Expose an instance-level `writeInteger(_ value: Int, width: Int, signed: Bool, atOffset: Int)` and `readInteger(width: Int, signed: Bool, atOffset: Int) -> Int` on `StructData` (or on `GoDData`), both using the `writeInteger` shift formula, keyed off `self.byteOrder`.
- `readInteger` sign-extends from the top bit **in the field's byte order** (top byte is the last byte for LE, first for BE), covering widths 1/2/3/4/8 uniformly — this subsumes the special int24 code.

### 2. Rewrite the mutation API on top of it
- `set(_:to: Int?)` / `set(_:to: Enum.Case?)`: resolve the property's width + signedness, call `writeInteger(...)` directly. Delete the `wordSize`/chunk-deletion block in `set(_:to: GoDData?)` entirely.
- Keep a separate raw-bytes `set(_:to: GoDData?)` for non-integer fields (strings, sub-structs, raw arrays) that writes exactly `length` bytes, padding/truncating on the correct side per byte order (or, better, reject size mismatches for those).

### 3. Route read + encode through `readInteger`
- `get(_:) -> Int?` integer/enum cases → `readInteger`.
- `encode`'s `readInt` → `readInteger`. This makes `get` and `encode` agree by construction and removes the `address: 1` int24 hack.

### 4. Booleans: preserve the raw byte
- Store/emit the underlying byte value rather than normalizing to 0/1. Options: (a) treat `.boolean` as a 1-byte integer that JSON-encodes as `true`/`false` but preserves any non-{0,1} byte via a numeric fallback, or (b) add a strict raw-byte type. Prefer (a) for minimal schema churn.

### 5. Lossless large integers
- Add a `lossless_integer` treatment mirroring the existing `LosslessFloat/Double` string-wrapper: encode uint64 (and optionally full-range uint32) as a decimal string in JSON so `JSONSerialization`'s Double path can't round it. `coerceToInt` already accepts `String`.

### 6. (Recommended) Single-source the layout walk
- The cStyle alignment/offset computation is duplicated in four places
  (`StructDefiniton.swift:35-58, 129-154`; `StructData.swift:515-523, 733-741`).
  Extract one `layout() -> [(property, offset)]` and consume it everywhere so
  offset math can't diverge across read/write/encode/decode once LE is in play.

## Test strategy (this is the real proof, since no LE game exists yet)
- Add `GoDStructTests` cases building synthetic struct maps read/written with `byteOrder: .little`:
  - Round-trip each width (8/16/24/32/64) signed + unsigned, incl. negative int24 and values that exercise the sign bit and the >2^53 range.
  - Assert exact byte layout for a known value (e.g. LE u16 `5` → `[0x05, 0x00]`).
  - Boolean field carrying `0xFF` preserves `0xFF` through encode→decode.
- Re-run the existing BE tests unchanged to prove no regression.

## Sequencing & estimate
- Isolated to the Structs module; no engine/operation changes.
- ~1 focused session. Do it after the trap→throw hardening so the refactor lands on already-hardened code. Cross-references audit findings C3/C4/C5/C6/C14 and struct-audit #1/#2/#8/#14.
