//
//  ExternalProcess.swift
//  GoDFoundation
//
//  Running a program on the host machine and collecting what it printed.
//
//  Here rather than in an engine for the same reason the codecs are: nothing
//  about spawning a process is game knowledge. It is a host capability, like
//  byte order and the platform's path spelling, so it sits beside them and
//  the operation that uses it stays a thin wrapper.
//
//  A child always gets pipes for all three streams — never the tool's own
//  terminal. An operation chain that handed a child GODDESS's stdin would let
//  it swallow keystrokes meant for the tool, and a child writing straight to
//  the console would interleave with the logger.
//

import Foundation

public enum ExternalProcess {

    /// What a finished process left behind.
    public struct Result {
        /// The process's exit status, or 0 when it was killed by a signal —
        /// `terminatingSignal` is what says so.
        public let exitCode: Int32
        /// The signal that killed the process, or nil if it exited normally.
        public let terminatingSignal: Int32?
        public let standardOutput: Data
        public let standardError: Data

        public init(exitCode: Int32, terminatingSignal: Int32?, standardOutput: Data, standardError: Data) {
            self.exitCode = exitCode
            self.terminatingSignal = terminatingSignal
            self.standardOutput = standardOutput
            self.standardError = standardError
        }

        public var succeeded: Bool { terminatingSignal == nil && exitCode == 0 }
    }

    /// Why a process could not be started. A process that *ran* and failed is
    /// not an error here — that is a `Result` with a non-zero `exitCode`, and
    /// what to make of it is the caller's decision.
    public enum LaunchFailure: Error, CustomStringConvertible {
        case notFound(path: String)
        case notExecutable(path: String)
        case workingDirectoryNotFound(path: String)
        case couldNotLaunch(path: String, reason: String)
        case unsupportedPlatform

        public var description: String {
            switch self {
            case let .notFound(path):
                return "No file at \(path) to run"
            case let .notExecutable(path):
                return "\(path) exists but is not executable — check its permission bits (chmod +x)"
            case let .workingDirectoryNotFound(path):
                return "No folder at \(path) to run in"
            case let .couldNotLaunch(path, reason):
                return "Could not launch \(path): \(reason)"
            case .unsupportedPlatform:
                return "This platform cannot launch external processes"
            }
        }
    }

    /// Runs `executable` to completion and returns its streams.
    ///
    /// `standardInput` is written to the child and the stream is then closed,
    /// so a program that reads to EOF sees exactly those bytes and stops. Nil
    /// closes it immediately, which is the same thing with no bytes.
    ///
    /// Blocks until the process exits. Both output streams are drained while
    /// it runs, so a program that prints more than a pipe buffer's worth does
    /// not stall waiting for a reader.
    public static func run(
        executable: File,
        arguments: [String] = [],
        standardInput: Data? = nil,
        workingDirectory: Folder? = nil
    ) throws -> Result {
        #if os(WASI)
        throw LaunchFailure.unsupportedPlatform
        #else
        _ = ignoreBrokenPipes

        let manager = FileManager.default
        let executablePath = executable.nativePath
        guard manager.fileExists(atPath: executablePath) else {
            throw LaunchFailure.notFound(path: executable.path)
        }
        guard manager.isExecutableFile(atPath: executablePath) else {
            throw LaunchFailure.notExecutable(path: executable.path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        if let workingDirectory {
            var isFolder: ObjCBool = false
            let folderPath = workingDirectory.nativePath
            guard manager.fileExists(atPath: folderPath, isDirectory: &isFolder), isFolder.boolValue else {
                throw LaunchFailure.workingDirectoryNotFound(path: workingDirectory.path)
            }
            process.currentDirectoryURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        }

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw LaunchFailure.couldNotLaunch(path: executable.path, reason: String(describing: error))
        }

        // Both streams are drained on their own threads. A child that fills
        // the pipe buffer blocks until someone reads it, so draining them in
        // turn — or only after `waitUntilExit` — hangs on any program that
        // prints more than a page.
        var collectedOutput = Data()
        var collectedErrors = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "GoDFoundation.ExternalProcess", attributes: .concurrent)
        queue.async(group: group) { collectedOutput = output.fileHandleForReading.readDataToEndOfFile() }
        queue.async(group: group) { collectedErrors = errors.fileHandleForReading.readDataToEndOfFile() }

        // A program that stops reading early (`head -1`) closes its end while
        // we are still writing, which is ordinary rather than a failure: what
        // it did with the input it took is its exit code's business.
        if let standardInput, !standardInput.isEmpty {
            try? input.fileHandleForWriting.write(contentsOf: standardInput)
        }
        try? input.fileHandleForWriting.close()

        process.waitUntilExit()
        group.wait()

        #if os(Windows)
        // Windows has no signals, but Foundation reports every non-zero exit
        // there as `.uncaughtSignal`; the status is always the exit code.
        let killedBy: Int32? = nil
        #else
        let killedBy: Int32? = process.terminationReason == .uncaughtSignal ? process.terminationStatus : nil
        #endif
        return Result(
            exitCode: killedBy == nil ? process.terminationStatus : 0,
            terminatingSignal: killedBy,
            standardOutput: collectedOutput,
            standardError: collectedErrors
        )
        #endif
    }

    #if !os(WASI)
    /// Writing to a pipe whose reader has gone raises SIGPIPE, whose default
    /// action is to kill the writer — so a child that exits without reading
    /// its input would take the whole tool down with it. Ignoring the signal
    /// turns that into the `EPIPE` the write above swallows. Done once, on
    /// the first launch, rather than at module load: a process that never
    /// spawns anything keeps the platform's default disposition.
    ///
    /// Windows has no SIGPIPE: a write to a closed pipe already fails with an
    /// error instead of killing the writer, so there is nothing to ignore.
    private static let ignoreBrokenPipes: Void = {
        #if !os(Windows)
        signal(SIGPIPE, SIG_IGN)
        #endif
    }()
    #endif
}
