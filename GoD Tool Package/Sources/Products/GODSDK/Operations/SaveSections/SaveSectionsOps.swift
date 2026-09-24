import GoDFoundation
import GoDEngine
import Structs

/// Decomposes a save section's raw bytes into typed sub-artifacts, and puts
/// them back.
///
/// The save dump and build stay deliberately dumb about sub-structure: a
/// section they can't type is one `.bin`. This pair sits either side of them —
/// `saveSectionsDump` runs after the save dump and decomposes, `saveSectionsBuild`
/// runs before the save build and recomposes — so the raw binary is never
/// deleted and is always regenerated from the artifacts before the build reads
/// it.
///
/// The split exists because some sections aren't describable by a section type
/// at all. XD's flag section needs a descriptor table from `common.rel` to know
/// where one flag ends and the next begins; Colosseum's flags sit at an offset
/// *inside* a larger section. Both are byte ranges within a section, which is
/// what `SectionLayout` describes.
enum SaveSectionsOps {

    /// Name of the folder a decomposed section's artifacts go into: the
    /// section artifact's stem. The artifact itself stays beside it, so the
    /// extension has to come off whether the section dumped as `.bin` (XD's
    /// flags) or `.json` (Colosseum's typed `Tail`) — leaving it on would ask
    /// for a folder named exactly like the file next to it.
    static func artifactFolderName(forBinary binary: String) -> String {
        for ext in [".bin", ".json", ".csv"] where binary.hasSuffix(ext) {
            return String(binary.dropLast(ext.count))
        }
        return binary
    }

    /// Bytes no chunk claims are kept verbatim in files named for their offset,
    /// so a partial layout loses nothing and the rebuild can place them again
    /// without a manifest.
    static func gapFilename(offset: Int) -> String {
        String(format: "gap-%06X.bin", offset)
    }

    static func gapOffset(of filename: String) -> Int? {
        guard filename.hasPrefix("gap-"), filename.hasSuffix(".bin") else { return nil }
        let hex = filename.dropFirst(4).dropLast(4)
        return Int(hex, radix: 16)
    }

    /// One region of a section, resolved against the section's real length.
    struct ResolvedChunk {
        let chunk: SectionLayout.Chunk
        let offset: Int
        let length: Int
    }

    /// Orders a section's chunks by offset and works out each one's length,
    /// rejecting anything that overlaps or runs past the section — a layout
    /// that does either would silently corrupt a neighbour.
    static func resolve(
        _ section: SectionLayout.Section,
        sectionLength: Int,
        engine: GenericEngine,
        sectionName: String
    ) throws -> [ResolvedChunk] {
        var resolved: [ResolvedChunk] = []
        // Field-addressed flag chunks live inside a typed section's artifact,
        // not in a byte range, so they take no part in the offset arithmetic.
        for chunk in section.chunks.filter({ !$0.isFieldAddressed }).sorted(by: { $0.offset < $1.offset }) {
            let length: Int
            switch chunk {
            case .flags(let c):
                length = c.length
            case .structInstance(let c):
                guard let definition = try? engine.getStruct(c.type) as StructDefinition else {
                    throw SaveSectionsOpsErrors.unresolvedStruct(type: c.type, chunk: c.name, .init())
                }
                length = definition.length
            case .table(let c):
                guard let definition = try? engine.getStruct(c.type) as StructDefinition else {
                    throw SaveSectionsOpsErrors.unresolvedStruct(type: c.type, chunk: c.name, .init())
                }
                length = definition.length * c.count
            }
            guard chunk.offset >= 0, length > 0, chunk.offset + length <= sectionLength else {
                throw SaveSectionsOpsErrors.chunkOutOfBounds(
                    section: sectionName, chunk: chunk.name,
                    offset: chunk.offset, length: length, sectionLength: sectionLength, .init()
                )
            }
            if let previous = resolved.last, chunk.offset < previous.offset + previous.length {
                throw SaveSectionsOpsErrors.overlappingChunks(
                    section: sectionName, first: previous.chunk.name, second: chunk.name, .init()
                )
            }
            resolved.append(ResolvedChunk(chunk: chunk, offset: chunk.offset, length: length))
        }
        return resolved
    }

    /// The chunks addressed by field rather than byte range.
    static func fieldChunks(_ section: SectionLayout.Section) -> [SectionLayout.Chunk] {
        section.chunks.filter(\.isFieldAddressed)
    }

    /// The runs of a section no chunk claims, as (offset, length).
    static func gaps(around chunks: [ResolvedChunk], sectionLength: Int) -> [(offset: Int, length: Int)] {
        var result: [(Int, Int)] = []
        var cursor = 0
        for chunk in chunks {
            if chunk.offset > cursor { result.append((cursor, chunk.offset - cursor)) }
            cursor = chunk.offset + chunk.length
        }
        if cursor < sectionLength { result.append((cursor, sectionLength - cursor)) }
        return result
    }
}
