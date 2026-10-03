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
}
