import Foundation

// Navigation metadata only. Canonical membership and IDs: docs/TOOL_CATALOG.md.
enum ToolID: String, Codable, CaseIterable, Identifiable, Sendable {
  case t001 = "T-001"
  case t002 = "T-002"
  case t003 = "T-003"
  case t004 = "T-004"
  case t005 = "T-005"
  case t006 = "T-006"
  case t007 = "T-007"
  case t008 = "T-008"
  case t009 = "T-009"
  case t010 = "T-010"
  case t011 = "T-011"
  case t012 = "T-012"
  case t013 = "T-013"
  case t014 = "T-014"
  case t015 = "T-015"
  case t016 = "T-016"
  case t017 = "T-017"
  case t018 = "T-018"
  case t019 = "T-019"
  case t020 = "T-020"
  case t021 = "T-021"
  case t022 = "T-022"
  case t023 = "T-023"
  case t024 = "T-024"
  case t025 = "T-025"
  case t026 = "T-026"
  case t027 = "T-027"
  case t028 = "T-028"
  case t029 = "T-029"
  case t030 = "T-030"
  case t031 = "T-031"
  case t032 = "T-032"
  case t033 = "T-033"
  case t034 = "T-034"
  case t035 = "T-035"
  case t036 = "T-036"
  case t037 = "T-037"
  case t038 = "T-038"
  case t039 = "T-039"
  case t040 = "T-040"
  case t041 = "T-041"
  case t042 = "T-042"
  case t043 = "T-043"
  case t044 = "T-044"
  case t045 = "T-045"
  case t046 = "T-046"
  case t047 = "T-047"
  case t048 = "T-048"
  case t049 = "T-049"
  case t050 = "T-050"
  case t051 = "T-051"
  case t052 = "T-052"
  case t053 = "T-053"
  case t054 = "T-054"
  case t055 = "T-055"
  case t056 = "T-056"
  case t057 = "T-057"
  case t058 = "T-058"
  case t059 = "T-059"
  case t060 = "T-060"
  case t061 = "T-061"
  case t062 = "T-062"
  case t063 = "T-063"
  case t064 = "T-064"
  case t065 = "T-065"
  case t066 = "T-066"
  case t067 = "T-067"
  case t068 = "T-068"
  case t069 = "T-069"
  case t070 = "T-070"
  case t071 = "T-071"
  case t072 = "T-072"
  case t073 = "T-073"
  case t074 = "T-074"
  case t075 = "T-075"
  case t076 = "T-076"
  case t077 = "T-077"
  case t078 = "T-078"
  var id: Self { self }
}

enum ToolCategory: String, Codable, CaseIterable, Identifiable, Sendable {
  case dataJSON
  case encoders
  case generators
  case text
  case dateNetwork
  case formatters  // Persisted ID; display title can change without migrating preferences.
  case colorFiles
  case certificates
  var id: Self { self }
  var title: String {
    switch self {
    case .dataJSON: return "Data & JSON"
    case .encoders: return "Encoders & Inspectors"
    case .generators: return "Generators & Crypto"
    case .text: return "Text & Strings"
    case .dateNetwork: return "Date, Network & Numbers"
    case .formatters: return "Code & Markup"
    case .colorFiles: return "Color & Files"
    case .certificates: return "Certificates & PKI"
    }
  }
  var symbol: String {
    switch self {
    case .dataJSON: return "curlybraces"
    case .encoders: return "arrow.left.arrow.right"
    case .generators: return "sparkles"
    case .text: return "textformat"
    case .dateNetwork: return "clock"
    case .formatters: return "text.alignleft"
    case .colorFiles: return "photo"
    case .certificates: return "checkmark.shield"
    }
  }
}

