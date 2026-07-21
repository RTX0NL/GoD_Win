import GoDFoundation
import GoDEngine

public extension XDEngine {
    struct Data: Codable {

        /// 16 save-slot sections per PKHeX's `SAV3XD.cs`. Position in
        /// the array IS the in-slot TOC index — the same one
        /// `XDSaveSlot.subBlockOffset` resolves through
        /// `slot[0x40..0x80]`. The runtime reads each section's
        /// physical offset and length from the slot's own TOC, so
        /// the engine spec only carries name + type + (optional
        /// table count). Same taxonomy as the DOL/REL data-section
        /// chunk system: `.binary` for raw, `.struct` for typed
        /// instances, `.table` for typed runs.
        ///
        /// Identities resolved by matching the empirically observed
        /// on-card section sizes against the RAM `SystemSaveData` block
        /// sizes documented in the XD disassembly
        /// (`Overview/Save System.md` §2 + `Data Structures/
        /// SystemSaveData.md`). The correspondence is tight (e.g. phys 7
        /// = 0x2400 ≈ Shadow-Pokémon RAM block 0x2410; phys 15 = 0xC800 =
        /// AnywaySave 0xC800; phys 14 = 0x2298 ≈ Purification/Relive
        /// 0x22B0). Note two corrections to PKHeX's tentative names:
        /// index 7 is the global **Shadow Pokémon Status** table (not
        /// "ShadowInfo"), and index 14 is the **Purification** / Relic-
        /// Forest state (game symbol `Relive`, not "Purifier"). We use
        /// the English "Shadow Pokémon" term throughout, though the
        /// game's own symbols say "DarkPokemon" (Japanese). Indices 3
        /// and 9 are small opaque blocks not yet matched to a named RAM
        /// block; 8 is the composite flag-bank bundle (FlagLevel0/1/2 +
        /// ExRibbon, ≈0x6B4).
        public var saveSections: [SaveSectionSpec] = Self.defaultSaveSections

        static let defaultSaveSections: [SaveSectionSpec] = [
            .structInstance(name: "Config"),                    // 0  0x88   → XDSaveConfig (Gamedata)
            .structInstance(name: "Trainer"),                   // 1  0x978  → XDSaveTrainer (Hero)
            .structInstance(name: "PCBox"),                     // 2  0xBC50 → XDSavePCBox
            .binary(name: "Section3"),                          // 3  0x4A   (opaque small block)
            .structInstance(name: "Daycare"),                   // 4  0xCC   → XDSaveDaycare (Sodateya)
            .structInstance(name: "StrategyMemo"),              // 5  0x1774 → XDSaveStrategyMemo (PDA memos)
            .structInstance(name: "BattleMode"),                // 6  0x364  → XDSaveBattleMode (Taisen rule save; game symbol "_TOOL_SAVEDATA")
            .table(name: "ShadowStatusTable", count: 128),      // 7  0x2400 → 128 × ShadowPokemonStatus
            .binary(name: "Flags"),                             // 8  0x6B4  flag bit-banks: FlagLevel0(0x20)/1(0x80)/2(0x630-trunc)/ExRibbon(0x20). Raw chunk — decode via future flag op (descriptor table `flag_data` is in common.rel, 6B entries)
            .binary(name: "Section9"),                          // 9  0xB    (opaque tiny block)
            .binary(name: "Yobi1"),                             // 10 0x400  (reserved block 1)
            .binary(name: "Yobi2"),                             // 11 0x800  (reserved block 2)
            .binary(name: "Yobi3"),                             // 12 0x1000 (reserved block 3)
            .binary(name: "Yobi4"),                             // 13 0x2000 (reserved block 4)
            .binary(name: "Purification"),                      // 14 0x2298 (Relic Forest / Purify Chamber state; game symbol "Relive")
            .binary(name: "CurrentMapState"),                   // 15 0xC800 (save-anywhere snapshot; game symbol "AnywaySave")
        ]

        /// Section index → registered struct definition name. The
        /// authoritative source-of-truth for which sections get
        /// parsed into JSON via `StructData`. Mod authors override
        /// this to wire new struct definitions to existing or
        /// new section indices without redeclaring `saveSections`;
        /// removing an entry reverts that section to a raw `.bin`
        /// dump (XD reads length from the slot's TOC regardless,
        /// so the binding is JSON-only for XD).
        ///
        /// Lookup is purely by index, so this works with arbitrary
        /// mod-added sections too — adding `15: "MyModStruct"` is
        /// enough to make section 15 dump as JSON, provided the
        /// struct is also registered in `engine.structs`.
        public var sectionStructTypes: [Int: String] = Self.defaultSectionStructTypes

