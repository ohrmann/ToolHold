import Foundation

/// Deliberately limited RFC2397 profile. Never percent-decodes or renders content.
enum Base64DataURL {
    static func isToken(_ text: Substring) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || Array("!#$&'*+-.^_`|~".utf8).contains(byte)
        }
    }
    static func validMIME(_ text: String) -> Bool {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy(isToken)
    }
    static func header(mime: String) throws -> Data {
        guard mime.utf8.count <= Base64FileBudget.header - 14 else { throw Base64FileFailure(.resourceLimit, "The Data URL header exceeds 4 KiB.") }
        guard validMIME(mime) else { throw Base64FileFailure(.unsupportedFormat, "Enter a MIME type such as image/png or application/octet-stream.") }
        return Data("data:\(mime);base64,".utf8)
    }
    static func parse(_ header: Data) throws -> String {
        guard header.count <= Base64FileBudget.header else { throw Base64FileFailure(.resourceLimit, "The Data URL header exceeds 4 KiB.") }
        if let invalid = header.enumerated().first(where: { $0.element < 33 || $0.element > 126 || $0.element == 37 }) {
            throw Base64FileFailure(.unsupportedFormat, "Expected an ASCII data: header. Whitespace and percent escapes are not supported.", byteOffset: Int64(invalid.offset))
        }
        guard let text = String(data: header, encoding: .ascii), text.lowercased().hasPrefix("data:") else {
            throw Base64FileFailure(.unsupportedFormat, "Expected an ASCII data: header. Whitespace and percent escapes are not supported.", byteOffset: 0)
        }
        let fields = text.dropFirst(5).split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count >= 2 && fields.last?.lowercased() == "base64" else {
            throw Base64FileFailure(.unsupportedFormat, "Expected a final ';base64,' marker. Non-Base64 Data URLs are not supported.", byteOffset: Int64(header.count), length: 0)
        }
        let mime = String(fields[0])
        guard mime.isEmpty || validMIME(mime) else { throw Base64FileFailure(.unsupportedFormat, "The Data URL media type is not supported.", byteOffset: 5) }
        var names = Set<String>()
        for part in fields.dropFirst().dropLast() {
            let pair = part.split(separator: "=", omittingEmptySubsequences: false)
            guard pair.count == 2, pair[0].lowercased() != "base64", isToken(pair[0]), isToken(pair[1]), names.insert(pair[0].lowercased()).inserted else {
                throw Base64FileFailure(.unsupportedFormat, "Expected unique token-valued Data URL parameters followed by ';base64,'. Quoted values and percent escapes are not supported.", byteOffset: 5)
            }
        }
        return mime.isEmpty ? "text/plain" : mime.lowercased()
    }
}
