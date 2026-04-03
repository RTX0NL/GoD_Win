import Foundation

public enum Log {
    public enum TaskStatus {
        case started
        case completed(Bool)
        case progress(Percentage)
    }
    
    case info(String)
    case warning(String)
    case error(String)
    case taskStatus(taskName: String, status: TaskStatus)
}


public protocol Logger {
    func log(_ category: Log)
}
