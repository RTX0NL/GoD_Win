import GoDFoundation

extension ColoXD {
    struct BuildConfig: Codable {
        enum Operations: Codable {
            case pass
        }
        
        let operations: [OperationConfig<Operations>]
    }
}
