import GoDFoundation

public extension XDEngine {
    struct Data: Codable {
        /// Name of the FSYS archive containing deck data (without .fsys extension)
        public var decksFsys: String = "deck_archive"
    }
}
