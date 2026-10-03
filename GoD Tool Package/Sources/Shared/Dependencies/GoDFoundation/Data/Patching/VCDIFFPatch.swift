//
//  VCDIFFPatch.swift
//
//  VCDIFF (RFC 3284) — what an `.xdelta` file holds, and what xdelta3 writes.
//
//      header:  D6 C3 C4 00
//               Hdr_Indicator                 VCD_DECOMPRESS 1, VCD_CODETABLE 2, VCD_APPHEADER 4
//               [secondary compressor id]     when VCD_DECOMPRESS
//               [code table data]             when VCD_CODETABLE
//               [app header length + bytes]   when VCD_APPHEADER
//      windows, to the end of the file:
//               Win_Indicator                 VCD_SOURCE 1, VCD_TARGET 2, (xdelta3) VCD_ADLER32 4
//               [source segment length, position]
//               length of the delta encoding
//               target window length
//               Delta_Indicator               per-section secondary compression
//               data / instruction / address section lengths
//               [adler32 of the target window]  xdelta3's extension
//               the three sections
//
//  Each window is decoded on its own: instructions address a space that is the
//  window's **source segment followed by the part of this window already
//  written**, with the caches reset at the window boundary. Nothing reaches
//  into an earlier window's output — unless the window sets VCD_TARGET, which
//  takes its segment from the target instead, and which is refused here
//  because it would mean holding all the output produced so far.
//
//  What is refused, by name rather than by misreading it: a secondary
//  compressor (xdelta3's `-S`), a custom code table, and any per-section
//  compression. Every `.rvz`-era xdelta3 patch in the wild leaves all three
//  off; the one real sample on hand does.
//
//  **VCD_ADLER32 is xdelta3's, not the RFC's.** It adds four bytes after the
//  section lengths. Skip it and every window after the first is read from the
//  wrong offset — which is exactly how a first attempt at this read window two
//  as indicator 0x88.
//

import Foundation

public struct VCDIFFPatch {

    public static let magic: [UInt8] = [0xD6, 0xC3, 0xC4]
    public static let supportedVersion: UInt8 = 0x00

    public struct HeaderIndicator {
        public static let decompress: UInt8 = 0x01
        public static let codeTable: UInt8 = 0x02
        public static let appHeader: UInt8 = 0x04
    }

    public struct WindowIndicator {
        public static let source: UInt8 = 0x01
        public static let target: UInt8 = 0x02
        /// xdelta3's extension: a checksum of the decoded window.
        public static let adler32: UInt8 = 0x04
    }

    public struct Window {
        public let indicator: UInt8
        public let sourceSegmentLength: Int
        public let sourceSegmentPosition: Int
        public let targetLength: Int
        /// Where this window's output starts in the whole target.
        public let targetStart: Int
        public let dataRange: Range<Int>
        public let instructionRange: Range<Int>
        public let addressRange: Range<Int>
        public let adler32: UInt32?

        public var usesSource: Bool { indicator & WindowIndicator.source != 0 }
        public var usesTarget: Bool { indicator & WindowIndicator.target != 0 }
        public var targetRange: Range<Int> { targetStart ..< (targetStart + targetLength) }
    }

    /// The application header, kept as stored. xdelta3 puts the file names
    /// there; other tools put a description.
    public let appHeader: [UInt8]
    public let windows: [Window]
    /// The sum of the windows' target lengths.
    public let targetSize: Int

    // MARK: - Parsing

