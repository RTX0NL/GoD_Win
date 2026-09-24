//
//  SaveCard.swift
//
//  How a Genius Sonority save's memory-card body divides up, and the
//  checksum the game keeps over its metadata.
//
//  The banner, icon and comments are console-level and derive from the
//  save's own directory entry, so nothing about them is declared here.
//  What can't be derived is where the game's save slots start: XD's two
//  slots sit at 0x6000 and 0x2E000 and Colosseum's three at 0x6000,
//  0x24000 and 0x42000, and no rule in the card format says so.
//
//  See `Documentation/File Formats/Shared/GCI - GameCube Memory Card Save.md`.
//

import Foundation
import GameCube

public extension GeniusSonorityEngine.Data {

    /// A game's save-card body shape.
    ///
    /// Optional on `Data` because Battle Revolution has none — a Wii
    /// title saves to NAND, not a GameCube memory card, so there is no
    /// `.gci` shape to describe. An engine without one falls back to the
    /// derived layout, which finds the card metadata but leaves the
    /// game's own data unsplit.
    struct SaveCard: Codable, Equatable {
        /// Total body length this shape describes. A save whose body is a
        /// different size isn't this shape and must not be split by it.
        public var bodyLength: Int
        public var regions: [CardSaveLayout.Region]
        public var integrity: [CardIntegrityRule]

        public init(
            bodyLength: Int,
            regions: [CardSaveLayout.Region],
            integrity: [CardIntegrityRule]
        ) {
            self.bodyLength = bodyLength
            self.regions = regions
            self.integrity = integrity
        }
    }

    /// The metadata region both games share: comments at 0, images from
    /// 0x40 to 0x3A40, the checksum word, then zero to the slots.
    ///
    /// The region is 0x6000 rather than ending at the checksum because
    /// that is the unit the game writes — `_memcardJobMain__FUlUl` puts
    /// the whole 0x6000 down in one transfer — and because the trailing
    /// zeros have to belong to some region for the body to tile.
    static var geniusSonorityMetadataLength: Int { 0x6000 }

    /// XD and Colosseum both sum the first 0x3A40 bytes as big-endian
    /// words and store the result at 0x3A40. Verified on all 72 real
    /// saves across both games and all three regions. Editing a banner,
    /// an icon or a comment invalidates it, which is why the rebuild has
    /// to recompute it.
    static var geniusSonorityMetadataChecksum: CardIntegrityRule {
        .init(
            algorithm: .sumUInt32BigEndian,
            offset: 0,
            length: 0x3A40,
            storeAt: 0x3A40
        )
    }

    /// Pokémon XD: 0x56000 body, two 0x28000 slots.
    static var galeOfDarknessSaveCard: SaveCard {
        .init(
            bodyLength: 0x56000,
            regions: [
                .init(
                    name: "metadata", offset: 0,
                    length: geniusSonorityMetadataLength, kind: .cardMetadata
                ),
                .init(name: "slot-a", offset: 0x06000, length: 0x28000, kind: .gameData),
                .init(name: "slot-b", offset: 0x2E000, length: 0x28000, kind: .gameData),
            ],
            integrity: [geniusSonorityMetadataChecksum]
        )
    }

    /// Pokémon Colosseum: 0x60000 body, three 0x1E000 slots.
    static var colosseumSaveCard: SaveCard {
        .init(
            bodyLength: 0x60000,
            regions: [
                .init(
                    name: "metadata", offset: 0,
                    length: geniusSonorityMetadataLength, kind: .cardMetadata
                ),
                .init(name: "slot-1", offset: 0x06000, length: 0x1E000, kind: .gameData),
                .init(name: "slot-2", offset: 0x24000, length: 0x1E000, kind: .gameData),
                .init(name: "slot-3", offset: 0x42000, length: 0x1E000, kind: .gameData),
            ],
            integrity: [geniusSonorityMetadataChecksum]
        )
    }
}
