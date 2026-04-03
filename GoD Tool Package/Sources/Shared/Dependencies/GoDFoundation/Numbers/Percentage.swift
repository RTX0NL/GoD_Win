import Foundation

public struct Percentage: CustomStringConvertible, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    public typealias FloatLiteralType = Double
    
    public let value: Double
    
    public init(_ value: Double) {
        self.value = value
    }
    
    public init(floatLiteral value: Double) {
        self.value = value
    }
    
    public init(integerLiteral value: Int) {
        self.value = Double(value)
    }
    
    public var description: String {
        return String(format: "%.1f%%", value)
    }
}
