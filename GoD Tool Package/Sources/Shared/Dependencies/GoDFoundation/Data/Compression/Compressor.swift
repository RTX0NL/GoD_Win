import Foundation

public protocol Compressor {
    func compress(_ data: GoDData) -> GoDData
    func decompress(_ data: GoDData) throws -> GoDData
}

/// A compressor whose streams announce themselves with a magic at offset 0.
///
/// Lets a codec keep its signature next to its implementation while
/// `CompressionFormat` sniffs across all of them. Not every compressor
/// qualifies: the bare LZSS stream `LZSSCompressor` speaks carries no magic
/// at all — `LZSSHeaderedCompressor` is its self-describing form.
public protocol MagicPrefixedCompressor: Compressor {
    static var magic: [UInt8] { get }
}
