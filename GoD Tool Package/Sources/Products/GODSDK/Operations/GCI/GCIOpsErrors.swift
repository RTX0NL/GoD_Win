import GoDFoundation

enum GCIOpsErrors: Error, CustomStringConvertible {
    case inputNotFound(file: File, ErrorTrace)
    case missingManifest(file: File, ErrorTrace)
    case missingRegion(folder: Folder, name: String, ErrorTrace)
    case missingArtifact(file: File, ErrorTrace)
    case imageLayoutUnavailable(ErrorTrace)
    case imageBlockOutsideRegion(region: String, ErrorTrace)
    case commentsOutsideRegion(region: String, ErrorTrace)
    case regionLengthChanged(name: String, expected: Int, actual: Int, ErrorTrace)
    case imagesNotReproducible(gamecode: String, offset: Int, length: Int, ErrorTrace)
    case commentsNotReproducible(gamecode: String, offset: Int, ErrorTrace)
    case metadataNotReproducible(
        gamecode: String, region: String, fill: UInt8, count: Int,
        samples: [(offset: Int, value: UInt8)], ErrorTrace
    )

    var description: String {
        switch self {
        case let .inputNotFound(file, trace):
            return "GCI input not found: \(file)\n\(trace)"
        case let .missingManifest(file, trace):
            return "GCI build: no manifest at \(file)\n\(trace)"
        case let .missingRegion(folder, name, trace):
            return "GCI build: missing region file '\(name)' under \(folder)\n\(trace)"
        case let .missingArtifact(file, trace):
            return "GCI build: missing card artifact \(file)\n\(trace)"
        case let .imageLayoutUnavailable(trace):
            return """
                GCI build: the manifest says the images are editable, but the \
                directory entry declares none.
                \(trace)
                """
        case let .imageBlockOutsideRegion(region, trace):
            return "GCI build: the image block falls outside region '\(region)'\n\(trace)"
        case let .commentsOutsideRegion(region, trace):
            return "GCI build: the comments fall outside region '\(region)'\n\(trace)"
        case let .regionLengthChanged(name, expected, actual, trace):
            return "GCI build: region '\(name)' rebuilt to \(actual) bytes, expected \(expected)\n\(trace)"
        case let .imagesNotReproducible(gamecode, offset, length, trace):
            return """
                GCI dump: the banner and icon of this \(gamecode) save do not \
                re-encode to the \(length) bytes at \(String(format: "%#x", offset)) \
                they were read from, so a save rebuilt from them would differ from \
                the original. This save's image encoding needs support added rather \
                than a stored copy of its bytes.
                \(trace)
                """
        case let .commentsNotReproducible(gamecode, offset, trace):
            return """
                GCI dump: the comment strings of this \(gamecode) save do not \
                re-encode to the bytes at \(String(format: "%#x", offset)) they were \
                read from — most likely a character set this tool does not infer \
                from the gamecode. That needs support added rather than a stored copy.
                \(trace)
                """
        case let .metadataNotReproducible(gamecode, region, fill, count, samples, trace):
            let listed = samples
                .map { String(format: "%#x=%02X", $0.offset, $0.value) }
                .joined(separator: ", ")
            let more = count > samples.count ? ", and \(count - samples.count) more" : ""
            return """
                GCI dump: region '\(region)' of this \(gamecode) save holds \(count) \
                byte(s) that no artifact describes and that are not the region's fill \
                (\(String(format: "%02X", fill))): \(listed)\(more). A rebuild fills \
                that space, so the save would not come back byte-identical. Whatever \
                lives there needs to be modelled — a field, a per-game fill, or its \
                own region — rather than copied across.
                \(trace)
                """
        }
    }
}