        static let defaultSectionStructTypes: [Int: String] = [
            0: "XDSaveConfig",
            1: "XDSaveTrainer",
            2: "XDSavePCBox",
            4: "XDSaveDaycare",
            5: "XDSaveStrategyMemo",
            6: "XDSaveBattleMode",
            7: "ShadowPokemonStatus",
        ]

        /// Slot-format TOC table offsets (size table, offset table, body
        /// base). Defaults to the retail XD format. The sub-block *count*
        /// is NOT stored here — it's derived from `saveSections.count`,
        /// so adding a section spec is enough. A ROM mod that adds sub-
        /// blocks also sets these offsets (and must patch the game's own
        /// save code to match). See `XDSaveSlot.Layout`.
        public var saveSlotLayout: XDSaveSlot.Layout = .stock


        /// Name of the FSYS archive containing deck data (without .fsys extension)
        public var decksFsys: String = "deck_archive"

        /// Per-deck routing — output folders + EU dedup behaviour. Drives
        /// where the trainer dump op writes each deck's data and how the
        /// FSYS dump aliases `_eu` variants to their base entries.
        public var decks: Decks = Decks()

        /// Property names on the deck struct rows that the trainer dump
        /// op uses to walk references between sections. Configurable so
        /// renames in the StructMaps above don't desync silently.
        public var deckTrainerPokemonIndexesProperty: String = "pokemonIndexes"
        public var deckTrainerAIIndexProperty: String = "aiIndex"
        public var deckTrainerShadowMaskProperty: String = "shadowMask"

        /// Cap on the number of `DeckShadowPokemon` (DDPK) slots. The
        /// 128 default is doubly-binding: the save format reserves
        /// 128 slots, AND the runtime accessor `deckGetDeckDarkPokemon`
        /// hardcodes the same bound — `cmplwi r3, 0x80; bge → NULL`
        /// — so going past it both corrupts saves and gets the index
        /// silently dropped at lookup time.
        ///
        /// Note: shadow references are NOT exclusive to DeckStory. The
        /// disassembly confirms every `_fightTrainerCreateDeck*`
        /// variant (Normal / Virtual / UnderTaker / UnderTakerIn-
        /// Colosseum / WildPoke / Pokemon) calls
        /// `DeckTrainer::getDarkPokemonDataID`, which reads the same
        /// `shadowMask` byte for any deck's trainer. The dump op must
        /// walk every routed deck file to discover used DDPK ids — the
        /// global union across all decks defines what's referenced.
        ///
        /// On dump: DDPK rows that no trainer references are silently
        /// skipped (they don't correspond to a meaningfully editable
        /// trainer-side state).
        ///
        /// On rebuild: the DDPK section is padded out to exactly this
        /// many entries. Indexes that the rebuild's trainer JSONs claim
        /// are written; any remaining slot up to the cap is emitted as
        /// a zero-filled row so save-file indexes still resolve.
        public var darkPokemonSaveSlotLimit: Int = 128

        public struct Decks: Codable {
            /// Output folders per trainer deck file (FSYS entry basename
            /// → folder under the project root). Defaults route each
            /// deck under `Source/Data/Decks/<ClearName>` using
            /// colloquial names. `DeckData_DarkPokemon` deliberately
            /// has no entry here — the shadow pokémon section is
            /// consumed by the trainer dump op (referenced rows get
            /// inlined into trainer JSONs; unreferenced rows are
            /// dropped) and rebuilt from those JSONs + the
            /// `darkPokemonSaveSlotLimit` cap on the parent `Data`.
            public var routing: [String: Folder] = Decks.defaultRouting

            /// FSYS entry basename for the shadow pokémon deck. The
            /// trainer dump op reads this entry to find DDPK rows that
            /// trainers reference; everything else about that file is
            /// regenerated at rebuild time.
            public var darkPokemonFsysEntry: String = "DeckData_DarkPokemon"

            /// When true (default), entries whose name ends in `_eu`
            /// share their on-disk file with the base variant — both
            /// FSYS registry entries point at the same path. Set false
            /// to give each region its own dump.
            public var mergeEURegionDecks: Bool = true

            public init(
                routing: [String: Folder]? = nil,
                darkPokemonFsysEntry: String = "DeckData_DarkPokemon",
                mergeEURegionDecks: Bool = true
            ) {
                self.routing = routing ?? Decks.defaultRouting
                self.darkPokemonFsysEntry = darkPokemonFsysEntry
                self.mergeEURegionDecks = mergeEURegionDecks
            }

            public static let defaultRouting: [String: Folder] = [
                "DeckData_Story":       "/Source/Data/Decks/Story",
                "DeckData_Colosseum":   "/Source/Data/Decks/Colosseum",
                "DeckData_Hundred":     "/Source/Data/Decks/MtBattle",
                "DeckData_Bingo":       "/Source/Data/Decks/Bingo",
                "DeckData_Virtual":     "/Source/Data/Decks/VirtualTrainer",
                "DeckData_Imasugu":     "/Source/Data/Decks/Imasugu",
                "DeckData_Sample":      "/Source/Data/Decks/Sample",
            ]
        }

