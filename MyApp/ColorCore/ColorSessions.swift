import Foundation
import Observation
@MainActor @Observable public final class ColorWorkspace {
    public var input=""
    public var foreground="#000000"
    public var background="#FFFFFF"
    public var backdrop="#FFFFFF"
    public var precision:Int {didSet{defaults.set(precision,forKey:"color.precision")}}
    private let defaults:UserDefaults
    public init(defaults:UserDefaults = .standard) {self.defaults=defaults;precision=defaults.object(forKey:"color.precision") == nil ? 3 : min(6,max(0,defaults.integer(forKey:"color.precision")))}
}
