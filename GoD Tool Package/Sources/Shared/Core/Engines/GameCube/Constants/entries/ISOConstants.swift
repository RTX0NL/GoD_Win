import GoDFoundation

extension GamecubeEngine.Data {
    public struct ISO: Codable {
        public private(set) var maxDiscCapacity = 0x57058000
        public private(set) var fileAlignment = 1
    }
}
