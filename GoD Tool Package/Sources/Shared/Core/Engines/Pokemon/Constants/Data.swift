import GoDFoundation

public extension PokemonEngine {
    /// Project-level Pokémon configuration. Empty for now — every field
    /// has a sensible default and the data is mostly inherited from the
    /// engine's enums/structs. Hosted here so future additions don't
    /// force a schema migration on existing engine JSONs.
    struct Data: Codable {
        public init() {}
    }
}
