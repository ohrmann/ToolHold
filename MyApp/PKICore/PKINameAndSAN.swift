import Foundation
import Darwin

public enum PKINameAndSAN {
    public static func host(_ text: String, wildcard: Bool = false) throws -> String {
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { $0.value < 33 || $0.value == 127 }), !text.contains("\u{0}") else { throw PKIFailure("Enter a hostname or IP address without whitespace/control characters") }
        var address = in6_addr()
        if text.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 || text.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 { return text }
        let star = wildcard && text.hasPrefix("*.")
        let base = star ? String(text.dropFirst(2)) : text
        guard !base.contains("*"), !base.contains(":"), !base.contains("/"), !base.contains("@"), !base.contains("?"), !base.contains("#"), !base.contains("%"), !base.hasSuffix(".") else { throw PKIFailure("Enter DNS labels only; wildcard is allowed only as the full leftmost label") }
        guard let url = URL(string: "https://" + base), let ascii = url.host, ascii.utf8.allSatisfy({ $0 < 128 }), ascii.utf8.count <= 253 else { throw PKIFailure("Invalid DNS/IDNA hostname") }
        let labels = ascii.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 63 && $0.first != "-" && $0.last != "-" && $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 } }), !star || labels.count >= 2 else { throw PKIFailure("Invalid DNS labels or wildcard scope") }
        return (star ? "*." : "") + ascii.lowercased()
    }
    static func validate(_ d: PKIGenerationDraft, csr: Bool) throws -> (fields: [(String,String)], sans: [PKISAN]) {
        let fields = [("CN",d.commonName),("O",d.organization),("OU",d.unit),("L",d.locality),("ST",d.state),("C",d.country)].filter { !$0.1.isEmpty }
        guard !fields.isEmpty, fields.allSatisfy({ $0.1.utf8.count <= 1024 && !$0.1.unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }) else { throw PKIFailure("Enter a subject; each field must fit in 1024 bytes without control characters") }
        guard d.country.isEmpty || d.country.utf8.count == 2 && d.country.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) else { throw PKIFailure("Country must contain exactly two ASCII letters") }
        guard (0...8).contains(d.pathLength), d.sans.count <= 128 else { throw PKIFailure("Maximum 128 SAN entries and CA path length 0…8") }
        if !csr { let interval = d.notAfter.timeIntervalSince(d.notBefore)
            guard interval >= 86400, interval <= 3651 * 86400, d.notBefore.timeIntervalSince1970 >= 0, d.notAfter.timeIntervalSince1970 <= 253402300799 else { throw PKIFailure("Validity must span 1…3650 days (plus clock skew), ending after its start") }
        }
        let sans = try d.sans.map { san -> PKISAN in
            guard !san.value.isEmpty, san.value.utf8.count <= 1024, !san.value.unicodeScalars.contains(where: { $0.value < 33 || $0.value == 127 }) else { throw PKIFailure("SAN values must be nonempty and contain no whitespace/control characters") }
            var result = san
            switch san.kind {
            case .dns: result.value = try host(san.value, wildcard: true); var ip = in6_addr(); guard result.value.withCString({ inet_pton(AF_INET, $0, &ip) }) != 1 && result.value.withCString({ inet_pton(AF_INET6, $0, &ip) }) != 1 else { throw PKIFailure("Use the IP SAN type for numeric IP addresses") }
            case .ip: var ip = in6_addr(); guard san.value.withCString({ inet_pton(AF_INET, $0, &ip) }) == 1 || san.value.withCString({ inet_pton(AF_INET6, $0, &ip) }) == 1 else { throw PKIFailure("Invalid IPv4/IPv6 SAN") }
            case .uri: guard san.value.utf8.allSatisfy({ $0 < 128 }), let url = URLComponents(string: san.value), url.scheme?.isEmpty == false else { throw PKIFailure("URI SAN requires an absolute ASCII URI") }
            case .email: let parts = san.value.split(separator: "@", omittingEmptySubsequences: false); guard parts.count == 2, !parts[0].isEmpty, parts[0].utf8.allSatisfy({ $0 < 128 }) else { throw PKIFailure("Email SAN requires an ASCII local part and a domain") }; result.value = String(parts[0]) + "@" + (try host(String(parts[1])))
            }
            return result
        }
        guard d.profile != .server || sans.contains(where: { $0.kind == .dns || $0.kind == .ip }) else { throw PKIFailure("TLS Server requires at least one DNS or IP SAN; CN is not a substitute") }
        guard fields.reduce(0, { $0 + $1.1.utf8.count }) + sans.reduce(0, { $0 + $1.value.utf8.count }) <= 32768 else { throw PKIFailure("Subject and SAN fields exceed 32 KiB", status: .resourceLimit) }
        return (fields, sans)
    }
}