struct ToolDescriptor: Identifiable, Sendable {
  enum Release: String, Sendable {
    case ga = "GA"
    case gated = "GA-GATE"
    case later = "LATER"
  }
  let id: ToolID
  let title: String
  /// Stable purpose text, independent of implementation status and search synonyms.
  let shortDescription: String
  let category: ToolCategory
  let symbol: String
  let release: Release
  let synonyms: String
  var isImplemented: Bool { id == .t001 || id == .t002 || id == .t003 || id == .t004 || id == .t005 || id == .t006 || id == .t007 || id == .t008 || id == .t009 || id == .t010 || id == .t011 || id == .t012 || id == .t013 || id == .t014 || id == .t015 || id == .t016 || id == .t017 || id == .t018 || id == .t019 || id == .t020 || id == .t021 || id == .t022 || id == .t023 || id == .t024 || id == .t025 || id == .t026 || id == .t027 || id == .t028 || id == .t029 || id == .t030 || id == .t031 || id == .t032 || id == .t033 || id == .t034 || id == .t035 || id == .t036 || id == .t037 || id == .t038 || id == .t039 || id == .t040 || id == .t041 || id == .t042 || id == .t043 || id == .t044 || id == .t045 || id == .t046 || id == .t047 || id == .t048 || id == .t049 || id == .t050 || id == .t051 || id == .t052 || id == .t053 || id == .t054 || id == .t055 || id == .t056 || id == .t057 || id == .t058 || id == .t059 || id == .t060 || id == .t061 || id == .t062 || id == .t063 || id == .t064 || id == .t065 || id == .t066 || id == .t067 || id == .t068 || id == .t069 || id == .t070 || id == .t071 || id == .t072 || id == .t073 || id == .t074 || id == .t075 || id == .t076 || id == .t077 || id == .t078 }
  var displayName: String { id == .t001 ? "JSON Formatter" : title }
  var compactNavigationTitle: String {
    switch id {
    case .t020: "JWT Inspector"
    case .t069: "Certificate Generator"
    case .t070: "CSR Inspector"
    case .t071: "PEM ↔ DER"
    case .t072: "PKCS#12 / PFX"
    case .t073: "Certificate Chain"
    case .t074: "Key Matcher"
    case .t075: "Key Inspector"
    case .t076: "Certificate Expiration"
    default: displayName
    }
  }
}

