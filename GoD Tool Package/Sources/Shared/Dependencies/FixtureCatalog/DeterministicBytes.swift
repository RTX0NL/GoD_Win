//
//  DeterministicBytes.swift
//
//  A seeded LCG byte generator so fixture payloads are non-trivial but
//  reproducible — regenerating a fixture twice yields identical bytes.
//  Matches the LCG constants already used in XDSaveSlotTests.
//

import Foundation

/// `count` pseudo-random bytes from a seeded LCG. Deterministic: same seed
/// and count always produce the same bytes.
public func deterministicBytes(_ count: Int, seed: UInt32 = 0x1234_5678) -> [UInt8] {
    var rng = seed
    var out: [UInt8] = []
    out.reserveCapacity(count)
    for _ in 0..<count {
        rng = rng &* 1_664_525 &+ 1_013_904_223
        out.append(UInt8(truncatingIfNeeded: rng >> 24))
    }
    return out
}
