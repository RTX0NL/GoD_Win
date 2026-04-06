import Structs

/// Wraps a StructData value with its associated label name.
/// Used for table entries and individual typed values where each entry
/// may have its own symbol/label at its address.
public struct LabeledData {
    /// The symbol/label at this entry's address (nil if unlabeled)
    public let label: String?
    /// The struct data for this entry
    public let data: StructData

    public init(label: String?, data: StructData) {
        self.label = label
        self.data = data
    }
}
