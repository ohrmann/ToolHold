import Foundation

#if canImport(NumberCore)
  import NumberCore
#endif

public struct HTTPStatusRecord: Codable, Identifiable, Sendable {
  public let id: String, low: Int, high: Int, name: String, references: [String]
  public var explanation: String {
    switch low / 100 {
    case 1:
      return
        "Interim response: processing continues. Check the referenced specification for this code."
    case 2:
      return
        "Successful response. The exact result and response body depend on the method and code."
    case 3:
      return
        "Redirection: additional action may be needed; do not assume every redirect preserves the method."
    case 4:
      return
        "The request could not be fulfilled as submitted. Inspect authentication, request content and the specific code."
    default:
      return
        "The server could not complete the request. Retry safety depends on the method and application."
    }
  }
}
public struct MIMERecord: Codable, Identifiable, Sendable {
  public let id: String, name: String, references: [String]
}
public struct MIMEExtension: Codable, Identifiable, Sendable {
  public let id: String, `extension`: String, type: String, source: String
}
public struct IPSpecialRecord: Codable, Identifiable, Sendable {
  public let id: String, name: String, source: String, destination: String, forwardable: String,
    globalReachable: String, reserved: String, termination: String, notes: [String],
    references: [String]
}
public enum NetworkReferences {
  static func read<T: Decodable>(_ name: String, _ type: T.Type) throws -> T {
    #if SWIFT_PACKAGE
      let bundle = Bundle.module
    #else
      let bundle = Bundle.main
    #endif
    guard let url = bundle.url(forResource: name, withExtension: "json") else {
      throw CalculationIssue(.resource, "Bundled registry is unavailable: \(name).")
    }
    return try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }
  private static let httpCache = Result { try read("http-status", [HTTPStatusRecord].self) }
  private static let mimeCache = Result { try read("media-types", [MIMERecord].self) }
  private static let extensionsCache = Result { try read("mime-extensions", [MIMEExtension].self) }
  private static let ipCache = Result {
    try read("ipv4-special", [IPSpecialRecord].self) + read("ipv6-special", [IPSpecialRecord].self)
  }
  public static func http() throws -> [HTTPStatusRecord] { try httpCache.get() }
  public static func mime() throws -> [MIMERecord] { try mimeCache.get() }
  public static func extensions() throws -> [MIMEExtension] { try extensionsCache.get() }
  public static func special() throws -> [IPSpecialRecord] { try ipCache.get() }
  public static func httpSearch(_ raw: String, category: Int = 0) throws -> CalculationReport {
    let q = try CalculationInput.trimmed(raw, limit: 256, field: "Search").lowercased()
    if let code = Int(q), !(100...599).contains(code) {
      throw CalculationIssue(.invalid, "HTTP status codes are 100…599.")
    }
    let found = try http().filter { r in
      (category == 0 || r.low / 100 == category)
        && (q.isEmpty || r.name.lowercased().contains(q) || r.id.contains(q)
          || Int(q).map { (r.low...r.high).contains($0) } == true)
    }
    return .init(
      rows: found.map {
        .init(
          $0.id, $0.id, $0.name,
          detail: ($0.name.contains("Unassigned")
            ? "No registered meaning in this snapshot." : $0.explanation) + "\n"
            + $0.references.joined(separator: "\n"))
      },
      notes: [
        "IANA snapshot · updated 2025-09-15 · retrieved 2026-10-22. Temporary registrations retain their published expiry; this snapshot does not update automatically.",
        "Source: https://www.iana.org/assignments/http-status-codes/",
      ], status: found.isEmpty ? "No matches" : "\(found.count) registry entries")
  }
  public static func mimeSearch(_ raw: String, mode: String = "All") throws -> CalculationReport {
    let q = try CalculationInput.trimmed(raw, limit: 256, field: "Search").lowercased()
    let types = try mime()
    let mappings = try extensions()
    let leaf = q.split(separator: "/").last.map(String.init) ?? q
    let ext = leaf.split(separator: ".").last.map(String.init) ?? leaf
    let mapped = mappings.filter { !$0.extension.isEmpty && $0.extension == ext }
    var rows: [CalculationRow] = []
    if mode != "Extensions" {
      rows += types.filter {
        q.isEmpty || (q.hasSuffix("/*") ? $0.id.hasPrefix(String(q.dropLast())) : $0.id.contains(q))
      }.map { record in
        let exts = mappings.filter { $0.type == record.id }.map { "." + $0.extension }.joined(
          separator: ", ")
        return .init(
          "type:" + record.id, record.name, "IANA registered",
          detail:
            "Top-level: \(record.id.split(separator: "/").first ?? "") · Suffix: \(record.id.contains("+") ? String(record.id.split(separator: "+").last!) : "none")\n"
            + (exts.isEmpty
              ? "No extension mapping in the curated set." : "Curated extensions: " + exts) + "\n"
            + record.references.joined(separator: "\n"))
      }
    }
    if mode != "Media Types" {
      let list = q.isEmpty ? mappings : mapped
      rows += list.map {
        .init("ext:" + $0.id, "." + $0.extension, $0.type, detail: "Filename hint · " + $0.source)
      }
    }
    if q.hasSuffix(".tar.gz") && mode != "Media Types" {
      rows.append(
        .init(
          "compound:tar.gz", "Compound filename .tar.gz",
          "gzip-compressed tar archive (filename convention)",
          detail:
            "Outer extension .gz is listed separately. The filename does not verify an inner tar archive; no content inspection is performed."
        ))
    }
    return .init(
      rows: rows,
      notes: [
        "IANA media types · updated 2026-10-20 · retrieved 2026-10-22. Extension mappings are a separate curated set; multiple answers are retained.",
        "A filename or suffix does not prove content type or safety. Structured suffixes such as +json describe representation, not trust.",
      ], status: rows.isEmpty ? "No matches" : "\(rows.count) entries")
  }
  public static func classify(_ network: IPNetwork) throws -> [String] {
    let matches = try special().compactMap { record -> (IPSpecialRecord, IPNetwork)? in
      guard let block = try? IPNetwork(record.id), block.overlaps(network) else { return nil }
      return (record, block)
    }.sorted { $0.1.prefix > $1.1.prefix }
    var result = [
      "Special-purpose registry snapshot: 2025-10-09 (retrieved 2026-10-22). Classification does not establish reachability or firewall policy."
    ]
    for (r, block) in matches {
      result.append(
        "\(block.contains(network) ? "Contains this range" : "Overlaps part of this range"): \(r.id) · \(r.name) · globally reachable: \(r.globalReachable)\(r.termination.isEmpty ? "" : " · termination: "+r.termination). More-specific entries take precedence.\n"
          + r.references.joined(separator: "\n")
          + (r.notes.isEmpty ? "" : "\nRegistry notes: " + r.notes.joined(separator: " ")))
    }
    if matches.isEmpty {
      result.append(
        "No special-purpose entry overlaps this range in the bundled snapshot; this is not proof of public routability."
      )
    }
    return result
  }
}

