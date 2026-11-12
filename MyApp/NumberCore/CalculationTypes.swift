import Foundation

public struct CalculationIssue: Error, Equatable, Sendable {
  public enum Kind: String, Sendable { case invalid, unsupported, resource, notReady, needsChoice }
  public let kind: Kind
  public let message: String
  public let field: String
  public let range: NSRange?
  public init(
    _ kind: Kind = .invalid, _ message: String, field: String = "Input", range: NSRange? = nil
  ) {
    self.kind = kind
    self.message = message
    self.field = field
    self.range = range
  }
}
public struct CalculationRow: Identifiable, Equatable, Sendable {
  public let id: String
  public let label: String
  public let value: String
  public let detail: String
  public init(_ id: String, _ label: String, _ value: String, detail: String = "") {
    self.id = id
    self.label = label
    self.value = value
    self.detail = detail
  }
}
public struct CalculationChoice: Identifiable, Equatable, Sendable {
  public let id: String
  public let label: String
  public init(_ id: String, _ label: String) {
    self.id = id
    self.label = label
  }
}
public struct CalculationReport: Equatable, Sendable {
  public var choicesForResult = false
  public var rows: [CalculationRow]
  public var notes: [String]
  public var choices: [CalculationChoice]
  public var status: String
  public init(
    rows: [CalculationRow] = [], notes: [String] = [], choices: [CalculationChoice] = [],
    status: String = "Ready"
  ) {
    self.rows = rows
    self.notes = notes
    self.choices = choices
    self.status = status
  }
  public var text: String {
    (rows.map { "\($0.label): \($0.value)" + ($0.detail.isEmpty ? "" : "\n\($0.detail)") } + notes)
      .joined(separator: "\n")
  }
}
public enum CalculationInput {
  public static func integer(_ raw: String, field: String, range: ClosedRange<Int>) throws -> Int {
    let s = try trimmed(raw, limit: 32, field: field)
    guard !s.isEmpty else {
      throw CalculationIssue(.notReady, "Enter a whole number.", field: field)
    }
    guard s.utf8.allSatisfy({ (48...57).contains($0) }), let n = Int(s), range.contains(n) else {
      throw CalculationIssue(
        .invalid, "Use a whole number in \(range.lowerBound)…\(range.upperBound).", field: field)
    }
    return n
  }

  public static func trimmed(_ raw: String, limit: Int, field: String = "Input") throws -> String {
    guard raw.utf16.count <= limit else {
      throw CalculationIssue(.resource, "Limit: \(limit) UTF-16 units.", field: field)
    }
    try Task.checkCancellation()
    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
