//
//  CompressionOps.swift
//  GODOps
//
//  Standalone compress / decompress of one file, or a folder of files, with
//  the stream codecs GoDFoundation implements. Nothing here reads engine
//  data: a codec is fixed knowledge about a format, so the format name plus
//  its options fully determine it, and the operations stay engine-free.
//

import GoDFoundation

enum CompressionOps {

    /// The stream format a `compress` writes or a `decompress` reads, as one
    /// plain name in the config (`"format": "yaz0"`). Raw values are
    /// hyphenated lowercase, like `Convert.FileFormatSelection`.
    enum Format: String, Codable, CaseIterable {
        case yaz0
        case yay0
        /// Genius Sonority's LZSS behind its 16-byte `LZSS` header — what a
        /// compressed FSYS entry holds. Self-describing, so a `decompress`
        /// can detect it.
        case lzss
        /// The bare LZSS stream with no header. It carries no magic, so a
        /// `decompress` has to be told, and the geometry options say how it
        /// was cut.
        case lzssRaw = "lzss-raw"

        /// The sniffable format this is, or nil for a stream with no magic.
        var detectable: CompressionFormat? {
            switch self {
            case .yaz0: return .yaz0
            case .yay0: return .yay0
            case .lzss: return .lzss
            case .lzssRaw: return nil
            }
        }

        init(detected: CompressionFormat) {
            switch detected {
            case .yaz0: self = .yaz0
            case .yay0: self = .yay0
            case .lzss: self = .lzss
            }
        }

        /// The conventional spelling, for logs and errors.
        var name: String {
            switch self {
            case .yaz0: return Yaz0Compressor.formatName
            case .yay0: return Yay0Compressor.formatName
            case .lzss: return LZSSHeaderedCompressor.formatName
            case .lzssRaw: return "raw \(LZSSHeaderedCompressor.formatName)"
            }
        }

        /// The extension a compressed file gets when the config doesn't
        /// name one. Both LZSS forms share `.lzss` — the file's first bytes
        /// say which it is.
        var defaultCompressedExtension: String {
            switch self {
            case .yaz0: return "szs"
            case .yay0: return "szp"
            case .lzss, .lzssRaw: return "lzss"
            }
        }

        /// Yaz0 and Yay0 make identical compression decisions through one
        /// `LZ77Encoder`, so its tuning applies to both.
        var usesLZ77Encoder: Bool {
            switch self {
            case .yaz0, .yay0: return true
            case .lzss, .lzssRaw: return false
            }
        }

        /// Whether the LZSS window / length / threshold geometry applies.
        var usesLZSSGeometry: Bool {
            switch self {
            case .lzss, .lzssRaw: return true
            case .yaz0, .yay0: return false
            }
        }
    }

    enum Direction: String {
        case compress
        case decompress
    }

    /// Per-format arguments. Every field is optional. A field set for a
    /// format or direction that doesn't read it is an error rather than
    /// silently ignored, so a config can't claim something it doesn't do.
    struct Options: Codable, Equatable {
        /// Yaz0's header alignment word. Zero for GameCube and Wii content;
        /// used from the Wii U on. Compress only.
        let alignment: UInt32?
        /// LZ77 (Yaz0 / Yay0) encoder: Nintendo's one-byte deferral
        /// heuristic. On by default. Compress only.
        let deferredMatching: Bool?
        /// LZ77 encoder: the most candidates examined per position, at
        /// least 1. The default covers the whole window. Compress only.
        let maxChainLength: Int?
        /// LZSS window bits (EI): the ring buffer holds `1 << windowBits`
        /// bytes. Default 12. Both directions.
        let windowBits: Int?
        /// LZSS length bits (EJ). Default 4. Both directions.
        let lengthBits: Int?
        /// LZSS threshold (P): a match of this many bytes or fewer is sent
        /// as literals. Default 2. Both directions.
        let threshold: Int?

        init(
            alignment: UInt32? = nil,
            deferredMatching: Bool? = nil,
            maxChainLength: Int? = nil,
            windowBits: Int? = nil,
            lengthBits: Int? = nil,
            threshold: Int? = nil
        ) {
            self.alignment = alignment
            self.deferredMatching = deferredMatching
            self.maxChainLength = maxChainLength
            self.windowBits = windowBits
            self.lengthBits = lengthBits
            self.threshold = threshold
        }

        static let none = Options()