    public static func parse(_ patch: GoDReadable) throws -> VCDIFFPatch {
        let name = VCDIFFPatchCodec.formatName
        let length = patch.length
        guard length >= 5 else {
            throw PatchError.patchTooShort(format: name, length: length, minimum: 5)
        }
        guard let head = patch.read(atAddress: 0, length: 4) else {
            throw PatchError.readFailed(format: name, offset: 0, length: 4)
        }
        let headBytes = head.rawBytes
        guard Array(headBytes[0 ..< 3]) == magic else {
            throw PatchError.wrongMagic(format: name, found: headBytes)
        }
        guard headBytes[3] == supportedVersion else {
            throw PatchError.unsupportedFeature(
                format: name, feature: "version byte \(headBytes[3]) (only 0 is specified)"
            )
        }

        let stream = PatchByteStream(source: patch, start: 4, end: length)
        guard let indicator = stream.readByte() else {
            throw PatchError.malformedPatch(format: name, reason: "the header indicator is missing", offset: 4)
        }
        if indicator & HeaderIndicator.decompress != 0 {
            let id = stream.readByte() ?? 0
            throw PatchError.unsupportedFeature(
                format: name,
                feature: "secondary compression (compressor id \(id)) — written by xdelta3's -S option"
            )
        }
        if indicator & HeaderIndicator.codeTable != 0 {
            throw PatchError.unsupportedFeature(format: name, feature: "a custom code table")
        }
        var appHeader = [UInt8]()
        if indicator & HeaderIndicator.appHeader != 0 {
            let size = try integer(from: stream, field: "application header length", name: name)
            let start = stream.offset
            guard size >= 0, start + size <= length, let block = patch.read(atAddress: start, length: size) else {
                throw PatchError.malformedPatch(
                    format: name, reason: "the application header runs past the end of the patch", offset: start
                )
            }
            appHeader = block.rawBytes
            stream.skip(size)
        }

        var windows = [Window]()
        var targetStart = 0
        while !stream.isAtEnd {
            let windowStart = stream.offset
            guard let windowIndicator = stream.readByte() else { break }
            let known = WindowIndicator.source | WindowIndicator.target | WindowIndicator.adler32
            guard windowIndicator & ~known == 0 else {
                throw PatchError.malformedPatch(
                    format: name,
                    reason: String(format: "window indicator %#02x has bits no version of this format defines", windowIndicator),
                    offset: windowStart
                )
            }
            if windowIndicator & WindowIndicator.target != 0 {
                throw PatchError.unsupportedFeature(
                    format: name,
                    feature: "a window whose segment comes from the target (VCD_TARGET) — reading one means "
                    + "holding every byte decoded so far"
                )
            }

            var segmentLength = 0
            var segmentPosition = 0
            if windowIndicator & WindowIndicator.source != 0 {
                segmentLength = try integer(from: stream, field: "source segment length", name: name)
                segmentPosition = try integer(from: stream, field: "source segment position", name: name)
            }

            _ = try integer(from: stream, field: "delta encoding length", name: name)
            let targetLength = try integer(from: stream, field: "target window length", name: name)
            guard let deltaIndicator = stream.readByte() else {
                throw PatchError.malformedPatch(format: name, reason: "the delta indicator is missing", offset: stream.offset)
            }
            guard deltaIndicator == 0 else {
                throw PatchError.unsupportedFeature(
                    format: name,
                    feature: String(format: "per-section secondary compression (delta indicator %#02x)", deltaIndicator)
                )
            }
            let dataLength = try integer(from: stream, field: "data section length", name: name)
            let instructionLength = try integer(from: stream, field: "instruction section length", name: name)
            let addressLength = try integer(from: stream, field: "address section length", name: name)

            var adler: UInt32?
            if windowIndicator & WindowIndicator.adler32 != 0 {
                let start = stream.offset
                guard let bytes = patch.read(atAddress: start, length: 4), bytes.length == 4 else {
                    throw PatchError.malformedPatch(
                        format: name, reason: "the window checksum is missing", offset: start
                    )
                }
                let raw = bytes.rawBytes
                adler = UInt32(raw[0]) << 24 | UInt32(raw[1]) << 16 | UInt32(raw[2]) << 8 | UInt32(raw[3])
                stream.skip(4)
            }

            let dataStart = stream.offset
            let instructionStart = dataStart + dataLength
            let addressStart = instructionStart + instructionLength
            let windowEnd = addressStart + addressLength
            guard dataLength >= 0, instructionLength >= 0, addressLength >= 0, windowEnd <= length else {
                throw PatchError.malformedPatch(
                    format: name,
                    reason: "a window's sections (\(dataLength) + \(instructionLength) + \(addressLength) bytes) "
                    + "run past the end of the patch",
                    offset: dataStart
                )
            }

            windows.append(Window(
                indicator: windowIndicator,
                sourceSegmentLength: segmentLength,
                sourceSegmentPosition: segmentPosition,
                targetLength: targetLength,
                targetStart: targetStart,
                dataRange: dataStart ..< instructionStart,
                instructionRange: instructionStart ..< addressStart,
                addressRange: addressStart ..< windowEnd,
                adler32: adler
            ))
            targetStart += targetLength
            stream.skip(windowEnd - stream.offset)
        }

        return VCDIFFPatch(appHeader: appHeader, windows: windows, targetSize: targetStart)
    }

    private static func integer(from stream: PatchByteStream, field: String, name: String) throws -> Int {
        let start = stream.offset
        do {
            return try VCDIFFInteger.decode(nextByte: { stream.readByte() })
        } catch {
            throw PatchError.malformedPatch(format: name, reason: "\(field): \(error)", offset: start)
        }
    }
}
