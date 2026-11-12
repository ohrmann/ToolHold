import Foundation

/// Native diagnostic presentation only; the JSON parser is not involved.
enum HexBytesEditorDiagnosticAdapter {
    static func make(_ issue: HexBytesIssue?) -> JSONDiagnostic? {
        guard let issue, let range = issue.range, let line = issue.line, let column = issue.column else { return nil }
        return .init(severity: issue.severity == .error ? .error : .warning,
            code: issue.code.rawValue, message: issue.message, range: range, line: line, column: column,
            related: issue.related.map { [.init(.escapeStart, $0)] } ?? [], precision: .exact)
    }
}