        /// The LZSS geometry these options describe, defaults filled in.
        var lzssGeometry: (windowBits: Int, lengthBits: Int, threshold: Int) {
            (
                windowBits ?? LZSSCompressor.defaultWindowBits,
                lengthBits ?? LZSSCompressor.defaultLengthBits,
                threshold ?? LZSSCompressor.defaultThreshold
            )
        }

        /// Rejects any option the format doesn't read in this direction, and
        /// any value the codecs would only trap on: `LZ77Encoder` and
        /// `LZSSCompressor` assert their bounds rather than throw.
        func validate(for format: Format, direction: Direction) throws {
            let compressing = direction == .compress

            func check(_ option: String, isSet: Bool, applies: Bool, readBy: String) throws {
                guard isSet, !applies else { return }
                throw CompressionErrors.optionNotApplicable(
                    option: option, format: format, direction: direction, readBy: readBy, .init()
                )
            }
            try check("alignment", isSet: alignment != nil,
                      applies: compressing && format == .yaz0, readBy: "yaz0 when compressing")
            try check("deferredMatching", isSet: deferredMatching != nil,
                      applies: compressing && format.usesLZ77Encoder, readBy: "yaz0 and yay0 when compressing")
            try check("maxChainLength", isSet: maxChainLength != nil,
                      applies: compressing && format.usesLZ77Encoder, readBy: "yaz0 and yay0 when compressing")
            try check("windowBits", isSet: windowBits != nil,
                      applies: format.usesLZSSGeometry, readBy: "lzss and lzss-raw")
            try check("lengthBits", isSet: lengthBits != nil,
                      applies: format.usesLZSSGeometry, readBy: "lzss and lzss-raw")
            try check("threshold", isSet: threshold != nil,
                      applies: format.usesLZSSGeometry, readBy: "lzss and lzss-raw")

            func outOfRange(_ option: String, _ value: Int, _ rule: String) -> CompressionErrors {
                .optionOutOfRange(option: option, value: value, format: format, rule: rule, .init())
            }
            if let maxChainLength, maxChainLength < 1 {
                throw outOfRange("maxChainLength", maxChainLength, "must be at least 1")
            }
            guard format.usesLZSSGeometry else { return }

            // A back-reference is two bytes: `lengthBits` of length, and the
            // position in the remaining `16 - lengthBits`. The encoder primes
            // its search with a full lookahead below the start, so the window
            // has to hold two lookaheads.
            let (ei, ej, p) = lzssGeometry
            guard (1 ... 8).contains(ej) else {
                throw outOfRange("lengthBits", ej, "must be 1...8")
            }
            guard (1 ... 15).contains(ei) else {
                throw outOfRange("windowBits", ei, "must be 1...15")
            }
            guard ei + ej <= 16 else {
                throw outOfRange("windowBits", ei, "windowBits + lengthBits must not exceed 16 — a back-reference is packed into two bytes")
            }
            guard p >= 0 else {
                throw outOfRange("threshold", p, "must be at least 0")
            }
            let window = 1 << ei
            let lookahead = (1 << ej) + p
            guard window >= 2 * lookahead else {
                throw outOfRange(
                    "windowBits", ei,
                    "a \(window)-byte window must hold two lookaheads of (1 << lengthBits) + threshold = \(lookahead) bytes"
                )
            }
        }
    }

    /// A window onto the input, for a stream embedded inside a larger file.
    struct ByteRange: Codable, Equatable {
        let offset: Int
        /// Absent runs to the end of the file. Every self-describing format
        /// stops where its header says, so trailing bytes are harmless; a
        /// raw LZSS stream would decode them, so give it a length.
        let length: Int?

        init(offset: Int, length: Int? = nil) {
            self.offset = offset
            self.length = length
        }
    }

    // MARK: - Codecs

    static func makeCompressor(format: Format, options: Options?) throws -> Compressor {
        let options = options ?? .none
        try options.validate(for: format, direction: .compress)
        switch format {
        case .yaz0: return Yaz0Compressor(alignment: options.alignment ?? 0, encoder: lz77Encoder(options))
        case .yay0: return Yay0Compressor(encoder: lz77Encoder(options))
        case .lzss: return LZSSHeaderedCompressor(codec: lzssCodec(options))
        case .lzssRaw: return lzssCodec(options)
        }
    }

    static func makeDecompressor(format: Format, options: Options?) throws -> Compressor {
        let options = options ?? .none
        try options.validate(for: format, direction: .decompress)
        switch format {
        case .yaz0: return Yaz0Compressor()
        case .yay0: return Yay0Compressor()
        case .lzss: return LZSSHeaderedCompressor(codec: lzssCodec(options))
        case .lzssRaw: return lzssCodec(options)
        }
    }

