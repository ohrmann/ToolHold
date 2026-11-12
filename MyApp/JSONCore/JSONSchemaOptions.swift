import Foundation

/// Only these switches may be persisted. Resource contents/locations are session-only.
struct JSONSchemaOptions: Sendable, Equatable {
    var validateFormats = false
    var assumedDialect: Dialect = .draft2020_12
}
struct JSONSchemaResource: Sendable, Identifiable {
    let id: UUID
    let name: String
    let retrievalURI: URL
    let document: JSONStructureDocument
    init(id: UUID = UUID(), name: String, retrievalURI: URL, document: JSONStructureDocument) {
        self.id = id; self.name = name; self.retrievalURI = retrievalURI; self.document = document
    }
    func located(beside primary: URL) -> JSONSchemaResource {
        guard retrievalURI.host == JSONSchemaRegistry.base.host else { return self }
        let filename = retrievalURI.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "schema.json"
        let uri = URL(string: filename, relativeTo: primary)?.absoluteURL ?? retrievalURI
        return .init(id: id, name: name, retrievalURI: uri, document: document)
    }
}

/// Audited syntax-only validators. No DNS, URL fetching or deliverability checks.
struct ToolboxSchemaFormat: FormatValidator {
    let formatName: String
    static let names: Set<String> = ["date-time", "date", "time", "email", "ipv4", "ipv6", "uuid", "uri", "uri-reference", "json-pointer", "relative-json-pointer", "duration", "regex"]
    static let standardNames = names.union(["hostname", "idn-email", "idn-hostname", "iri", "iri-reference", "uri-template"])
    static var all: [any FormatValidator] { names.sorted().map { ToolboxSchemaFormat(formatName: $0) } }
    private func match(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "\\A(?:" + pattern + ")\\z") else { return false }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) != nil
    }
    func validate(_ value: String) -> Bool {
        guard SchemaRuntime.check() else { return false }
        switch formatName {
        case "date-time": return DateTimeFormatValidator().validate(value)
        case "date": return match("[0-9]{4}-[0-9]{2}-[0-9]{2}", value) && DateTimeFormatValidator().validate(value + "T00:00:00Z")
        case "time": return DateTimeFormatValidator().validate("2000-12-31T" + value) || DateTimeFormatValidator().validate("2000-01-01T" + value)
        case "ipv4":
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            return parts.count == 4 && parts.allSatisfy { part in
                part.utf8.count <= 3 && !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) }
                && (part.count == 1 || part.first != "0") && (Int(part) ?? 256) <= 255
            }
        case "ipv6": return IPv6FormatValidator().validate(value)
        case "uuid": return match("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", value)
        case "hostname":
            let name = value.hasSuffix(".") ? String(value.dropLast()) : value
            return name.utf8.count <= 253 && name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { match("[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", String($0)) }
        case "email":
            guard let at = value.lastIndex(of: "@") else { return false }
            let local = String(value[..<at]), host = String(value[value.index(after: at)...])
            let atom = "[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+"
            let quoted = #""(?:[\x20-\x21\x23-\x5B\x5D-\x7E]|\\[\x20-\x7E])*""#
            let localOK = !host.hasSuffix(".") && match(atom + "(?:\\." + atom + ")*|" + quoted, local)
            let hostOK: Bool
            if host.hasPrefix("["), host.hasSuffix("]") {
                let address = String(host.dropFirst().dropLast())
                hostOK = address.lowercased().hasPrefix("ipv6:") ? IPv6FormatValidator().validate(String(address.dropFirst(5))) : ToolboxSchemaFormat(formatName: "ipv4").validate(address)
            } else { hostOK = ToolboxSchemaFormat(formatName: "hostname").validate(host) }
            return localOK && hostOK
        case "uri", "uri-reference":
            guard value.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 32 && $0.value < 127 }),
                !value.contains("\\"), !value.contains("\""), !value.contains("<"), !value.contains(">"), !value.contains("{"), !value.contains("}"), !value.contains("|"), !value.contains("^"), !value.contains("`") else { return false }
            let bytes = Array(value.utf8)
            for i in bytes.indices where bytes[i] == 37 {
                guard i + 2 < bytes.count, bytes[(i+1)...(i+2)].allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return false }
            }
            guard let parts = URLComponents(string: value) else { return false }
            if formatName == "uri", parts.scheme == nil { return false }
            if parts.scheme == nil, !value.hasPrefix("/"), (value.split(separator: "/", omittingEmptySubsequences: false).first ?? "").contains(":") { return false }
            if parts.path.contains("[") || parts.path.contains("]") { return false }
            if let authorityStart = value.range(of: "//"), authorityStart.lowerBound == value.startIndex || value[..<authorityStart.lowerBound].hasSuffix(":") {
                let authority = value[authorityStart.upperBound...].prefix { !"/?#".contains($0) }
                if authority.filter({ $0 == "@" }).count > 1 { return false }
                if let at = authority.firstIndex(of: "@"), authority[..<at].contains(where: { $0 == "[" || $0 == "]" }) { return false }
                let hostPort = authority.split(separator: "@", omittingEmptySubsequences: false).last ?? ""
                if hostPort.hasPrefix("[") {
                    guard let end = hostPort.firstIndex(of: "]"), IPv6FormatValidator().validate(String(hostPort[hostPort.index(after: hostPort.startIndex)..<end])) else { return false }
                }
            }
            return value.filter { $0 == "#" }.count <= 1
        case "json-pointer": return value.isEmpty || match(#"(?:/(?:[^~]|~[01])*)+"#, value)
        case "relative-json-pointer": return match(#"(?:0|[1-9][0-9]*)(?:#|(?:/(?:[^~]|~[01])*)*)"#, value)
        case "duration": return match(#"P(?:(?:[0-9]+Y(?:[0-9]+M(?:[0-9]+D)?)?|[0-9]+M(?:[0-9]+D)?|[0-9]+D)(?:T(?:[0-9]+H(?:[0-9]+M(?:[0-9]+S)?)?|[0-9]+M(?:[0-9]+S)?|[0-9]+S))?|T(?:[0-9]+H(?:[0-9]+M(?:[0-9]+S)?)?|[0-9]+M(?:[0-9]+S)?|[0-9]+S)|[0-9]+W)"#, value)
        case "regex": return value.isEmpty || SchemaPattern(value) != nil
        default: return true
        }
    }
}

struct JSONSchemaResourceKey: Equatable, Sendable {
    let id: UUID
    let snapshot: UUID
    let uri: URL
    let name: Data
    init(_ resource: JSONSchemaResource) { id = resource.id; snapshot = resource.document.snapshotID; uri = resource.retrievalURI; name = Data(resource.name.utf8) }
}