        /// Filesystem paths (relative to the engine folder) for the
        /// bundled reference resources: REL typemap, symbol indexes, and
        /// per-region DOL symbol maps. Consumers (disassembler ops)
        /// resolve these against the engine folder and read through the
        /// shared `FileSystemTree`, so users can edit the files in the
        /// project and the tool picks up the changes.
        public var resources: Resources = Resources()

        /// XD ships with a small number of leftover Colosseum-format map
        /// REL files that don't match the final XD map layout (e.g.
        /// names starting with `B1_`, `M1_cave_`). Maps whose filename
        /// starts with any of these prefixes are routed to a dedicated
        /// "unused" output folder and skipped by the typemap-driven
        /// disassembly path. The list is intentionally short until we
        /// audit a real XD ISO; extend as more are discovered.
        public var unusedColosseumMapPrefixes: [String] = ["B1_", "M1_"]

        public struct Resources: Codable {
            /// Pointer index → symbol name for common.rel.
            public var commonRelSymbolMap: File = "Resources/common_rel_symbols.json"
            /// Pointer index → chunk type (table/function/etc.) for common.rel.
            public var commonRelTypeMap: File = "Resources/common_rel_typemap.json"
            /// Pointer index → symbol name for map.rel.
            public var mapRelSymbolMap: File = "Resources/map_rel_symbols.json"
            /// Typed regions for map .rel files. Single map (one layout
            /// across all XD maps; the unused-prefix maps don't follow
            /// it and are routed elsewhere).
            public var mapRelTypeMap: File = "Resources/map_rel_typemap.json"
            /// Pointer index → symbol name for pocket_menu.rel.
            public var pocketMenuSymbolMap: File = "Resources/pocket_menu_symbols.json"
            /// Relative path of the DOL symbol map for this project. The
            /// engine bundles the US map as the default so the file is
            /// always populated; `ProjectSetup` overwrites it with the
            /// region-specific map when the ROM isn't US. One file, one
            /// path — downstream ops never need to know about regions.
            public var dolSymbolMap: File = "Resources/dol.map"
            /// Typed regions within the main.dol data sections (struct tables
            /// and embedded MSG files). US addresses; regenerate per region.
            public var dolTypeMap: File = "Resources/dol_typemap.json"

            public init(
                commonRelSymbolMap: File = "Resources/common_rel_symbols.json",
                commonRelTypeMap: File = "Resources/common_rel_typemap.json",
                mapRelSymbolMap: File = "Resources/map_rel_symbols.json",
                mapRelTypeMap: File = "Resources/map_rel_typemap.json",
                pocketMenuSymbolMap: File = "Resources/pocket_menu_symbols.json",
                dolSymbolMap: File = "Resources/dol.map",
                dolTypeMap: File = "Resources/dol_typemap.json"
            ) {
                self.commonRelSymbolMap = commonRelSymbolMap
                self.commonRelTypeMap = commonRelTypeMap
                self.mapRelSymbolMap = mapRelSymbolMap
                self.mapRelTypeMap = mapRelTypeMap
                self.pocketMenuSymbolMap = pocketMenuSymbolMap
                self.dolSymbolMap = dolSymbolMap
                self.dolTypeMap = dolTypeMap
            }
        }

        public init(
            decksFsys: String = "deck_archive",
            resources: Resources = Resources(),
            decks: Decks = Decks(),
            deckTrainerPokemonIndexesProperty: String = "pokemonIndexes",
            deckTrainerAIIndexProperty: String = "aiIndex",
            deckTrainerShadowMaskProperty: String = "shadowMask",
            darkPokemonSaveSlotLimit: Int = 128,
            unusedColosseumMapPrefixes: [String] = ["B1_", "M1_"],
            saveSections: [SaveSectionSpec]? = nil,
            sectionStructTypes: [Int: String]? = nil
        ) {
            self.decksFsys = decksFsys
            self.resources = resources
            self.decks = decks
            self.deckTrainerPokemonIndexesProperty = deckTrainerPokemonIndexesProperty
            self.deckTrainerAIIndexProperty = deckTrainerAIIndexProperty
            self.deckTrainerShadowMaskProperty = deckTrainerShadowMaskProperty
            self.darkPokemonSaveSlotLimit = darkPokemonSaveSlotLimit
            self.unusedColosseumMapPrefixes = unusedColosseumMapPrefixes
            self.saveSections = saveSections ?? Self.defaultSaveSections
            self.sectionStructTypes = sectionStructTypes ?? Self.defaultSectionStructTypes
        }
    }
}
