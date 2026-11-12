import Foundation

public enum QRContentKind: String, CaseIterable, Sendable {
    case freeText = "Free Text", url = "URL", contact = "Contact Card", wifi = "Wi-Fi", email = "Email", phone = "Phone", sms = "SMS"
}
public enum QRWiFiSecurity: String, CaseIterable, Sendable { case wpa = "WPA", wep = "WEP", open = "nopass"
    public var title: String { self == .wpa ? "WPA / WPA2 Personal" : self == .wep ? "WEP" : "Open" }
}
/// Working drafts only. Intentionally NOT Codable and never stored in preferences.
public struct QRContentFields: Sendable {
    public var url = ""
    public var firstName = "", lastName = "", organization = "", jobTitle = ""
    public var contactPhone = "", contactEmail = "", contactWebsite = ""
    public var street = "", city = "", region = "", postalCode = "", country = ""
    public var ssid = "", password = ""
    public var security: QRWiFiSecurity = .wpa
    public var hiddenNetwork = false
    public var emailAddress = "", emailSubject = "", emailBody = ""
    public var phoneNumber = "", smsNumber = "", smsBody = ""
    public init() {}
}
public enum QRCodeContent {
    public static func make(_ kind: QRContentKind, text: String, fields f: QRContentFields) throws -> String {
        if kind == .freeText { return text }
        let strings: [String]
        switch kind {
        case .freeText: strings = [text]
        case .url: strings = [f.url]
        case .contact: strings = [f.firstName,f.lastName,f.organization,f.jobTitle,f.contactPhone,f.contactEmail,f.contactWebsite,f.street,f.city,f.region,f.postalCode,f.country]
        case .wifi: strings = [f.ssid,f.password]
        case .email: strings = [f.emailAddress,f.emailSubject,f.emailBody]
        case .phone: strings = [f.phoneNumber]
        case .sms: strings = [f.smsNumber,f.smsBody]
        }
        guard strings.reduce(0, { $0 + $1.utf16.count }) <= 32_768 else { throw QRIssue(.resource,"Content exceeds the 32,768 UTF-16 unit processing limit.") }
        switch kind {
        case .freeText: return text
        case .url:
            return try absoluteURL(f.url)
        case .contact:
            guard !f.firstName.isEmpty || !f.lastName.isEmpty else { throw QRIssue(.content,"Enter a first or last name for the contact.") }
            if !f.contactEmail.isEmpty { try email(f.contactEmail) }
            let website = f.contactWebsite.isEmpty ? nil : try absoluteURL(f.contactWebsite)
            // vCard 3.0: TEXT escaping, structured N/ADR components, CRLF and UTF-8-safe folding.
            func e(_ s: String) -> String {
                s.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n")
                    .replacingOccurrences(of:"\n",with:"\\n").replacingOccurrences(of:";",with:"\\;").replacingOccurrences(of:",",with:"\\,")
            }
            guard strings.allSatisfy({ !$0.unicodeScalars.contains(where: { $0.value == 0 || ($0.value < 32 && ![9,10,13].contains($0.value)) }) }) else { throw QRIssue(.content,"Contact fields contain unsupported control characters.") }
            var lines = ["BEGIN:VCARD","VERSION:3.0","N:\(e(f.lastName));\(e(f.firstName));;;","FN:"+e([f.firstName,f.lastName].filter{!$0.isEmpty}.joined(separator:" "))]
            for (name,value) in [("ORG",f.organization),("TITLE",f.jobTitle),("TEL",f.contactPhone),("EMAIL",f.contactEmail)] where !value.isEmpty { lines.append(name+":"+e(value)) }
            if let website { lines.append("URL:"+website) }
            if [f.street,f.city,f.region,f.postalCode,f.country].contains(where:{!$0.isEmpty}) {
                lines.append("ADR:;;"+[f.street,f.city,f.region,f.postalCode,f.country].map(e).joined(separator:";"))
            }
            lines.append("END:VCARD")
            return lines.map(fold).joined(separator:"\r\n")+"\r\n"
        case .wifi:
            guard !f.ssid.isEmpty else { throw QRIssue(.content,"Enter the Wi-Fi network name (SSID).") }
            guard f.ssid.utf8.count <= 32 else { throw QRIssue(.content,"A Wi-Fi SSID may contain up to 32 UTF-8 bytes.") }
            if f.security != .open && f.password.isEmpty { throw QRIssue(.content,"Enter the network password or select Open security.") }
            guard [f.ssid,f.password].allSatisfy({ !$0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) }) else { throw QRIssue(.content,"Wi-Fi fields must not contain control characters.") }
            func e(_ s: String) -> String { s.reduce(into:"") { if "\\;,:\"".contains($1) { $0.append("\\") };$0.append($1) } }
            return "WIFI:T:\(f.security.rawValue);S:\(e(f.ssid));"+(f.security == .open ? "" : "P:\(e(f.password));")+"H:\(f.hiddenNetwork ? "true" : "false");;"
        case .email:
            try email(f.emailAddress)
            guard !f.emailSubject.contains(where:{$0.isNewline}) && !f.emailSubject.contains("\u{0}") else { throw QRIssue(.content,"Email subject must be a single line.") }
            var query = [String]()
            if !f.emailSubject.isEmpty { query.append("subject="+percent(f.emailSubject)) }
            if !f.emailBody.isEmpty { query.append("body="+percent(f.emailBody.replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n").replacingOccurrences(of:"\n",with:"\r\n"))) }
            return "mailto:"+f.emailAddress.addingPercentEncoding(withAllowedCharacters:CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~@"))!+(query.isEmpty ? "" : "?"+query.joined(separator:"&"))
        case .phone: return "tel:"+(try telephone(f.phoneNumber))
        case .sms: return "sms:"+(try telephone(f.smsNumber))+(f.smsBody.isEmpty ? "" : "?body="+percent(f.smsBody))
        }
    }
    private static func absoluteURL(_ s: String) throws -> String {
        // URL mode serializes an IRI as an ASCII URI, unlike exact Free Text.
        // Readers need IDNA hosts and UTF-8 percent escapes, not raw Unicode bytes
        // whose interpretation depends on the QR reader's byte-mode charset.
        let bytes = Array(s.utf8)
        let validEscapes = bytes.indices.allSatisfy { index in
            bytes[index] != 37 || (index+2 < bytes.count && bytes[(index+1)...(index+2)].allSatisfy {
                (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
            })
        }
        guard !s.isEmpty, !s.unicodeScalars.contains(where:{CharacterSet.whitespacesAndNewlines.contains($0) || $0.value < 32 || $0.value == 127}),
              let c = URLComponents(string:s), let scheme = c.scheme, !scheme.isEmpty,
              !["http","https"].contains(scheme.lowercased()) || c.host?.isEmpty == false,
              validEscapes else {
            throw QRIssue(.content,"Enter an absolute URL, for example https://example.com. Use valid percent escapes for spaces and reserved characters.")
        }
        // Foundation can double-escape an existing %2F when the SAME component
        // also contains Unicode. Encode non-ASCII first while preserving URI syntax.
        let asciiCharacters = CharacterSet(charactersIn:String((33...126).map { Character(UnicodeScalar($0)!) }))
        guard let encoded = s.addingPercentEncoding(withAllowedCharacters:asciiCharacters),
              var serialized = URLComponents(string:encoded) else { throw QRIssue(.content,"Could not encode this URL.") }
        if let host = c.host, !host.utf8.allSatisfy({ $0 < 128 }) { serialized.host = host }
        guard let uri = serialized.url?.absoluteString, uri.utf8.allSatisfy({ $0 < 128 }) else { throw QRIssue(.content,"Could not encode this URL.") }
        return uri
    }
    private static func email(_ s: String) throws {
        let parts = s.split(separator:"@",omittingEmptySubsequences:false)
        guard parts.count == 2, parts.allSatisfy({!$0.isEmpty}), !s.contains(where:{$0.isWhitespace}),
              !s.unicodeScalars.contains(where:{$0.value < 32 || $0.value == 127}), !s.contains(where:{",;<>\"".contains($0)}) else { throw QRIssue(.content,"Enter one email address, for example name@example.com.") }
    }
    private static func telephone(_ s: String) throws -> String {
        let compact = s.filter { !" ()-.".contains($0) }
        guard compact.hasPrefix("+"), compact.count > 1, compact.dropFirst().utf8.allSatisfy({(48...57).contains($0)}) else { throw QRIssue(.content,"Enter an international phone number beginning with + and a country code.") }
        return compact
    }
    private static func percent(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters:CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))! }
    /// RFC 2425 line folding: max 75 octets, continuation space counts toward the limit.
    private static func fold(_ line: String) -> String {
        var out = "", bytes = 0
        for scalar in line.unicodeScalars {
            let piece = String(scalar), length = piece.utf8.count
            if bytes+length > 75 { out += "\r\n ";bytes = 1 }
            out += piece;bytes += length
        }
        return out
    }
}
