import Foundation

#if canImport(NumberCore)
  import NumberCore
#endif
public enum NetworkTool: Int, Sendable {
  case cidr = 48
  case http, mime, chmod
}
public struct NetworkCalculationRequest: Sendable {
  public var tool: NetworkTool
  public var lastPermissionBits: UInt16 = 0
  public var octalDraft = "", symbolicDraft = ""
  public var input = "", comparison = "", expression = ""
  public var category = 0, mimeMode = "All", contentType = false, symbolic = false,
    directory = false
  public init(tool: NetworkTool) { self.tool = tool }
}
public enum NetworkCalculation {
  public static func process(_ r: NetworkCalculationRequest) throws -> CalculationReport {
    try Task.checkCancellation()
    switch r.tool {
    case .cidr:
      let network = try IPNetwork(r.input)
      var report = try network.report(comparison: r.comparison)
      report.notes += try NetworkReferences.classify(network)
      return report
    case .http: return try NetworkReferences.httpSearch(r.input, category: r.category)
    case .mime:
      return try r.contentType
        ? ContentTypeParser.parse(r.input).report
        : NetworkReferences.mimeSearch(r.input, mode: r.mimeMode)
    case .chmod:
      let mode = try r.symbolic ? PermissionMode(symbolic: r.input) : PermissionMode(octal: r.input)
      var report = CalculationReport(
        rows: [
          .init("octal", "Octal", mode.octal), .init("symbolic", "Symbolic", mode.symbolic),
          .init("command", "Command template", "chmod " + mode.octal + " <path>"),
        ],
        notes: [
          "Pure 12-bit calculation; no files are accessed. Special bits and directory behavior depend on filesystem policy. No umask is inferred."
        ], status: "Calculated")
      if !r.expression.isEmpty {
        let changed = try mode.applying(r.expression, directory: r.directory)
        report.rows += [
          .init("previewOctal", "Preview · octal", changed.octal),
          .init("previewSymbolic", "Preview · symbolic", changed.symbolic),
        ]
        if changed == mode {
          report.notes.append(
            "This expression does not change the mode. Special s applies only to u/g; t only to o. X requires a directory or an existing execute bit."
          )
        }
        report.notes.append("Preview only. Apply explicitly to change the working mode.")
      }
      return report
    }
  }
}
