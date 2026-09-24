# swift-png (vendored)

Verbatim copy of [tayloraswift/swift-png](https://github.com/tayloraswift/swift-png)
**4.5.1** (`8a0bcd4df5e4b307c804937776a56dd6ecdf6396`), Apache 2.0 — see `LICENSE`.
Only the `LZ77` and `PNG` targets are here; the documentation catalogues,
tests and benchmarks are not.

## Why it is vendored rather than depended on

One local patch, in `LZ77/Deflator/LZ77.DeflatorBuffers.Stream.swift`.
Upstream's `compressBlocks(final:)` decides the final DEFLATE block type from
the leftover input count alone:

```swift
switch self.input.count {
case 3...:  while let _ = self.compress(all: true) { self.writeBlock() }
            finalType = .dynamic
case let count:
            finalType = .bytes(count: count)     // 0, 1 or 2 bytes
}
```

When the matcher stops with 0-2 bytes still queued, the second branch emits a
final *stored* block holding just those bytes and never calls
`writeBlock(final:)` — so every term already accumulated in the match buffer is
dropped, as are the last 3 bytes sitting in the window pipeline. The stream is
structurally valid and carries the Adler-32 of the *whole* input, so the only
symptom is that it fails its own checksum when read back.

Measured on `D2_magma_3_005` (Colosseum JP font atlas, 61,520 filtered bytes,
level 0): the final flush arrives with `input.count == 1`, 58,503 bytes have
been written, 3,013 bytes of terms are pending — and are discarded. A GS flash
menu texture (280x32 RGBA) lost all but 1 byte of 35,872, because its first
block boundary had not been reached.

Which images this hits is a function of where the matcher happens to stop, so
it varies with the compression level *and* with the caller's chunk sizes, with
no pattern: of three real failing images the failing levels were {0,1,2,3},
{5,6,7} and {0,1}. There is no safe level, and no cheap way to detect the
result — hence the patch rather than a workaround.

Patched: **0 failures** across 3,509 real images x levels 0-7, and the two
reproducers encode correctly at all 14 levels. The patch is byte-for-byte inert
on streams that were already complete: corpus output totals are identical at
every level that had no failure.

## Re-syncing with upstream

`master` as of 2026-09-16 (39 commits past 4.5.1) has no changes under
`Sources/LZ77`, so there is nothing to pick up. When there is: copy
`Sources/LZ77` and `Sources/PNG` over this folder, drop the `docs.docc`
catalogues, and re-apply the patch (search for "GoD-Tool patch"). Then run
`PNGEncoderTests`, which pins both reproducers.