    private static func lz77Encoder(_ options: Options) -> LZ77Encoder {
        let base = LZ77Encoder.Configuration.nintendo
        return LZ77Encoder(configuration: .init(
            windowSize: base.windowSize,
            minMatchLength: base.minMatchLength,
            maxMatchLength: base.maxMatchLength,
            usesDeferredMatching: options.deferredMatching ?? base.usesDeferredMatching,
            maxChainLength: options.maxChainLength ?? base.maxChainLength
        ))
    }

    private static func lzssCodec(_ options: Options) -> LZSSCompressor {
        let (ei, ej, p) = options.lzssGeometry
        return LZSSCompressor(EI: ei, EJ: ej, P: p)
    }

    // MARK: - Input

    /// The format to decompress `stream` as: the named one, checked against
    /// the stream's magic where it has one, or else whatever the magic says.
    static func resolveFormat(named: Format?, of stream: GoDReadable, file: File) throws -> Format {
        let detected = CompressionFormat.detect(stream)
        guard let named else {
            guard let detected else {
                throw CompressionErrors.unrecognizedFormat(file: file, prefix: prefix(of: stream), .init())
            }
            return Format(detected: detected)
        }
        if let expected = named.detectable, detected != expected {
            throw CompressionErrors.formatMismatch(file: file, expected: named, found: detected, .init())
        }
        return named
    }

    /// The bytes a decompress works on: the whole of `readable`, or the
    /// window `range` selects. A range is bounds-checked against the file
    /// and read as a window, so a streamed source stays streamed.
    static func slice(_ readable: GoDReadable, range: ByteRange?, file: File) throws -> GoDData {
        guard let range else {
            guard let whole = readable.allData ?? readable.read(atAddress: 0, length: readable.length) else {
                throw CompressionErrors.inputFileNotFound(file: file, .init())
            }
            return whole
        }
        let size = readable.length
        let length = range.length ?? (size - range.offset)
        guard range.offset >= 0, length >= 0, range.offset + length <= size,
              let window = readable.read(atAddress: range.offset, length: length) else {
            throw CompressionErrors.rangeOutOfBounds(
                file: file, offset: range.offset, length: range.length, fileSize: size, .init()
            )
        }
        return window
    }

    private static func prefix(of stream: GoDReadable) -> [UInt8] {
        let count = min(stream.length, CompressionFormat.magicLength)
        return stream.read(atAddress: 0, length: count)?.rawBytes ?? []
    }

    // MARK: - Names

    /// Extensions a `decompress` strips from a derived output name.
    static let compressedExtensions: Set<String> = ["szs", "szp", "yaz0", "yay0", "lzss"]

    /// `<fileName>.<ext>` — the inner extension is kept so a decompress of
    /// the result derives the original name back.
    static func compressedName(for fileName: String, extension ext: String) -> String {
        "\(fileName).\(ext)"
    }

    /// The compressed extension dropped if the name carries one, else
    /// `.bin` appended — so the output never has the input's name, and a
    /// folder can be decompressed onto itself.
    static func decompressedName(for fileName: String) -> String {
        let ext = fileName.fileExtension.lowercased()
        guard !ext.isEmpty, compressedExtensions.contains(ext) else {
            return "\(fileName).bin"
        }
        let stem = fileName.withoutExtension
        return stem.isEmpty ? "decompressed.bin" : stem
    }

    /// `configured` with any leading dot stripped, or the format's default.
    static func outputExtension(_ configured: String?, for format: Format) throws -> String {
        guard let configured else { return format.defaultCompressedExtension }
        let ext = normalizedExtension(configured)
        guard !ext.isEmpty else {
            throw CompressionErrors.invalidOutputExtension(configured, .init())
        }
        return ext
    }

    /// Whether `file` passes an `extensions` filter — no filter passes
    /// everything; entries are matched case-insensitively, dot or no dot.
    static func matches(_ file: File, extensions: [String]?) -> Bool {
        guard let extensions else { return true }
        guard let ext = file.fileType?.lowercased() else { return false }
        return extensions.contains { normalizedExtension($0) == ext }
    }

    private static func normalizedExtension(_ ext: String) -> String {
        var clean = ext.lowercased()
        while clean.hasPrefix(".") { clean.removeFirst() }
        return clean
    }

    static func sibling(of file: File, named name: String) -> File {
        (file.parentFolder ?? Folder("/")).file(name)
    }
}
