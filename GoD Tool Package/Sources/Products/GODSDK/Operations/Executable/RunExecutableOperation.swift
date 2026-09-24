import GoDFoundation

/// A thin wrapper over `ExternalProcess`: resolve the config's paths the way
/// every other operation resolves its paths, turn the stdin lines into bytes,
/// run, then report. Nothing about the program being launched is interpreted.

extension RunExecutable {

    static func run(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let executable = fileSystem.resolvedPath(of: config.executablePath)
        let workingDirectory = config.workingDirectory.map { fileSystem.resolvedPath(of: $0) }
        let arguments = config.arguments ?? []

        // Each line is terminated, including the last: a program reading
        // line by line would otherwise be left holding an unterminated one
        // when the stream closes.
        let input = config.standardInput.map { lines in
            Data(lines.map { $0 + "\n" }.joined().utf8)
        }

        let result: ExternalProcess.Result
        do {
            result = try ExternalProcess.run(
                executable: executable,
                arguments: arguments,
                standardInput: input,
                workingDirectory: workingDirectory
            )
        } catch {
            throw RunExecutableErrors.couldNotLaunch(reason: String(describing: error), .init())
        }

        let standardOutput = String(decoding: result.standardOutput, as: UTF8.self)
        let standardError = String(decoding: result.standardError, as: UTF8.self)

        // What the program printed is the only account of what it did, so it
        // goes to the log whether or not it is also captured to a file.
        if !standardOutput.isEmpty {
            logger?.log(.info("\(executable.fileName) stdout:\n\(standardOutput)"))
        }
        if !standardError.isEmpty {
            // A program that prints to stderr and still succeeds is ordinary
            // (progress, warnings), so this is only an error when the exit
            // code says so — which the throw below handles.
            logger?.log(.warning("\(executable.fileName) stderr:\n\(standardError)"))
        }

        // Written before the exit code is judged: the output of a run that
        // failed is exactly what someone needs to see to find out why.
        if let outputFile = config.outputFile {
            try fileSystem.writeFile(
                GoDData(data: result.standardOutput, byteOrder: Environment.byteOrder),
                at: outputFile,
                overwrite: config.overwrite ?? true
            )
        }

        if let signal = result.terminatingSignal {
            throw RunExecutableErrors.killedBySignal(
                executable: executable, signal: signal, standardError: standardError, .init()
            )
        }
        if result.exitCode != 0, config.failOnNonZeroExit ?? true {
            throw RunExecutableErrors.exitedNonZero(
                executable: executable, code: result.exitCode, standardError: standardError, .init()
            )
        }

        let outcome = result.exitCode == 0 ? "exited cleanly" : "exited with status \(result.exitCode)"
        logger?.log(.info(
            "Ran \(executable.path) with \(arguments.count) argument\(arguments.count == 1 ? "" : "s"); \(outcome)"
        ))
    }
}
