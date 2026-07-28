import Foundation
import GoDFoundation

/// Console logger for the CLI. Diagnostics (`warning` / `error`, and the
/// FAILED task status) go to stderr so a caller can redirect them
/// independently of the tool's normal progress output on stdout.
final class PrintLogger: Logger {
    public let verbose: Bool

    init(verbose: Bool = false) {
        self.verbose = verbose
    }

    private func printErr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    func log(_ log: GoDFoundation.Log) {
        if !verbose, case .info = log { return }

        switch log {
        case .info(let message):
            print("INFO: \(message)")
        case .warning(let message):
            printErr("WARNING: \(message)")
        case .error(let message):
            printErr("ERROR: \(message)")
        case .taskStatus(let taskName, let status):
            switch status {
            case .started:
                print("TASK \(taskName): STARTED")
            case .completed(let success):
                if success {
                    print("TASK \(taskName): COMPLETED")
                } else {
                    printErr("TASK \(taskName): FAILED")
                }
            case .progress(let percentage):
                print("TASK \(taskName): \(percentage)")
            }
        }
    }
}
