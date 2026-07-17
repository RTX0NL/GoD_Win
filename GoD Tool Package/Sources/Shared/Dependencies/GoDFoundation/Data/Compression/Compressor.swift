import Foundation

public protocol Compressor {
    func compress(_ data: GoDData) -> GoDData
    func decompress(_ data: GoDData) throws -> GoDData
}
