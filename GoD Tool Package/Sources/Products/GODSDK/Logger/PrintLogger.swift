import GoDFoundation

final class PrintLogger: Logger {
    public let verbose: Bool
    
    init(verbose: Bool = false) {
        self.verbose = verbose
    }
    
    func log(_ log: GoDFoundation.Log) {
        if !verbose, case .info = log { return }
        
        switch log {
        case .info(let message):
            print("INFO: \(message)")
        case .warning(let message):
            print("WARNING: \(message)")
        case .error(let message):
            print("ERROR: \(message)")
        case .taskStatus(let taskName, let status):
            switch status {
            case .started:
                print("TASK \(taskName): STARTED")
            case .completed(let success):
                print("TASK \(taskName): \(success ? "COMPLETED" : "FAILED")")
            case .progress(let percentage):
                print("TASK \(taskName): \(percentage)")
            }
        }
    }
}
