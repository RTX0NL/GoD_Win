import GoDFoundation

public extension NintendoEngine {
    struct Data: Codable {
        public var u8 = U8()
        public var narc = NARC()

        public init() {}
    }
}
