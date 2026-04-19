import GoDFoundation
import GoDEngine
import GTX

/// Parser and serializer for the GSW (Genius Sonority flash menu) format.
///
/// File layout (validated against XD samples + `flashmenu/Init` and
/// `flashmenu/Update` disassembly):
///
///     [0x00..0x2F]  48-byte structured header. Every field has a named meaning;
///                   asm-confirmed via `Init__9FlashMenuFPvUl.s` which
///                   initializes the tag-stream read position to 0x30.
///     [0x30..EOF]   Tag stream — a flat sequence of `(u32 BE code,
///                   u32 BE size, u8 payload[size])` records. The encoding is
///                   uniform: `FlashMenu::ParseTag` exits with
///                   `position += size` for every tag regardless of which
///                   handler runs. Empirically this walk lands exactly at EOF
///                   for every surveyed real sample.
///
/// Tag *codes* are uniformly decoded (range 0x00..0x2F, dispatched by
/// `ParseTag`'s 48-entry jump table at `data5/lbl_8041A100.s`). Tag *payload
/// contents* are handler-specific — each of the 19 in-use codes has its own
/// internal layout that hasn't been uniformly reverse-engineered, so payloads
/// are preserved as opaque `Data` for round-trip.
///
/// Embedded textures appear within tag payloads, identified by the 4-byte
/// marker `[0x03, 0x00, 0x00, id]` (id ∈ 1..255) followed at +0x20 by a
/// GTX-format header whose 2-byte field at +0x24 equals `0x0801`. When found,
/// each texture is extracted as a PNG and a `GSWTextureRef` records its
/// position within its containing tag's payload so the build path can splice
/// the re-encoded bytes back at the same offset.
public struct GSWFile: Codable, Equatable {
    public static let formatName = "gsw"

    public var header: GSWHeader
    public var tags: [GSWTag]

    public init(header: GSWHeader, tags: [GSWTag]) {
        self.header = header
        self.tags = tags
    }

    /// Convenience: every embedded texture across every tag, in iteration order.
    public var allTextureRefs: [GSWTextureRef] {
        tags.flatMap(\.textures)
    }
}

/// 48-byte (0x30) header. Field positions asm-confirmed by the read-position
/// initialization in `Init__9FlashMenuFPvUl.s` (`li r0, 0x30; stw r0, 0x0(r31)`).
///
/// Field semantics partly reverse-engineered. Fields labeled `unknown_*` are
/// preserved verbatim for round-trip but their meaning has not been confirmed.
public struct GSWHeader: Codable, Equatable {
    /// 0x00 — observed always 0x00000007 across surveyed XD samples.
    public var version: UInt32
    /// 0x04 — canvas width in twips (1/20 pixel).
    public var canvasWidthTwips: UInt16
    /// 0x06 — canvas height in twips.
    public var canvasHeightTwips: UInt16
    /// 0x08 — purpose unclear. Empirically does NOT bound the tag stream
    /// (the stream extends to EOF), but the value is non-zero and varies per
    /// file (e.g. 17%–30% of file size). Possibly a runtime allocation hint
    /// for a specific buffer. Preserved verbatim.
    public var tagDataSize: UInt32
    /// 0x0C — observed always 0.
    public var unknown_0x0C: UInt16
    /// 0x0E — observed always 0x3200.
    public var frameRate: UInt16
    /// 0x10 — observed always 0x2580.
    public var unknown_0x10: UInt32
    /// 0x14 — observed always 0.
    public var unknown_0x14: UInt32
    /// 0x18 — number of sprite depth layers (FlashMenu::InitDataPointer
    /// allocates per-depth state arrays sized by this value). Also serves as
    /// the upper bound for embedded-texture id iteration.
    public var spriteDepthCount: UInt16
    /// 0x1A — number of character definitions.
    public var characterCount: UInt16
    /// 0x1C..0x2B — 16 bytes, observed all-zero; preserved verbatim.
    public var padding_0x1C: Data
    /// 0x2C — observed always 0; purpose unknown.
    public var unknown_0x2C: UInt32

    public init(
        version: UInt32,
        canvasWidthTwips: UInt16,
        canvasHeightTwips: UInt16,
        tagDataSize: UInt32,
        unknown_0x0C: UInt16,
        frameRate: UInt16,
        unknown_0x10: UInt32,
        unknown_0x14: UInt32,
        spriteDepthCount: UInt16,
        characterCount: UInt16,
        padding_0x1C: Data,
        unknown_0x2C: UInt32
    ) {
        self.version = version
        self.canvasWidthTwips = canvasWidthTwips
        self.canvasHeightTwips = canvasHeightTwips
        self.tagDataSize = tagDataSize
        self.unknown_0x0C = unknown_0x0C
        self.frameRate = frameRate
        self.unknown_0x10 = unknown_0x10
        self.unknown_0x14 = unknown_0x14
        self.spriteDepthCount = spriteDepthCount
        self.characterCount = characterCount
        self.padding_0x1C = padding_0x1C
        self.unknown_0x2C = unknown_0x2C
    }
}

/// One tag record in the tag stream.
public struct GSWTag: Codable, Equatable {
    /// FlashMenu::ParseTag dispatches on this code (range 0x00..0x2F).
    public var code: UInt32
    /// Payload bytes following the (code, size) header. Length matches the
    /// `size` field that was read alongside this tag. Opaque because each
    /// tag-handler interprets its payload differently; no uniform decoding.
    public var payload: Data
    /// Embedded textures found within `payload`, ordered by the offset they
    /// appear at. Empty for most tags.
    public var textures: [GSWTextureRef]

    public init(code: UInt32, payload: Data, textures: [GSWTextureRef] = []) {
        self.code = code
        self.payload = payload
        self.textures = textures
    }
}

/// Metadata describing one embedded texture located within a tag's payload.
public struct GSWTextureRef: Codable, Equatable {
    /// 1-based id from the `[0x03, 0x00, 0x00, id]` header marker.
    public var id: Int
    /// Byte offset of the marker within the containing tag's payload.
    public var payloadOffset: Int
    /// Total size of the texture block (texture data + palette) at
    /// `payload[payloadOffset + 0x20 ..< payloadOffset + 0x20 + blockSize]`.
    public var blockSize: Int
    public var format: GXTextureFormat
    public var paletteFormat: GXPaletteFormat?
    public var width: Int
    public var height: Int
    /// Path to the extracted PNG, relative to the metadata `.json` file's
    /// parent folder (e.g. `./textures/<gswName>_texture_001.png`). Stored as
    /// a path rather than a bare filename so the textures folder can be
    /// renamed or relocated without losing the link.
    public var pngPath: String

    public init(
        id: Int,
        payloadOffset: Int,
        blockSize: Int,
        format: GXTextureFormat,
        paletteFormat: GXPaletteFormat?,
        width: Int,
        height: Int,
        pngPath: String
    ) {
        self.id = id
        self.payloadOffset = payloadOffset
        self.blockSize = blockSize
        self.format = format
        self.paletteFormat = paletteFormat
        self.width = width
        self.height = height
        self.pngPath = pngPath
    }
}
