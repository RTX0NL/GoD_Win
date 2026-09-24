import GoDFoundation

enum SaveSectionsOpsErrors: Error, CustomStringConvertible {
    case missingLayout(file: File, ErrorTrace)
    case missingSectionBinary(section: String, folder: Folder, ErrorTrace)
    case missingArtifact(file: File, ErrorTrace)
    case unresolvedStruct(type: String, chunk: String, ErrorTrace)
    case chunkOutOfBounds(section: String, chunk: String, offset: Int, length: Int, sectionLength: Int, ErrorTrace)
    case overlappingChunks(section: String, first: String, second: String, ErrorTrace)
    case missingFlagTable(chunk: String, ErrorTrace)
    case missingBankField(chunk: String, field: String, ErrorTrace)
    case malformedFlagCSV(chunk: String, reason: String, ErrorTrace)
    case rebuiltSizeMismatch(section: String, expected: Int, actual: Int, ErrorTrace)

    var description: String {
        switch self {
        case let .missingLayout(file, trace):
            return "Save sections: no section layout at \(file)\n\(trace)"
        case let .missingSectionBinary(section, folder, trace):
            return "Save sections: the layout describes section '\(section)' but no matching `.bin` is in \(folder) — run the save dump first\n\(trace)"
        case let .missingArtifact(file, trace):
            return "Save sections: missing artifact at \(file)\n\(trace)"
        case let .unresolvedStruct(type, chunk, trace):
            return "Save sections: chunk '\(chunk)' names struct '\(type)', which none of the listed engines resolved\n\(trace)"
        case let .chunkOutOfBounds(section, chunk, offset, length, sectionLength, trace):
            return "Save sections: chunk '\(chunk)' spans +0x\(String(offset, radix: 16))..+0x\(String(offset + length, radix: 16)) but section '\(section)' is only 0x\(String(sectionLength, radix: 16)) bytes\n\(trace)"
        case let .overlappingChunks(section, first, second, trace):
            return "Save sections: chunks '\(first)' and '\(second)' overlap in section '\(section)' — a layout's regions must be disjoint or one would overwrite the other\n\(trace)"
        case let .missingBankField(chunk, field, trace):
            return "Save sections: chunk '\(chunk)' expects a bank in the section's '\(field)' property, which its JSON doesn't have\n\(trace)"
        case let .missingFlagTable(chunk, trace):
            return "Save sections: chunk '\(chunk)' is flag banks, which need a flag descriptor table — pass `flagsTable`\n\(trace)"
        case let .malformedFlagCSV(chunk, reason, trace):
            return "Save sections: the decoded-flag CSV for '\(chunk)' is unusable — \(reason)\n\(trace)"
        case let .rebuiltSizeMismatch(section, expected, actual, trace):
            return "Save sections: section '\(section)' recomposed to \(actual) bytes but its binary is \(expected) — an artifact is the wrong size for its chunk\n\(trace)"
        }
    }
}
