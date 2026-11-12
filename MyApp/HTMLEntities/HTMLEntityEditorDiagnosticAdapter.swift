import Foundation

/// Native marker presentation only. HTML character-reference processing never invokes the JSON parser.
enum HTMLEntityEditorDiagnosticAdapter {
    static func make(_ issue: HTMLEntityIssue?) -> JSONDiagnostic? {
        guard let issue, let range = issue.range, let line = issue.line, let column = issue.column else { return nil }
        return .init(severity: issue.severity == .error ? .error : .warning,
                     code: issue.code.rawValue, message: issue.message, range: range, line: line, column: column,
                     precision: .exact)
    }
}
