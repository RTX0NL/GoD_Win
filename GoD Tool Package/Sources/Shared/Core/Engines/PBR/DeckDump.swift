import Foundation
import GoDFoundation
import Structs

/// Decoding a `deck.fsys` table into its typed, editable form.
///
/// A deck file is a 0x10 header (`PBRDeckHeader`, entry count at +0x08) then
/// an entry array that tiles exactly — no string pool or name/relocation
/// regions, unlike `common.fsys`. Decks are addressed by FSYS file type.
public extension PBREngine {

    /// Deck descriptor for an FSYS file type (`dckp`/`dckt`/`dcka`).
    func deckTable(forType fileType: String) -> Data.DeckTable? {
        data.deckTables.first { $0.fileType == fileType }
    }

    /// Decode one `deck.fsys` table binary into its header and typed rows.
    ///
    /// - Parameter structs: the engine the entry struct resolves against —
    ///   see `typeCommonTable`. Deck entries name species, held items and
    ///   moves, so this is the same cross-engine case.
    func typeDeckTable(
        _ deck: Data.DeckTable,
        binary: GoDData,
        structs: any Engine
    ) throws -> (header: StructData, entries: [StructData], entryDefinition: StructDefinition) {
        binary.setByteOrder(.big)

        let headerDefinition = try structs.getStruct(data.deckHeaderStructName)
        let entryDefinition = try structs.getStruct(deck.structName)

        guard entryDefinition.length == deck.entrySize else {
            throw CommonTableError.entryStrideMismatch(
                table: deck.fileType, structName: deck.structName,
                structLength: entryDefinition.length, expected: deck.entrySize
            )
        }
        guard let headerBytes = binary.read(atAddress: 0, length: headerDefinition.length) else {
            throw CommonTableError.truncated(table: deck.fileType)
        }
        let header = StructData(definition: headerDefinition, data: headerBytes)
        guard let count: Int = header.get("entry_count") else {
            throw CommonTableError.truncated(table: deck.fileType)
        }

        var entries = [StructData]()
        entries.reserveCapacity(count)
        for i in 0 ..< count {
            let offset = headerDefinition.length + i * entryDefinition.length
            guard let rowBytes = binary.read(atAddress: offset, length: entryDefinition.length) else {
                throw CommonTableError.truncated(table: deck.fileType)
            }
            entries.append(StructData(definition: entryDefinition, data: rowBytes))
        }
        return (header, entries, entryDefinition)
    }
}
