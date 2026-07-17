import GoDFoundation

public extension RELFile {

    /// Canonical pointer-index → target table. Mirrors the chained
    /// numbering the legacy `Rel` parser produced (and that
    /// `RelDisassemblyOperation` rebuilds), so consumers downstream of
    /// the disassembler can ask "what does pointer index N reference?"
    /// without re-implementing the walk.
    ///
    /// Numbering rule: walk every relocation edge in the REL grouped by
    /// imported module, sorted within each group by source section then
    /// source offset. The first time a unique target tuple appears it
    /// gets the next free index; subsequent edges to the same target
    /// share that index.
    func pointerIndexTable() -> [Int: SymbolRef] {

        struct TargetKey: Hashable {
            let module: UInt32
            let section: UInt8
            let offset: UInt32
        }
        struct EdgeDescriptor {
            let key: TargetKey
            let sourceSection: UInt8
            let sourceOffset: UInt32
        }

        var allEdges: [EdgeDescriptor] = []
        for section in sections {
            switch section.body {
            case .text(let instructions):
                var off: UInt32 = 0
                for inst in instructions {
                    if let ref = inst.ref, let fixup = inst.fixup {
                        let inner: UInt32
                        switch fixup {
                        case .addr16, .addr16_lo, .addr16_hi, .addr16_ha: inner = 2
                        default: inner = 0
                        }
                        allEdges.append(EdgeDescriptor(
                            key: .init(module: ref.moduleID, section: ref.section, offset: ref.offset),
                            sourceSection: UInt8(section.index),
                            sourceOffset: off + inner
                        ))
                    }
                    off &+= 4
                }
            case .data(let chunks):
                var off: UInt32 = 0
                for chunk in chunks {
                    if case .pointer(let ref, _) = chunk {
                        allEdges.append(EdgeDescriptor(
                            key: .init(module: ref.moduleID, section: ref.section, offset: ref.offset),
                            sourceSection: UInt8(section.index),
                            sourceOffset: off
                        ))
                    }
                    off &+= UInt32(chunk.byteLength)
                }
            case .empty, .bss:
                continue
            }
        }

        var indexByTarget: [TargetKey: Int] = [:]
        var result: [Int: SymbolRef] = [:]
        var next = 0
        for mod in importedModules {
            let modEdges = allEdges
                .filter { $0.key.module == mod }
                .sorted {
                    if $0.sourceSection != $1.sourceSection { return $0.sourceSection < $1.sourceSection }
                    return $0.sourceOffset < $1.sourceOffset
                }
            for edge in modEdges where indexByTarget[edge.key] == nil {
                indexByTarget[edge.key] = next
                result[next] = SymbolRef(
                    moduleID: edge.key.module,
                    section: edge.key.section,
                    offset: edge.key.offset
                )
                next += 1
            }
        }
        return result
    }

    /// Reads a 16-bit big-endian signed integer at the given section
    /// offset. Walks the section's data chunks to land on the right byte
    /// — `.binary` chunks store raw bytes, `.pointer` chunks expand to
    /// their `restValue` for read-back. Returns nil if the target lies
    /// outside the section, in a non-data section, or in BSS/empty.
    func readInt16(atSelfRef ref: SymbolRef) -> Int16? {
        guard ref.moduleID == moduleID else { return nil }
        guard let section = sections.first(where: { $0.index == Int(ref.section) }) else { return nil }
        guard case .data(let chunks) = section.body else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(Int(section.size))
        for chunk in chunks {
            switch chunk {
            case .binary(let b):
                bytes.append(contentsOf: b)
            case .pointer(_, let restValue):
                bytes.append(UInt8((restValue >> 24) & 0xFF))
                bytes.append(UInt8((restValue >> 16) & 0xFF))
                bytes.append(UInt8((restValue >> 8) & 0xFF))
                bytes.append(UInt8(restValue & 0xFF))
            }
        }
        let off = Int(ref.offset)
        guard off + 2 <= bytes.count else { return nil }
        let raw = (UInt16(bytes[off]) << 8) | UInt16(bytes[off + 1])
        return Int16(bitPattern: raw)
    }

    /// Reads a 32-bit big-endian unsigned integer at the given section
    /// offset, treating `.pointer` chunks as their stored `restValue`.
    /// Used by the Colo map-type classifier to read the
    /// `numberOfEntryPoints` value referenced by pointer index 1's
    /// "value at pointer".
    func readUInt32(atSelfRef ref: SymbolRef) -> UInt32? {
        guard ref.moduleID == moduleID else { return nil }
        guard let section = sections.first(where: { $0.index == Int(ref.section) }) else { return nil }
        guard case .data(let chunks) = section.body else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(Int(section.size))
        for chunk in chunks {
            switch chunk {
            case .binary(let b):
                bytes.append(contentsOf: b)
            case .pointer(_, let restValue):
                bytes.append(UInt8((restValue >> 24) & 0xFF))
                bytes.append(UInt8((restValue >> 16) & 0xFF))
                bytes.append(UInt8((restValue >> 8) & 0xFF))
                bytes.append(UInt8(restValue & 0xFF))
            }
        }
        let off = Int(ref.offset)
        guard off + 4 <= bytes.count else { return nil }
        return (UInt32(bytes[off]) << 24)
            | (UInt32(bytes[off + 1]) << 16)
            | (UInt32(bytes[off + 2]) << 8)
            |  UInt32(bytes[off + 3])
    }

    /// Result of the Colosseum map REL angle-sentinel classifier
    /// (legacy `XGMapRel.swift:35-53`).
    enum ColosseumMapType: String {
        /// Standard layout — entry-point pointers at indices 1/2,
        /// character pointers at indices 3/4.
        case type1
        /// Alternate layout — entry-point pointers at indices 0/1,
        /// character pointers at indices 5/6.
        case type2
    }

    /// Classifies a Colosseum map REL by reading the half-word at
    /// pointer index 1's target. If it's one of the "expected angle"
    /// sentinels the legacy parser recognises (or ±360 wraparounds),
    /// the layout is Type 1; anything else, or a `numberOfEntryPoints`
    /// over the legacy cap of 20, means Type 2.
    ///
    /// Returns `.type1` as the conservative default when the pointer
    /// table is too sparse to read either field — better to assume the
    /// standard layout than misroute. Callers that care about
    /// detection failure should `pointerIndexTable()` directly.
    func classifyColosseumMap() -> ColosseumMapType {
        let pointers = pointerIndexTable()
        // Index 1 = FirstWarpEntryLocation in Type 1 (== FirstCharacter in Type 2).
        // Index 2 = NumberOfWarpEntryLocations in Type 1 (== NumberOfCharacters in Type 2).
        let entryRef = pointers[1]
        let countRef = pointers[2]

        // numberOfEntryPoints > 20 → Type 2. The "value at pointer index 2"
        // means: read the 32-bit word stored at the address pointer index
        // 2 references (i.e. dereference index 2).
        if let countRef, let count = readUInt32(atSelfRef: countRef), count > 20 {
            return .type2
        }

        guard let entryRef, let angle = readInt16(atSelfRef: entryRef) else {
            return .type1
        }

        switch angle {
        case 0, 45, -45, 90, -90, 120, -120, 180, -180, 270, -270:
            return .type1
        default:
            return .type2
        }
    }
}
