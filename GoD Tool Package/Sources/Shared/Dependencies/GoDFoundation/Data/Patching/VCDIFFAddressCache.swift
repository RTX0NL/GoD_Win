//
//  VCDIFFAddressCache.swift
//
//  The near and same caches of RFC 3284 §5.3.
//
//  A COPY's address is usually close to the last one, or exactly one seen
//  before, so the format can spell it as "near address 2 plus 40" or "the same
//  address as this byte's slot" instead of an absolute integer. Both caches are
//  reset per target window, and **both are updated after every address
//  whatever mode it used** — a decoder that only updates them for cache modes
//  drifts out of step with the encoder and then decodes addresses that are
//  wrong but plausible.
//

import Foundation

struct VCDIFFAddressCache {

    private var near: [Int]
    private var same: [Int]
    private var nextSlot = 0

    init(nearSize: Int = VCDIFFCodeTable.nearCacheSize, sameSize: Int = VCDIFFCodeTable.sameCacheSize) {
        self.near = [Int](repeating: 0, count: nearSize)
        self.same = [Int](repeating: 0, count: sameSize * 256)
    }

    mutating func reset() {
        for index in near.indices { near[index] = 0 }
        for index in same.indices { same[index] = 0 }
        nextSlot = 0
    }

    /// Decode one address.
    ///
    /// - Parameters:
    ///   - mode: the COPY's mode, from the code table.
    ///   - here: the current position in the window's address space — the
    ///     source segment's length plus however much of the target window has
    ///     been written.
    ///   - nextInteger: reads an integer from the addresses section.
    ///   - nextByte: reads one byte from the addresses section.
    mutating func decodeAddress(
        mode: Int,
        here: Int,
        nextInteger: () throws -> Int,
        nextByte: () throws -> UInt8
    ) throws -> Int {
        let address: Int
        switch mode {
        case 0:
            address = try nextInteger()
        case 1:
            address = here - (try nextInteger())
        case 2 ..< (2 + near.count):
            address = near[mode - 2] + (try nextInteger())
        default:
            let row = mode - (2 + near.count)
            guard row >= 0, row < same.count / 256 else {
                throw VCDIFFIntegerError.overflow
            }
            address = same[row * 256 + Int(try nextByte())]
        }
        update(address)
        return address
    }

    mutating func update(_ address: Int) {
        if !near.isEmpty {
            near[nextSlot] = address
            nextSlot = (nextSlot + 1) % near.count
        }
        if !same.isEmpty {
            same[address % same.count] = address
        }
    }
}
