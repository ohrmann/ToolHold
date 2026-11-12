import Foundation

enum MarkupTool: String, Codable, CaseIterable, Sendable {
    case sql, xml, yaml, html, css, javascript, markdown, preview, mjml
    var id: String { switch self { case .sql: "T-053"; case .xml: "T-054"; case .yaml: "T-055"; case .html: "T-056"; case .css: "T-057"; case .javascript: "T-058"; case .markdown: "T-059"; case .preview: "T-060"; case .mjml: "T-077" } }
    var engineDescription: String {
        switch self {
        case .sql: "sql-formatter 15.9.0 · formatting only, not database validation"
        case .xml: "Foundation XMLParser · XML 1.0 well-formedness, not XSD validation"
        case .yaml: "yaml 2.9.1 / Prettier 3.9.10 · YAML 1.2 Core"
        case .html: "parse5 8.0.1 / Prettier 3.9.10 · conservative HTML printing"
        case .css: "CSSTree 3.2.1 / Prettier 3.9.10 · no cascade optimization"
        case .javascript: "Terser 5.51.2 · no execution, compression or renaming"
        case .markdown: "Marked 18.1.1 · sanitized static HTML"
        case .preview: "parse5 8.0.1 / WebKit · static preview, not HTML validation"
        case .mjml: "mjml-browser 5.4.1 · preview may differ from email clients"
        }
    }
    var isPreview: Bool { [.markdown, .preview, .mjml].contains(self) }
    var canMinify: Bool { [.html, .css, .javascript].contains(self) }
    var canValidate: Bool { [.xml, .yaml].contains(self) }
    var primary: String { isPreview ? (self == .mjml ? "Compile" : "Render") : "Format" }
    var fileExtension: String { switch self { case .sql: "sql"; case .xml: "xml"; case .yaml: "yaml"; case .css: "css"; case .javascript: "js"; default: "html" } }
}
struct MarkupOptions: Codable, Equatable, Sendable {
    var indent = 2
    var dialect = "sql"
    var keywordCase = "preserve"
    var module = false
    var document = false
    var fragmentContext = "body"
    var relaxedHTML = false
    var preserveXMLText = false
    var gfm = true
    var wrap = true
    var live = true
    var viewport = 0
    static let dialects = ["sql", "postgresql", "mysql", "mariadb", "sqlite", "transactsql", "plsql", "bigquery", "snowflake", "redshift", "db2", "hive", "spark", "trino", "duckdb", "clickhouse", "tidb", "singlestoredb", "n1ql"]
    static func dialectName(_ id: String) -> String {
        switch id {
        case "sql": "Standard SQL"
        case "postgresql": "PostgreSQL"
        case "mysql": "MySQL"
        case "mariadb": "MariaDB"
        case "sqlite": "SQLite"
        case "transactsql": "SQL Server / T-SQL"
        case "plsql": "Oracle SQL"
        case "bigquery": "BigQuery"
        case "snowflake": "Snowflake"
        case "redshift": "Redshift"
        case "db2": "DB2"
        case "hive": "Hive"
        case "spark": "Spark"
        case "trino": "Trino"
        case "duckdb": "DuckDB"
        case "clickhouse": "ClickHouse"
        case "tidb": "TiDB"
        case "singlestoredb": "SingleStore"
        case "n1ql": "N1QL"
        default: id
        }
    }
}
struct MarkupRequest: Encodable, Sendable {
    let tool: MarkupTool
    let source: String
    let operation: String
    let options: MarkupOptions
    let nonce: String
    let allowsExternalResources: Bool
    init(tool: MarkupTool, source: String, operation: String = "format", options: MarkupOptions = .init(), nonce: String = UUID().uuidString.lowercased(), allowsExternalResources: Bool = false) {
        self.tool = tool; self.source = source; self.operation = operation; self.options = options; self.nonce = nonce; self.allowsExternalResources = allowsExternalResources
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(tool, forKey: .tool); try c.encode(source, forKey: .source); try c.encode(operation, forKey: .operation); try c.encode(nonce, forKey: .nonce)
        try c.encode(allowsExternalResources, forKey: .allowsExternalResources)
        try c.encode(options.indent, forKey: .indent); try c.encode(options.dialect, forKey: .dialect); try c.encode(options.keywordCase, forKey: .keywordCase)
        try c.encode(options.module, forKey: .module); try c.encode(options.document, forKey: .document); try c.encode(options.fragmentContext, forKey: .fragmentContext)
        try c.encode(options.relaxedHTML, forKey: .relaxedHTML); try c.encode(options.gfm, forKey: .gfm)
    }
    enum Key: String, CodingKey { case tool, source, operation, nonce, indent, dialect, keywordCase, module, document, fragmentContext, relaxedHTML, gfm, allowsExternalResources }
}
struct MarkupDiagnostic: Codable, Sendable, Identifiable {
    var message: String
    var offset: Int?
    var length = 0
    var line: Int?
    var column: Int?
    var severity = "error"
    var id: String { "\(offset ?? -1)|\(line ?? -1)|\(message)" }
    func range(in source: String) -> NSRange? {
        let count = source.utf16.count
        if let offset, offset >= 0, offset <= count { return NSRange(location: offset, length: min(max(0, length), count-offset)) }
        guard let line, line > 0 else { return nil }
        let units = Array(source.utf16); var current = 1, start = 0, i = 0
        while current < line, i < units.count {
            if units[i] == 13 { if i+1 < units.count, units[i+1] == 10 { i += 1 }; current += 1; start = i+1 }
            else if units[i] == 10 { current += 1; start = i+1 }
            i += 1
        }
        guard current == line else { return nil }
        // Line-only anchors never pretend to know the engine's column unit.
        return NSRange(location: start, length: 0)
    }
}
struct MarkupImageReference: Codable, Sendable, Identifiable { let id: String; let reference: String }
struct MarkupResult: Codable, Sendable {
    var status: String
    var output: String?
    var preview: String?
    var diagnostics: [MarkupDiagnostic] = []
    var notices: [String] = []
    var images: [MarkupImageReference]?
    var succeeded: Bool { status == "success" || status == "successWithWarnings" }
    static func failure(_ status: String, _ message: String) -> Self { .init(status: status, diagnostics: [.init(message: message)]) }
    var label: String { switch status { case "ready": "Ready"; case "success": "Completed"; case "successWithWarnings": "Completed with warnings"; case "invalid": "Could not process input"; case "unsupported": "Unsupported input"; case "resourceLimit": "Resource limit reached"; case "cancelled": "Cancelled"; default: "Engine unavailable" } }
}
