//
//  VCDIFFCodeTable.swift
//
//  The default code table of RFC 3284, and the instruction model it encodes.
//
//  An instruction byte is an index into a 256-entry table, and each entry is up
//  to *two* instructions — which is the format's compression: the common
//  "a few new bytes then a copy" becomes one byte. A size of zero in the table
//  means the real size follows in the instruction stream.
//
//  The table is generated from the rules in the RFC rather than transcribed as
//  256 literal rows, because the rules are what the spec gives and a
//  transcription of this length is the kind of thing that is wrong in one place
//  for years. `VCDIFFCodeTableTests` pins the ranges, the counts and a sample
//  of entries against the spec's own description — the same treatment the Zstd
//  predefined tables get, and for the same reason: a subtly wrong table still
//  decodes most streams.
//
//  The index arithmetic is the check that the shape is right: 1 RUN + 18 ADD +
//  144 COPY (9 modes × 16) = 163, then 72 ADD+COPY (modes 0-5 × 4 add sizes ×
//  3 copy sizes) + 12 (modes 6-8 × 4 add sizes, copy size 4) = 247, then 9
//  COPY+ADD = 256.
//

import Foundation

enum VCDIFFInstructionType: Equatable {
    case noop
    case add
    case run
    case copy
}

struct VCDIFFInstruction: Equatable {
    let type: VCDIFFInstructionType
    /// Zero means the size is stored in the instruction stream.
    let size: Int
    /// Only meaningful for `copy`.
    let mode: Int

    static let noop = VCDIFFInstruction(type: .noop, size: 0, mode: 0)
}

enum VCDIFFCodeTable {

    /// Near-cache slots in the default table.
    static let nearCacheSize = 4
    /// Same-cache rows in the default table; each row is 256 wide.
    static let sameCacheSize = 3
    /// Modes 0 and 1 are SELF and HERE; the caches take the rest.
    static let modeCount = 2 + nearCacheSize + sameCacheSize

    /// `(first, second)` per code byte.
    static let `default`: [(VCDIFFInstruction, VCDIFFInstruction)] = {
        var table = [(VCDIFFInstruction, VCDIFFInstruction)]()
        table.reserveCapacity(256)

        // 0: RUN, size in the stream.
        table.append((VCDIFFInstruction(type: .run, size: 0, mode: 0), .noop))

        // 1-18: ADD — size in the stream, then sizes 1...17.
        table.append((VCDIFFInstruction(type: .add, size: 0, mode: 0), .noop))
        for size in 1 ... 17 {
            table.append((VCDIFFInstruction(type: .add, size: size, mode: 0), .noop))
        }

        // 19-162: COPY, per mode — size in the stream, then sizes 4...18.
        for mode in 0 ..< modeCount {
            table.append((VCDIFFInstruction(type: .copy, size: 0, mode: mode), .noop))
            for size in 4 ... 18 {
                table.append((VCDIFFInstruction(type: .copy, size: size, mode: mode), .noop))
            }
        }

        // 163-234: ADD then COPY, for the modes that pair with three copy sizes.
        for mode in 0 ... 5 {
            for addSize in 1 ... 4 {
                for copySize in 4 ... 6 {
                    table.append((
                        VCDIFFInstruction(type: .add, size: addSize, mode: 0),
                        VCDIFFInstruction(type: .copy, size: copySize, mode: mode)
                    ))
                }
            }
        }

        // 235-246: the same-cache modes pair with one copy size only.
        for mode in 6 ... 8 {
            for addSize in 1 ... 4 {
                table.append((
                    VCDIFFInstruction(type: .add, size: addSize, mode: 0),
                    VCDIFFInstruction(type: .copy, size: 4, mode: mode)
                ))
            }
        }

        // 247-255: COPY then ADD.
        for mode in 0 ..< modeCount {
            table.append((
                VCDIFFInstruction(type: .copy, size: 4, mode: mode),
                VCDIFFInstruction(type: .add, size: 1, mode: 0)
            ))
        }

        return table
    }()

    // MARK: - Codes the writer uses
    //
    // Only the three that take their size from the stream, which can express
    // any instruction at the cost of a few bytes. Addresses are written in mode
    // SELF, so nothing the writer emits depends on the caches' state.

    static let runWithExplicitSize = 0
    static let addWithExplicitSize = 1
    static let copySelfWithExplicitSize = 19
}