public struct ContentTypeParameter: Equatable, Sendable {
  public let name: String, value: String, raw: String
}
public struct ParsedContentType: Sendable {
  public let mediaType: String, parameters: [ContentTypeParameter]
  public var report: CalculationReport {
    let duplicates = Dictionary(grouping: parameters, by: { $0.name.lowercased() }).filter {
      $0.value.count > 1
    }.keys.sorted()
    let suffix =
      mediaType.split(separator: "+").count > 1
      ? String(mediaType.split(separator: "+").last!) : "None"
    return .init(
      rows: [.init("type", "Media type", mediaType), .init("suffix", "Structured suffix", suffix)]
        + parameters.enumerated().map {
          .init(
            "p\($0.offset)", $0.element.name, $0.element.value, detail: "Raw: " + $0.element.raw)
        },
      notes: duplicates.map { "Repeated parameter '\($0)' retained in order; no winner chosen." }
        + (parameters.contains { $0.name.contains("*") }
          ? ["Extended parameter syntax retained literally; RFC 2231 decoding is not performed."]
          : []),
      status: "Parsed Content-Type")
  }
}
public enum ContentTypeParser {
  public static func parse(_ raw: String) throws -> ParsedContentType {
    guard !raw.contains("\r"), !raw.contains("\n") else {
      throw CalculationIssue(.invalid, "CR/LF is not allowed in a Content-Type value.")
    }
    let s = try CalculationInput.trimmed(raw, limit: 8192, field: "Content-Type")
    guard !s.isEmpty else { throw CalculationIssue(.notReady, "Enter a Content-Type value.") }
    let a = Array(s.utf8)
    var i = 0
    let leading = raw.unicodeScalars.prefix { CharacterSet.whitespacesAndNewlines.contains($0) }
      .reduce(0) { $0 + $1.utf16.count }
    func failure(_ message: String) -> CalculationIssue {
      let offset = leading + String(decoding: a.prefix(i), as: UTF8.self).utf16.count
      return .init(
        .invalid, message, field: "Content-Type",
        range: .init(location: offset, length: i < a.count ? 1 : 0))
    }
    func ws() { while i < a.count && (a[i] == 32 || a[i] == 9) { i += 1 } }
    func token() throws -> String {
      let start = i
      while i < a.count && (a[i] >= 33 && a[i] <= 126)
        && !Array("()<>@,;:\\\"/[]?={} ".utf8).contains(a[i])
      { i += 1 }
      guard i > start else {
        throw failure("Expected an ASCII token.")
      }
      return String(decoding: a[start..<i], as: UTF8.self)
    }
    let type = try token()
    guard i < a.count, a[i] == 47 else {
      throw failure("Expected type/subtype.")
    }
    i += 1
    let subtype = try token()
    var params: [ContentTypeParameter] = []
    ws()
    while i < a.count {
      guard params.count < 128 else { throw CalculationIssue(.resource, "Limit: 128 parameters.") }
      guard a[i] == 59 else { throw failure("Expected ';' before parameter.") }
      i += 1
      ws()
      let start = i
      let name = try token()
      ws()
      guard i < a.count, a[i] == 61 else {
        throw failure("Expected '=' after parameter name.")
      }
      i += 1
      ws()
      var value: String
      if i < a.count && a[i] == 34 {
        i += 1
        var bytes: [UInt8] = []
        var closed = false
        while i < a.count {
          let c = a[i]
          i += 1
          if c == 34 {
            closed = true
            break
          }
          if c == 92 {
            guard i < a.count else { throw failure("Unfinished quoted escape.") }
            let escaped = a[i]
            guard escaped == 9 || escaped >= 32 && escaped != 127 else {
              throw failure("Invalid quoted control character.")
            }
            bytes.append(escaped)
            i += 1
          } else {
            guard c == 9 || c >= 32 && c != 127 else {
              throw failure("Invalid quoted control character.")
            }
            bytes.append(c)
          }
        }
        guard closed else { throw failure("Unterminated quoted parameter.") }
        value = String(decoding: bytes, as: UTF8.self)
      } else {
        value = try token()
      }
      params.append(
        .init(name: name, value: value, raw: String(decoding: a[start..<i], as: UTF8.self)))
      ws()
    }
    return .init(mediaType: (type + "/" + subtype).lowercased(), parameters: params)
  }
}
