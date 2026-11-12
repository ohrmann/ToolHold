import Foundation

/// Presentation bridge only. Base64Core never claims to have parsed JSON.
enum Base64EditorDiagnosticAdapter {
    static func make(_ issue: Base64Issue?) -> JSONDiagnostic? {
        guard let issue, let range = issue.range, let line = issue.line, let column = issue.column else { return nil }
        return .init(severity: issue.severity == .error ? .error : .warning,
                     code: issue.code.rawValue, message: issue.message, range: range, line: line, column: column)
    }
}
