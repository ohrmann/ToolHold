import Foundation

enum URLQueryEditorDiagnosticAdapter {
    static func make(_ issue: URLQueryIssue?, source: String) -> JSONDiagnostic? {
        guard let issue, let range = issue.range else { return nil }
        let (line,column) = URLQueryPresentation.coordinates(source,offset:range.location)
        return .init(severity:issue.severity == .error ? .error : .warning,code:issue.code,message:issue.message,
                     range:range,line:line,column:column,precision:issue.region ? .region : .exact)
    }
}