enum ToolCatalog {
  static let tools: [ToolDescriptor] = [
    .init(
      id: .t001, title: "JSON Formatter / Validator / Minifier",
      shortDescription: "Format and validate", category: .dataJSON,
      symbol: "curlybraces", release: .ga,
      synonyms: "pretty beautify format validate minify json форматирование проверка минификация"),
    .init(
      id: .t002, title: "JSON Tree Viewer",
      shortDescription: "Explore JSON structure", category: .dataJSON, symbol: "list.bullet.indent",
      release: .ga, synonyms: "tree viewer дерево просмотр"),
    .init(
      id: .t003, title: "Structural JSON Diff",
      shortDescription: "Compare JSON structures", category: .dataJSON,
      symbol: "arrow.triangle.branch", release: .ga,
      synonyms: "compare semantic difference сравнение разница"),
    .init(
      id: .t004, title: "JSONPath Explorer",
      shortDescription: "Query nested values", category: .dataJSON, symbol: "magnifyingglass",
      release: .later, synonyms: "query path запрос путь"),
    .init(
      id: .t005, title: "JSON Schema Validator",
      shortDescription: "Check schema compliance", category: .dataJSON, symbol: "checkmark.seal",
      release: .later, synonyms: "schema validation схема"),
    .init(
      id: .t006, title: "JSON ↔ YAML",
      shortDescription: "Convert JSON/YAML data", category: .dataJSON, symbol: "arrow.left.arrow.right",
      release: .ga, synonyms: "yaml convert конвертер"),
    .init(
      id: .t007, title: "JSON ↔ CSV / TSV",
      shortDescription: "Convert objects and tables", category: .dataJSON, symbol: "tablecells", release: .ga,
      synonyms: "csv tsv spreadsheet таблица"),
    .init(
      id: .t008, title: "JSON ↔ XML",
      shortDescription: "Convert JSON/XML documents", category: .dataJSON,
      symbol: "chevron.left.forwardslash.chevron.right", release: .later, synonyms: "xml convert"),
    .init(
      id: .t009, title: "JSON ↔ TOML",
      shortDescription: "Convert JSON/TOML configurations", category: .dataJSON, symbol: "doc.text", release: .later,
      synonyms: "toml convert"),
    .init(
      id: .t010, title: "CSV / TSV Table Viewer",
      shortDescription: "Browse delimited tables", category: .dataJSON, symbol: "tablecells",
      release: .ga, synonyms: "csv tsv table таблица"),
    .init(
      id: .t011, title: "JSON → Models",
      shortDescription: "Generate typed models", category: .dataJSON, symbol: "chevron.left.forwardslash.chevron.right",
      release: .later, synonyms: "models types code Swift TypeScript C# CSharp .NET Java Kotlin модели"),
    .init(
      id: .t012, title: "Base64 Text / Base64URL",
      shortDescription: "Encode and decode text", category: .encoders, symbol: "number",
      release: .ga, synonyms: "b64 base64url encode decode кодирование декодирование"),
    .init(
      id: .t013, title: "Base64 File / Image",
      shortDescription: "Encode files as text", category: .encoders, symbol: "photo",
      release: .later, synonyms: "base64 file image файл изображение"),
    .init(
      id: .t014, title: "URL Percent Encode / Decode",
      shortDescription: "Escape URL components", category: .encoders, symbol: "link",
      release: .ga, synonyms: "percent encoding urlencode urldecode проценты"),
    .init(
      id: .t015, title: "URL Parser & Query Editor",
      shortDescription: "Inspect and edit queries", category: .encoders, symbol: "link.circle",
      release: .ga, synonyms: "query parameters url адрес параметры"),
    .init(
      id: .t016, title: "HTML Entity Encode / Decode",
      shortDescription: "Convert HTML entities", category: .encoders,
      symbol: "textformat.abc", release: .ga, synonyms: "entities html escape сущности"),
    .init(
      id: .t017, title: "String Escape / Unescape",
      shortDescription: "Escape special characters", category: .encoders, symbol: "quote.opening",
      release: .ga, synonyms: "escaping unescaping swift json javascript кавычки экранирование"),
    .init(
      id: .t018, title: "Hex ↔ UTF-8 / Bytes",
      shortDescription: "Inspect text as bytes", category: .encoders, symbol: "number.square",
      release: .ga, synonyms: "hex bytes utf8 байты"),
    .init(
      id: .t019, title: "GZip Compress / Decompress",
      shortDescription: "Compress and decompress data", category: .encoders, symbol: "archivebox",
      release: .later, synonyms: "gzip zip compress сжатие"),
    .init(
      id: .t020, title: "JWT Decoder & Claims Inspector",
      shortDescription: "Inspect token claims", category: .encoders,
      symbol: "person.text.rectangle", release: .ga, synonyms: "jwt token claims exp токен"),
    .init(
      id: .t078, title: "JWT Encoder",
      shortDescription: "Encode token claims", category: .encoders,
      symbol: "key.horizontal", release: .later,
      synonyms: "jwt encode encoder create token header payload claims кодирование генерация токен"),
    .init(
      id: .t021, title: "HTTP Basic Auth Header Builder",
      shortDescription: "Build credential headers", category: .encoders, symbol: "key",
      release: .ga, synonyms: "authorization credentials basic авторизация"),
    .init(
      id: .t022, title: "UUID v4/v7, ULID, NanoID Generator",
      shortDescription: "Create unique identifiers", category: .generators,
      symbol: "number", release: .ga, synonyms: "uuid guid ulid nanoid идентификатор"),
    .init(
      id: .t023, title: "Secure Password Generator",
      shortDescription: "Create random passwords", category: .generators, symbol: "sparkles",
      release: .ga, synonyms: "password secure random пароль"),
    .init(
      id: .t024, title: "Passphrase Generator",
      shortDescription: "Generate memorable secrets", category: .generators, symbol: "text.word.spacing",
      release: .later, synonyms: "passphrase words фраза"),
    .init(
      id: .t025, title: "Random Token / Secret Generator",
      shortDescription: "Generate random secrets", category: .generators,
      symbol: "key.fill", release: .ga, synonyms: "secret token random секрет токен"),
    .init(
      id: .t026, title: "Hash & Checksum Generator",
      shortDescription: "Calculate data fingerprints", category: .generators, symbol: "number.circle",
      release: .ga, synonyms: "sha md5 checksum digest хеш хэш"),
    .init(
      id: .t027, title: "HMAC Generator",
      shortDescription: "Authenticate messages with keys", category: .generators, symbol: "lock.shield",
      release: .later, synonyms: "hmac authentication hash"),
    .init(
      id: .t028, title: "QR Code Generator",
      shortDescription: "Encode content as QR", category: .generators, symbol: "qrcode", release: .ga,
      synonyms: "qr generate код"),
    .init(
      id: .t029, title: "QR Code Decoder",
      shortDescription: "Read codes from images", category: .generators, symbol: "qrcode.viewfinder",
      release: .ga, synonyms: "qr scan read сканировать"),
    .init(
      id: .t030, title: "X.509 Certificate Inspector",
      shortDescription: "Inspect certificate fields", category: .generators,
      symbol: "checkmark.seal", release: .ga, synonyms: "x509 pem der certificate сертификат"),
    .init(
      id: .t031, title: "Password Strength Estimator",
      shortDescription: "Estimate password resilience", category: .generators, symbol: "lock",
      release: .later, synonyms: "password entropy strength стойкость пароль"),
    .init(
      id: .t032, title: "JWT Signature Verifier",
      shortDescription: "Check token signatures", category: .generators, symbol: "signature",
      release: .later, synonyms: "jwt verify signature подпись"),
    .init(
      id: .t033, title: "Text Diff",
      shortDescription: "Compare text changes", category: .text, symbol: "text.alignleft", release: .ga,
      synonyms: "compare difference сравнить текст"),
    .init(
      id: .t034, title: "List / Set Comparator",
      shortDescription: "Find shared list entries", category: .text, symbol: "list.bullet",
      release: .ga, synonyms: "set list intersection union списки множества"),
    .init(
      id: .t035, title: "Regex Tester",
      shortDescription: "Test regular expressions", category: .text, symbol: "asterisk", release: .ga,
      synonyms: "regexp regular expression регулярные выражения"),
    .init(
      id: .t036, title: "String Case Converter",
      shortDescription: "Transform naming conventions", category: .text, symbol: "character.cursor.ibeam",
      release: .ga, synonyms: "camel snake kebab pascal регистр"),
    .init(
      id: .t037, title: "Line Sort & Deduplicate",
      shortDescription: "Organize and deduplicate lines", category: .text,
      symbol: "line.3.horizontal.decrease", release: .ga,
      synonyms: "sort unique deduplicate сортировка дубликаты"),
    .init(
      id: .t038, title: "Unicode / Invisible Character Inspector",
      shortDescription: "Reveal hidden characters", category: .text,
      symbol: "textformat.abc", release: .ga,
      synonyms: "unicode invisible confusables emoji невидимые символы"),
    .init(
      id: .t039, title: "Lorem Ipsum Generator",
      shortDescription: "Generate placeholder paragraphs", category: .text, symbol: "text.alignleft",
      release: .ga, synonyms: "placeholder dummy text текст"),
    .init(
      id: .t040, title: "Mock Data Generator",
      shortDescription: "Generate sample records", category: .text, symbol: "person.2", release: .later,
      synonyms: "fake test data данные"),
    .init(
      id: .t041, title: "Text / Word / Byte Statistics",
      shortDescription: "Measure text size", category: .text, symbol: "textformat.123",
      release: .ga, synonyms: "count words characters bytes подсчёт статистика"),
    .init(
      id: .t042, title: "Find & Replace with Regex",
      shortDescription: "Replace matching patterns", category: .text,
      symbol: "arrow.triangle.2.circlepath", release: .later,
      synonyms: "replace regexp замена поиск"),
    .init(
      id: .t043, title: "Unix Timestamp Converter",
      shortDescription: "Convert epoch times", category: .dateNetwork, symbol: "clock",
      release: .ga, synonyms: "epoch timestamp unix дата время"),
    .init(
      id: .t044, title: "ISO 8601 / RFC 3339 Inspector",
      shortDescription: "Inspect date representations", category: .dateNetwork, symbol: "calendar",
      release: .ga, synonyms: "iso rfc date дата время"),
    .init(
      id: .t045, title: "Timezone Converter",
      shortDescription: "Compare times across zones", category: .dateNetwork, symbol: "globe", release: .ga,
      synonyms: "timezone dst utc зона"),
    .init(
      id: .t046, title: "Date Arithmetic",
      shortDescription: "Calculate date intervals", category: .dateNetwork, symbol: "calendar.badge.clock",
      release: .ga, synonyms: "date add subtract разница дат"),
    .init(
      id: .t047, title: "Cron Parser",
      shortDescription: "Explain schedule expressions", category: .dateNetwork, symbol: "clock.arrow.circlepath",
      release: .later, synonyms: "cron schedule расписание"),
    .init(
      id: .t048, title: "IPv4/IPv6 CIDR Calculator",
      shortDescription: "Calculate subnets and ranges", category: .dateNetwork, symbol: "network",
      release: .ga, synonyms: "ip subnet mask cidr подсеть маска"),
    .init(
      id: .t049, title: "HTTP Status Reference",
      shortDescription: "Look up response meanings", category: .dateNetwork, symbol: "number.circle",
      release: .ga, synonyms: "http status response код ответа"),
    .init(
      id: .t050, title: "MIME Type Lookup",
      shortDescription: "Identify content types", category: .dateNetwork, symbol: "doc.text",
      release: .ga, synonyms: "mime content type тип файла"),
    .init(
      id: .t051, title: "chmod Permissions Calculator",
      shortDescription: "Calculate file access modes", category: .dateNetwork, symbol: "lock.doc",
      release: .ga, synonyms: "chmod octal permissions права"),
    .init(
      id: .t052, title: "Number Base Converter",
      shortDescription: "Convert numeric representations", category: .dateNetwork, symbol: "number",
      release: .ga, synonyms: "binary octal hex decimal системы счисления"),
    .init(
      id: .t053, title: "SQL Formatter",
      shortDescription: "Improve query readability", category: .formatters, symbol: "externaldrive",
      release: .ga, synonyms: "sql query format запрос"),
    .init(
      id: .t054, title: "XML Formatter / Validator",
      shortDescription: "Format and check XML", category: .formatters,
      symbol: "chevron.left.forwardslash.chevron.right", release: .ga,
      synonyms: "xml validate format"),
    .init(
      id: .t055, title: "YAML Formatter / Validator",
      shortDescription: "Format and check YAML", category: .formatters, symbol: "doc.text",
      release: .ga, synonyms: "yaml validate format"),
    .init(
      id: .t056, title: "HTML Formatter / Minifier",
      shortDescription: "Reformat or compact HTML", category: .formatters,
      symbol: "chevron.left.forwardslash.chevron.right", release: .ga,
      synonyms: "html pretty format minify"),
    .init(
      id: .t077, title: "MJML Editor & Preview",
      shortDescription: "Build responsive emails", category: .formatters, symbol: "envelope",
      release: .later, synonyms: "mjml email mail responsive html письмо почта рассылка"),
    .init(
      id: .t057, title: "CSS Formatter / Minifier",
      shortDescription: "Reformat or compact stylesheets", category: .formatters, symbol: "paintbrush",
      release: .later, synonyms: "css style format minify"),
    .init(
      id: .t058, title: "JavaScript Formatter / Minifier",
      shortDescription: "Reformat or compact scripts", category: .formatters,
      symbol: "curlybraces", release: .later, synonyms: "js javascript format minify"),
    .init(
      id: .t059, title: "Markdown Preview",
      shortDescription: "Preview rendered Markdown", category: .formatters, symbol: "square.text.square",
      release: .ga, synonyms: "md markdown preview просмотр"),
    .init(
      id: .t060, title: "HTML Preview",
      shortDescription: "Preview rendered HTML", category: .formatters, symbol: "safari", release: .later,
      synonyms: "html preview просмотр"),
    .init(
      id: .t061, title: "HEX / RGB / HSL Color Converter",
      shortDescription: "Translate color representations", category: .colorFiles,
      symbol: "paintpalette", release: .ga, synonyms: "color colour hex rgb hsl цвет"),
    .init(
      id: .t062, title: "WCAG Contrast Checker",
      shortDescription: "Check text readability", category: .colorFiles,
      symbol: "circle.lefthalf.filled", release: .ga,
      synonyms: "accessibility wcag contrast контраст"),
    .init(
      id: .t063, title: "Image Format Converter",
      shortDescription: "Change image encoding", category: .colorFiles, symbol: "photo",
      release: .ga, synonyms: "image png jpeg heic convert изображение"),
    .init(
      id: .t064, title: "Image Resize / Compress",
      shortDescription: "Adjust dimensions and size", category: .colorFiles,
      symbol: "arrow.up.left.and.arrow.down.right", release: .later,
      synonyms: "image resize compress размер сжатие"),
    .init(
      id: .t065, title: "Image Metadata Inspector / Stripper",
      shortDescription: "Inspect or remove metadata", category: .colorFiles,
      symbol: "info.circle", release: .later, synonyms: "exif metadata privacy метаданные"),
    .init(
      id: .t066, title: "SVG to CSS / Data URI",
      shortDescription: "Embed vector graphics", category: .colorFiles,
      symbol: "chevron.left.forwardslash.chevron.right", release: .later,
      synonyms: "svg data uri vector вектор"),
    .init(
      id: .t067, title: "cURL to Code Converter",
      shortDescription: "Generate request snippets", category: .colorFiles, symbol: "terminal",
      release: .later, synonyms: "curl code command код"),
    .init(
      id: .t068, title: "Connection String Inspector",
      shortDescription: "Inspect database connection parameters", category: .colorFiles,
      symbol: "externaldrive", release: .later, synonyms: "database connection string подключение"),
    .init(
      id: .t069, title: "Self-Signed Development Certificate Generator",
      shortDescription: "Create development certificates", category: .certificates,
      symbol: "checkmark.shield", release: .gated,
      synonyms: "self signed development localhost certificate сертификат"),
    .init(
      id: .t070, title: "CSR Generator & Inspector",
      shortDescription: "Create and inspect requests", category: .certificates,
      symbol: "doc.badge.plus", release: .later,
      synonyms: "csr request certificate запрос сертификат"),
    .init(
      id: .t071, title: "PEM ↔ DER Converter",
      shortDescription: "Change certificate encoding", category: .certificates,
      symbol: "arrow.left.arrow.right", release: .ga, synonyms: "pem der convert сертификат"),
    .init(
      id: .t072, title: "PKCS#12 / PFX Manager",
      shortDescription: "Package certificates and keys", category: .certificates, symbol: "lock.doc",
      release: .later, synonyms: "pkcs12 pfx container контейнер"),
    .init(
      id: .t073, title: "Certificate Chain Validator",
      shortDescription: "Check local certificate chains", category: .certificates,
      symbol: "checkmark.shield", release: .later,
      synonyms: "certificate chain trust цепочка доверие"),
    .init(
      id: .t074, title: "Certificate / Private Key Matcher",
      shortDescription: "Check key correspondence", category: .certificates, symbol: "key",
      release: .gated, synonyms: "certificate private key match ключ сертификат"),
    .init(
      id: .t075, title: "Public / Private Key Inspector",
      shortDescription: "Inspect key properties", category: .certificates,
      symbol: "key.horizontal", release: .later, synonyms: "public private key inspect ключ"),
    .init(
      id: .t076, title: "Batch Certificate Expiration Report",
      shortDescription: "Review certificate expiry dates", category: .certificates,
      symbol: "calendar.badge.exclamationmark", release: .later,
      synonyms: "expiry expiration batch report срок сертификат"),
  ]
  static func tool(_ id: ToolID) -> ToolDescriptor { tools.first { $0.id == id }! }
  static func tools(in category: ToolCategory) -> [ToolID] {
    tools.filter { $0.category == category }.map(\.id)
  }
  static func matches(_ id: ToolID, query: String) -> Bool {
    let tool = tool(id)
    let haystack = normalize(tool.title + " " + tool.synonyms + " " + id.rawValue)
    return normalize(query).split(whereSeparator: { $0.isWhitespace }).allSatisfy {
      haystack.contains($0)
    }
  }
  static func isSearching(_ query: String) -> Bool {
    !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  private static func normalize(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }
}
