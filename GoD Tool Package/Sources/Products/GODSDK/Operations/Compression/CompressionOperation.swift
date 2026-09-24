import GoDFoundation

/// Thin wrappers over the GoDFoundation codecs. Everything about a stream —
/// which format it is, how it was cut — comes from the config or from the
/// stream's own header, so these ops only decide which files to process,
/// which codec to build, and where the results go.

extension Compress {

    static func run(
        config: SingleConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let compressor = try CompressionOps.makeCompressor(format: config.format, options: config.options)
        guard let input = fileSystem.readFile(at: config.inputFile)?.allData else {
            throw CompressionErrors.inputFileNotFound(file: config.inputFile, .init())
        }
        let destination = config.outputFile ?? CompressionOps.sibling(
            of: config.inputFile,
            named: CompressionOps.compressedName(
                for: config.inputFile.fileName, extension: config.format.defaultCompressedExtension
            )
        )
        let compressed = compressor.compress(input)
        try fileSystem.writeFile(compressed, at: destination, overwrite: config.overwrite)
        logger?.log(.info(
            "Compressed \(config.inputFile.fileName) (\(input.length) bytes) as \(config.format.name) "
            + "to \(destination.path) (\(compressed.length) bytes)"
        ))
    }

    static func run(
        config: BatchConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let compressor = try CompressionOps.makeCompressor(format: config.format, options: config.options)
        let ext = try CompressionOps.outputExtension(config.outputExtension, for: config.format)
        guard fileSystem.inspectFolder(at: config.inputFolder) != nil else {
            throw FSTErrors.folderNotFound(config.inputFolder, .init())
        }

        var compressed = 0
        var skipped = 0
        for candidate in fileSystem.scan(config.inputFolder, recursive: config.recursive, matches: { _ in true }) {
            guard CompressionOps.matches(candidate.file, extensions: config.extensions) else {
                skipped += 1
                continue
            }
            guard let input = fileSystem.readFile(at: candidate.file)?.allData else {
                throw CompressionErrors.inputFileNotFound(file: candidate.file, .init())
            }
            let destination = config.outputFolder
                .folder(candidate.relativeFolder.path)
                .file(CompressionOps.compressedName(for: candidate.file.fileName, extension: ext))
            try fileSystem.writeFile(compressor.compress(input), at: destination, overwrite: config.overwrite)
            compressed += 1
        }

        logger?.log(.info("Compression: compressed \(compressed) as \(config.format.name), skipped \(skipped)"))
    }
}

extension Decompress {

    static func run(
        config: SingleConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        guard let readable = fileSystem.readFile(at: config.inputFile) else {
            throw CompressionErrors.inputFileNotFound(file: config.inputFile, .init())
        }
        let stream = try CompressionOps.slice(readable, range: config.range, file: config.inputFile)
        let format = try CompressionOps.resolveFormat(named: config.format, of: stream, file: config.inputFile)
        let decompressor = try CompressionOps.makeDecompressor(format: format, options: config.options)

        let decompressed = try decompressor.decompress(stream)
        let destination = config.outputFile ?? CompressionOps.sibling(
            of: config.inputFile,
            named: CompressionOps.decompressedName(for: config.inputFile.fileName)
        )
        try fileSystem.writeFile(decompressed, at: destination, overwrite: config.overwrite)
        logger?.log(.info(
            "Decompressed \(config.inputFile.fileName) (\(stream.length) bytes of \(format.name)) "
            + "to \(destination.path) (\(decompressed.length) bytes)"
        ))
    }

    static func run(
        config: BatchConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        // A named format is checked up front so a bad option fails before
        // any file is touched; an auto-detected one can only be checked
        // against what each file turns out to be.
        if let named = config.format {
            _ = try CompressionOps.makeDecompressor(format: named, options: config.options)
        }
        guard fileSystem.inspectFolder(at: config.inputFolder) != nil else {
            throw FSTErrors.folderNotFound(config.inputFolder, .init())
        }

        var decompressed = 0
        var skipped = 0
        for candidate in fileSystem.scan(config.inputFolder, recursive: config.recursive, matches: { _ in true }) {
            guard CompressionOps.matches(candidate.file, extensions: config.extensions),
                  let readable = fileSystem.readFile(at: candidate.file) else {
                skipped += 1
                continue
            }
            let stream = try CompressionOps.slice(readable, range: config.range, file: candidate.file)

            // The magic decides for the self-describing formats, so a file
            // that isn't a stream — or isn't the stream that was asked for —
            // is skipped rather than failed: a bulk run is expected to be
            // pointed at a mixed folder.
            let format: CompressionOps.Format
            switch config.format {
            case .none:
                guard let detected = CompressionFormat.detect(stream) else {
                    skipped += 1
                    continue
                }
                format = CompressionOps.Format(detected: detected)
            case .some(let named):
                if let expected = named.detectable, CompressionFormat.detect(stream) != expected {
                    skipped += 1
                    continue
                }
                format = named
            }

            let decompressor = try CompressionOps.makeDecompressor(format: format, options: config.options)
            let data = try decompressor.decompress(stream)
            let destination = config.outputFolder
                .folder(candidate.relativeFolder.path)
                .file(CompressionOps.decompressedName(for: candidate.file.fileName))
            try fileSystem.writeFile(data, at: destination, overwrite: config.overwrite)
            decompressed += 1
        }

        logger?.log(.info("Decompression: decompressed \(decompressed), skipped \(skipped)"))
    }
}
