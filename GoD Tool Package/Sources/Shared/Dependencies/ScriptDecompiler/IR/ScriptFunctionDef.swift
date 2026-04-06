import GoDFoundation

/// Definition of a script built-in function for decompilation purposes.
/// Used by both Colosseum (flat function IDs) and XD (class.method IDs).
public struct ScriptFunctionDef: Codable, Equatable {
    /// The function's display name
    public let name: String
    /// Parameter definitions (ordered)
    public let parameters: [ParameterDef]
    /// Return type (nil if void)
    public let returnType: ScriptParamType?
    /// Optional description/hint
    public let hint: String?

    public init(name: String, parameters: [ParameterDef] = [], returnType: ScriptParamType? = nil, hint: String? = nil) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.hint = hint
    }

    public struct ParameterDef: Codable, Equatable {
        public let name: String
        public let type: ScriptParamType

        public init(name: String, type: ScriptParamType) {
            self.name = name
            self.type = type
        }
    }
}
