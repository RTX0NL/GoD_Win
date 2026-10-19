//
//  RunMonitor.swift
//  GODOps
//
//  Watches one run — a config, a single operation, or a project setup — for
//  a caller that needs more than "it finished". The MCP server uses it to
//  stop a run its client cancelled, to stream progress, and to tell the
//  client which files the run wrote.
//
//  It sees a run through two seams. Dispatch tells it when each operation
//  starts and ends, and the run's `StreamedFileSystem` asks it before every
//  change to the disk. The second is what makes cancelling work at all:
//  operations are long synchronous loops with no notion of a task, but they
//  write through the tree, so refusing the next change stops them writing
//  within one file of the cancel. The refusal comes *before* the change, so
//  even engine code that swallows write errors writes nothing more — and the
//  next operation boundary throws regardless, so a cancelled run never comes
//  back as a success.
//

import Foundation
import GoDFoundation

/// Something that happened in a run, with where the run had got to.
public struct RunProgress: Equatable {
    public enum Event: Equatable {
        case operationStarted
        case operationCompleted
        case fileWritten(File)
    }

    public let event: Event
    /// The running operation's 1-based position, and how many the run has.
    /// Both are 0 for a run that isn't made of operations (project setup).
    public let operationIndex: Int
    public let operationCount: Int
    public let operation: OperationName?
    /// Distinct files written so far in the whole run.
    public let filesWritten: Int

    public init(event: Event, operationIndex: Int, operationCount: Int, operation: OperationName?, filesWritten: Int) {
        self.event = event
        self.operationIndex = operationIndex
        self.operationCount = operationCount
        self.operation = operation
        self.filesWritten = filesWritten
    }

    /// One line for a person watching the run.
    public var summary: String {
        let position = operation.map { "Operation \(operationIndex) of \(operationCount) (\($0.rawValue))" }
        let files = RunMonitor.count(filesWritten, "file")
        switch event {
        case .operationStarted:
            return "\(position ?? "Run") started"
        case .operationCompleted:
            return "\(position ?? "Run") done; \(files) written so far"
        case .fileWritten(let file):
            let written = "\(files) written, latest \(file.fileName)"
            return position.map { "\($0): \(written)" } ?? written
        }
    }
}

public final class RunMonitor: FileSystemObserver, @unchecked Sendable {

    private let onProgress: ((RunProgress) -> Void)?

    // Cancelling comes from another thread than the run's, and a few
    // pipelines write from worker threads, so all state is behind the lock.
    private let lock = NSLock()
    private var cancelled = false
    private var written: [File] = []
    private var writtenPaths: Set<String> = []
    private var operationIndex = 0
    private var operationCount = 0
    private var operation: OperationName?

    /// `onProgress` is called on the run's thread for every operation start
    /// and end and every file written; throttling is the receiver's business.
    public init(onProgress: ((RunProgress) -> Void)? = nil) {
        self.onProgress = onProgress
    }

    /// Stops the run at its next change to the disk or its next operation
    /// boundary, whichever comes first. Safe to call from any thread.
    public func cancel() {
        locked { cancelled = true }
    }

    public var isCancelled: Bool {
        locked { cancelled }
    }

    /// Each file the run wrote, once, in the order first written.
    public var writtenFiles: [File] {
        locked { written }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public func checkCancellation() throws {
        if isCancelled { throw CancellationError() }
    }

    // MARK: - Seams

    public func willChange(_ change: FileSystemChange) throws {
        try checkCancellation()
        guard let file = change.writtenFile else { return }
        let isNew = locked { writtenPaths.insert(file.path).inserted }
        guard isNew else { return }
        locked { written.append(file) }
        report(.fileWritten(file))
    }

    func operationStarted(_ name: OperationName, index: Int, of count: Int) throws {
        try checkCancellation()
        locked {
            operation = name
            operationIndex = index
            operationCount = count
        }
        report(.operationStarted)
    }

    /// Throws if the run was cancelled while the operation ran, even though
    /// it got to the end: what it wrote after the cancel was refused.
    func operationCompleted() throws {
        try checkCancellation()
        report(.operationCompleted)
    }

    private func report(_ event: RunProgress.Event) {
        guard let onProgress else { return }
        let progress = locked {
            RunProgress(
                event: event,
                operationIndex: operationIndex,
                operationCount: operationCount,
                operation: operation,
                filesWritten: written.count
            )
        }
        onProgress(progress)
    }

    // MARK: - Output summary

    /// What the run wrote, in a few lines: how many files, under which
    /// folder, and how many in each folder below it, two levels deep.
    public func outputSummary(maxFolders: Int = 20) -> String {
        let files = writtenFiles
        guard let first = files.first else { return "Wrote no files." }
        if files.count == 1 { return "Wrote 1 file: \(first.nativePath)" }

        let folders = files.map { components(of: $0.parentFolder?.path ?? "/") }
        let root = folders.dropFirst().reduce(folders[0]) { common, next in
            Array(zip(common, next).prefix(while: { $0.0 == $0.1 }).map(\.0))
        }

        var counts: [String: Int] = [:]
        for folder in folders {
            let below = folder.dropFirst(root.count).prefix(2)
            counts[below.isEmpty ? "" : below.joined(separator: "/"), default: 0] += 1
        }

        let rootFolder = Folder("/" + root.joined(separator: "/"))
        var lines = ["Wrote \(Self.count(files.count, "file")) under \(rootFolder.nativePath):"]
        let groups = counts.keys.sorted()
        for group in groups.prefix(maxFolders) {
            lines.append("  \(group.isEmpty ? "(top level)" : group): \(Self.count(counts[group] ?? 0, "file"))")
        }
        if groups.count > maxFolders {
            lines.append("  … and \(groups.count - maxFolders) more folders")
        }
        return lines.joined(separator: "\n")
    }

    private func components(of path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    /// "1 file", "1,234 files".
    static func count(_ value: Int, _ noun: String) -> String {
        let digits = String(value)
        var grouped = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        return "\(grouped) \(noun)\(value == 1 ? "" : "s")"
    }
}
