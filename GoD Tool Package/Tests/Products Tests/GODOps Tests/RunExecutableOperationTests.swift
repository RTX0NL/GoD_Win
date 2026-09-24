//
//  RunExecutableOperationTests.swift
//  GODOpsTests
//
//  Exercises the runExecutable operation against real programs. Unlike the
//  other operation tests these launch something — a process is the thing
//  under test, so there is nothing to synthesize — but only the small POSIX
//  utilities every host has, and each test skips rather than fails when its
//  program isn't there.
//
//  Outputs still land in an InMemoryFST, so nothing is written to disk.
//

import XCTest
import Foundation
import GoDFoundation
@testable import GODOps

final class RunExecutableOperationTests: XCTestCase {

    // MARK: - Helpers

    /// The first of `candidates` that exists and is executable, or a skip.
    /// Paths differ between hosts (`/bin/echo` vs `/usr/bin/echo`), and a
    /// missing utility says nothing about the operation.
    private func program(_ candidates: String..., file: StaticString = #filePath, line: UInt = #line) throws -> File {
        let manager = FileManager.default
        guard let found = candidates.first(where: { manager.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("none of \(candidates.joined(separator: ", ")) is executable on this host")
        }
        return File(found)
    }

    private var echo: File { get throws { try program("/bin/echo", "/usr/bin/echo") } }
    private var cat: File { get throws { try program("/bin/cat", "/usr/bin/cat") } }
    private var falseProgram: File { get throws { try program("/usr/bin/false", "/bin/false") } }

    private func run(_ config: RunExecutable.Config, in fst: InMemoryFST) throws {
        try RunExecutable.run(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
    }

    private func text(at path: String, in fst: InMemoryFST, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let data = try XCTUnwrap(fst.readFile(at: File(path))?.allData, "expected \(path)", file: file, line: line)
        return String(decoding: data.rawBytes, as: UTF8.self)
    }

    // MARK: - Arguments

    func testPassesArgumentsAndCapturesStandardOutput() throws {
        let fst = InMemoryFST()
        try run(.init(
            executablePath: try echo,
            arguments: ["Phenac", "City"],
            outputFile: File("/project/out.txt")
        ), in: fst)

        XCTAssertEqual(try text(at: "/project/out.txt", in: fst), "Phenac City\n")
    }

    /// Each element is one argument, whatever is inside it. A shell would
    /// split this on the space; there is no shell here, so `echo` prints it
    /// as the single word it was given.
    func testAnArgumentIsNeverSplitOnSpaces() throws {
        let fst = InMemoryFST()
        try run(.init(
            executablePath: try echo,
            arguments: ["Phenac City"],
            outputFile: File("/project/out.txt")
        ), in: fst)

        XCTAssertEqual(try text(at: "/project/out.txt", in: fst), "Phenac City\n")
    }

    func testRunsWithNoArgumentsAtAll() throws {
        let fst = InMemoryFST()
        try run(.init(executablePath: try echo, outputFile: File("/project/out.txt")), in: fst)
        XCTAssertEqual(try text(at: "/project/out.txt", in: fst), "\n")
    }

    // MARK: - Standard input

    func testWritesStandardInputLinesAndClosesTheStream() throws {
        let fst = InMemoryFST()
        try run(.init(
            executablePath: try cat,
            standardInput: ["alpha", "beta", "gamma"],
            outputFile: File("/project/out.txt")
        ), in: fst)

        // `cat` returning at all is the other half of this: the stream was
        // closed, so it read to EOF instead of waiting for more.
        XCTAssertEqual(try text(at: "/project/out.txt", in: fst), "alpha\nbeta\ngamma\n")
    }

    /// No `standardInput` still closes the stream immediately rather than
    /// handing the child GODDESS's own — a `cat` that inherited the terminal
    /// would block here forever.
    func testAbsentStandardInputIsAnImmediateEndOfFile() throws {
        let fst = InMemoryFST()
        try run(.init(executablePath: try cat, outputFile: File("/project/out.txt")), in: fst)
        XCTAssertEqual(try text(at: "/project/out.txt", in: fst), "")
    }

    /// Input and output larger than a pipe buffer (64 KB on most hosts).
    /// Writing all the input before reading any output, or reading the
    /// streams in turn, deadlocks here rather than failing an assertion.
    func testStreamsMoreThanAPipeBufferWithoutDeadlocking() throws {
        let fst = InMemoryFST()
        let lines = (0 ..< 20_000).map { "line \($0) of the purify chamber" }
        try run(.init(
            executablePath: try cat,
            standardInput: lines,
            outputFile: File("/project/out.txt")
        ), in: fst)

        let echoed = try text(at: "/project/out.txt", in: fst)
        XCTAssertEqual(echoed, lines.map { $0 + "\n" }.joined())
        XCTAssertGreaterThan(echoed.utf8.count, 0x10000, "the sample has to exceed a pipe buffer to mean anything")
    }

    // MARK: - Exit status

    func testThrowsWhenTheProgramExitsNonZero() throws {
        let fst = InMemoryFST()
        XCTAssertThrowsError(try run(.init(executablePath: try falseProgram), in: fst)) { error in
            guard case let RunExecutableErrors.exitedNonZero(_, code, _, _) = error else {
                return XCTFail("expected exitedNonZero, got \(error)")
            }
            XCTAssertEqual(code, 1)
        }
    }

    func testToleratesANonZeroExitWhenAsked() throws {
        let fst = InMemoryFST()
        XCTAssertNoThrow(try run(
            .init(executablePath: try falseProgram, failOnNonZeroExit: false),
            in: fst
        ))
    }

    /// The output of a failed run is what says why it failed, so it is
    /// written before the exit code is judged.
    func testCapturesOutputEvenWhenTheProgramFails() throws {
        let shell = try program("/bin/sh")
        let fst = InMemoryFST()
        XCTAssertThrowsError(try run(.init(
            executablePath: shell,
            arguments: ["-c", "echo diagnosis; exit 3"],
            outputFile: File("/project/out.txt")
        ), in: fst))

        XCTAssertEqual(try text(at: "/project/out.txt", in: fst), "diagnosis\n")
    }

    /// A failing program's own account of itself is quoted in the error,
    /// which is the whole point of collecting standard error.
    func testTheErrorQuotesTheProgramsStandardError() throws {
        let shell = try program("/bin/sh")
        let fst = InMemoryFST()
        XCTAssertThrowsError(try run(.init(
            executablePath: shell,
            arguments: ["-c", "echo 'no such rom' >&2; exit 2"]
        ), in: fst)) { error in
            guard case let RunExecutableErrors.exitedNonZero(_, code, standardError, _) = error else {
                return XCTFail("expected exitedNonZero, got \(error)")
            }
            XCTAssertEqual(code, 2)
            XCTAssertTrue(standardError.contains("no such rom"), standardError)
            XCTAssertTrue("\(error)".contains("no such rom"), "\(error)")
        }
    }

    /// A program killed by a signal never chose a status, so there is
    /// nothing for `failOnNonZeroExit` to tolerate.
    func testASignalIsAnErrorEvenWithFailuresTolerated() throws {
        let shell = try program("/bin/sh")
        let fst = InMemoryFST()
        XCTAssertThrowsError(try run(.init(
            executablePath: shell,
            arguments: ["-c", "kill -TERM $$"],
            failOnNonZeroExit: false
        ), in: fst)) { error in
            guard case let RunExecutableErrors.killedBySignal(_, signal, _, _) = error else {
                return XCTFail("expected killedBySignal, got \(error)")
            }
            XCTAssertEqual(signal, SIGTERM)
        }
    }

    // MARK: - Working directory

    func testRunsInTheGivenWorkingDirectory() throws {
        let shell = try program("/bin/sh")
        let fst = InMemoryFST()
        // `/tmp` is a symlink to `/private/tmp` on macOS, so compare against
        // what the shell itself reports rather than the path we passed.
        try run(.init(
            executablePath: shell,
            arguments: ["-c", "pwd"],
            workingDirectory: Folder("/tmp"),
            outputFile: File("/project/pwd.txt")
        ), in: fst)

        let reported = try text(at: "/project/pwd.txt", in: fst).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(
            URL(fileURLWithPath: reported).resolvingSymlinksInPath().path,
            URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath().path
        )
    }

    func testThrowsWhenTheWorkingDirectoryIsMissing() throws {
        let fst = InMemoryFST()
        XCTAssertThrowsError(try run(.init(
            executablePath: try echo,
            workingDirectory: Folder("/no/such/folder/anywhere")
        ), in: fst)) { error in
            guard case let RunExecutableErrors.couldNotLaunch(reason, _) = error else {
                return XCTFail("expected couldNotLaunch, got \(error)")
            }
            XCTAssertTrue(reason.contains("/no/such/folder/anywhere"), reason)
        }
    }

    // MARK: - Launch failures

    func testThrowsWhenTheExecutableIsMissing() {
        let fst = InMemoryFST()
        XCTAssertThrowsError(try run(.init(executablePath: File("/no/such/program")), in: fst)) { error in
            guard case let RunExecutableErrors.couldNotLaunch(reason, _) = error else {
                return XCTFail("expected couldNotLaunch, got \(error)")
            }
            XCTAssertTrue(reason.contains("/no/such/program"), reason)
        }
    }

    /// A file that exists but has no executable bit fails with its own
    /// message — "not executable" is a different problem from "not there",
    /// and sending someone to `chmod` is the whole value of saying so.
    func testThrowsWhenTheFileIsNotExecutable() throws {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GODDESS-not-executable-\(UUID().uuidString)")
        try Data("#!/bin/sh\n".utf8).write(to: scratch)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: scratch.path)

        let fst = InMemoryFST()
        XCTAssertThrowsError(try run(.init(executablePath: File(nativePath: scratch.path)), in: fst)) { error in
            guard case let RunExecutableErrors.couldNotLaunch(reason, _) = error else {
                return XCTFail("expected couldNotLaunch, got \(error)")
            }
            XCTAssertTrue(reason.contains("not executable"), reason)
        }
    }
}
