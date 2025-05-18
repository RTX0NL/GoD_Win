import GoDFoundation
import GoDEngine
import Structs

public final class FsysTOC: FileFormat {
    public static var formatName = "FsysTOC"
    
    var fsysIDsByFilename = [String: Int]()
    
    var enumeration: Enum {
        Enum(
            name: GeniusSonorityEngine.Enums.Defaults.fsysGroupIDsColoEnum.name,
            allowUnknownCases: GeniusSonorityEngine.Enums.Defaults.fsysGroupIDsColoEnum.allowUnknownCases,
            values: fsysIDsByFilename.map { Enum.Case(name: $0.key, rawValue: $0.value) },
            propertyType: GeniusSonorityEngine.Enums.Defaults.fsysGroupIDsColoEnum.propertyType
        )
    }
    
    init(fsysIDsByFilename: [String : Int] = [String: Int]()) {
        self.fsysIDsByFilename = fsysIDsByFilename
    }
    
    init(tocData: GoDData, game: GSGame) throws {
        
        
    }
    
    func tocData(for game: GSGame) throws -> GoDData {
        .none
    }
}
