//
//  PatchOperation.swift
//  GODOps
//
//  Thin wrappers over the patch codecs. Which format, which direction and
//  what the result must check out as all come from the config or from the
//  patch's own header, so these only decide which files to read, where the
//  result goes, and whether to keep it.
//

import GoDFoundation

extension CreatePatch {

    static func run(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        guard let source = fileSystem.readFile(at: config.sourceFile) else {
            throw PatchErrors.inputFileNotFound(file: config.sourceFile, .init())
        }
        guard let target = fileSystem.readFile(at: config.targetFile) else {
            throw PatchErrors.inputFileNotFound(file: config.targetFile, .init())
        }

        let codec = config.format.makeCodec()
        let patch = try codec.createPatch(source: source, target: target)
        try fileSystem.writeFile(patch, at: config.patchFile, overwrite: config.overwrite ?? true)

        logger?.log(.info(
            "Created a \(config.format.name) patch from \(config.sourceFile.fileName) (\(source.length) bytes) "
            + "to \(config.targetFile.fileName) (\(target.length) bytes): \(patch.length) bytes at \(config.patchFile.path)"
        ))
    }
}

extension ApplyPatch {

    static func run(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        // Writing the result over the input would destroy the bytes the
        // verify pass reads, so the two paths have to differ.
        let inputPath = fileSystem.resolvedPath(of: config.inputFile)
        let outputPath = fileSystem.resolvedPath(of: config.outputFile)
        guard inputPath != outputPath else {
            throw PatchErrors.outputIsInput(file: outputPath, .init())
        }

        guard let patch = fileSystem.readFile(at: config.patchFile) else {
            throw PatchErrors.patchFileNotFound(file: config.patchFile, .init())
        }
        guard let input = fileSystem.readFile(at: config.inputFile) else {
            throw PatchErrors.inputFileNotFound(file: config.inputFile, .init())
        }

        let format = try PatchOps.resolveFormat(named: config.format, of: patch, file: config.patchFile)
        let codec = format.makeCodec()
        let application = try codec.apply(
            patch: patch,
            to: input,
            direction: config.direction,
            validateInput: !(config.ignoreChecksums ?? false)
        )
        for warning in application.warnings {
            logger?.log(.warning("\(format.name): \(warning)"))
        }

        try fileSystem.writeFile(application.output, at: config.outputFile, overwrite: config.overwrite ?? true)

        // Verify what landed, not the view that produced it: a view that was
        // never written is no evidence about the bytes on disk.
        //
        // When the input was the one the patch names, a bad output can only
        // mean the codec is wrong, so the file is deleted rather than left
        // looking like a result — the gate the NKit restore uses. Under
        // `ignoreChecksums` the input was *not* that file, so the output was
        // never going to match and the mismatch is the expected outcome of
        // what was asked for: it is reported and the file kept.
        guard let written = fileSystem.readFile(at: config.outputFile) else {
            throw PatchErrors.outputNotReadable(file: config.outputFile, .init())
        }
        do {
            try codec.validate(output: written, of: application)
        } catch {
            guard config.ignoreChecksums == true else {
                try? fileSystem.deleteFile(at: config.outputFile)
                throw error
            }
            logger?.log(.warning("\(format.name): \(error)"))
        }

        logger?.log(.info(
            "Applied \(config.patchFile.fileName) (\(format.name), \(application.direction.rawValue)) to "
            + "\(config.inputFile.fileName) (\(input.length) bytes): \(application.output.length) bytes "
            + "at \(config.outputFile.path)"
        ))
    }
}
