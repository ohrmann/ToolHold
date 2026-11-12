import Foundation

@MainActor enum DateNetworkWorkspaces {
  static func date(_ tool: DateTool, defaults: UserDefaults = .standard) -> CalculationWorkspace<
    DateCalculationRequest
  > {
    var r = DateCalculationRequest(tool: tool)
    r.unit =
      TimestampUnit(rawValue: defaults.integer(forKey: "developerToolbox.date.unit")) ?? .seconds
    r.cronDialect =
      CronDialect(rawValue: defaults.string(forKey: "developerToolbox.date.cronDialect") ?? "")
      ?? .unix
    return .init(r, automatic: tool != .cron, process: DateCalculations.process)
  }
  static func network(_ tool: NetworkTool) -> CalculationWorkspace<NetworkCalculationRequest> {
    var r = NetworkCalculationRequest(tool: tool)
    if tool == .chmod { r.input = "0000" }
    return .init(r, process: NetworkCalculation.process)
  }
  static func number(defaults: UserDefaults = .standard) -> CalculationWorkspace<
    NumberCalculationRequest
  > {
    var r = NumberCalculationRequest()
    r.uppercase = defaults.object(forKey: "developerToolbox.number.uppercase") as? Bool ?? true
    r.group = defaults.bool(forKey: "developerToolbox.number.group")
    return .init(r, process: NumberCalculation.process)
  }
}
