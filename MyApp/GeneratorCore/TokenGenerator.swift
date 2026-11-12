import Foundation

enum TokenEncoding: String, CaseIterable, Codable, Sendable {
    case base64URL, base64, hex
    var title: String { switch self { case .base64URL: "Base64URL"; case .base64: "Base64"; case .hex: "Hex" } }
    func string(_ data: Data, uppercase: Bool) -> String {
        switch self {
        case .base64: return data.base64EncodedString()
        case .base64URL: return data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        case .hex:
            let symbols = Array((uppercase ? "0123456789ABCDEF" : "0123456789abcdef").utf8)
            var output = [UInt8](); output.reserveCapacity(data.count * 2)
            for byte in data { output.append(symbols[Int(byte >> 4)]); output.append(symbols[Int(byte & 15)]) }
            return String(decoding: output, as: UTF8.self)
        }
    }
    func length(_ count: Int) -> Int { switch self { case .hex: count * 2; case .base64: (count + 2) / 3 * 4; case .base64URL: count / 3 * 4 + (count % 3 == 0 ? 0 : count % 3 + 1) } }
}
struct TokenOptions: Codable, Equatable, Sendable {
    var bytes = 32, count = 1
    var encoding = TokenEncoding.base64URL
    var uppercase = false
    var valid: Bool { (1...1024).contains(bytes) && (1...1000).contains(count) && bytes * count <= 1_048_576 }
}
struct TokenBatch: Sendable {
    let id = UUID()
    let bytes: [Data]
    let size: Int
}
struct TokenPresentation: Sendable {
    let encoding: TokenEncoding
    let uppercase: Bool
    let values: [String]
}
struct TokenResult: Sendable { var batch: TokenBatch?; var issue: SecretIssue? }
enum TokenGenerator {
    static func generate(_ options: TokenOptions, random: (Int) throws -> [UInt8] = SecureRandomBytes.read,
                         deadline: Double? = nil) -> TokenResult {
        do {
            guard options.valid else { throw SecretIssue(.invalidOptions, "Bytes must be 1–1024 and count 1–1000.") }
            let end = deadline ?? ProcessInfo.processInfo.systemUptime + 5
            var output = [Data](); output.reserveCapacity(options.count)
            for _ in 0..<options.count {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime < end else { throw SecretIssue(.resourceLimit, "Generation time limit reached.") }
                let bytes: [UInt8]
                do { bytes = try random(options.bytes) }
                catch is CancellationError { throw CancellationError() }
                catch { throw SecretIssue(.entropyUnavailable, "Secure randomness is unavailable. Try again.") }
                guard bytes.count == options.bytes else { throw SecretIssue(.entropyUnavailable, "Secure randomness returned an incomplete result.") }
                output.append(Data(bytes))
            }
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < end else { throw SecretIssue(.resourceLimit, "Generation time limit reached.") }
            return .init(batch: .init(bytes: output, size: options.bytes))
        } catch is CancellationError { return .init(issue: .init(.cancelled, "Cancelled")) }
        catch let issue as SecretIssue { return .init(issue: issue) }
        catch { return .init(issue: .init(.entropyUnavailable, "Secure randomness is unavailable.")) }
    }
    static func present(_ batch: TokenBatch, encoding: TokenEncoding, uppercase: Bool) throws -> TokenPresentation {
        var values = [String](); values.reserveCapacity(batch.bytes.count)
        for bytes in batch.bytes { try Task.checkCancellation(); values.append(encoding.string(bytes, uppercase: uppercase)) }
        try Task.checkCancellation(); return .init(encoding: encoding, uppercase: uppercase, values: values)
    }
    static func serialize(_ presentation: TokenPresentation, json: Bool) throws -> String {
        var result = json ? "[" : ""
        for (index, value) in presentation.values.enumerated() {
            try Task.checkCancellation()
            if index > 0 { result += json ? "," : "\n" }
            // Values have only ASCII encoder alphabet characters, no JSON escaping needed.
            result += json ? "\"" + value + "\"" : value
            guard result.utf8.count <= 4_194_303 else { throw SecretIssue(.resourceLimit, "Copy exceeds 4 MiB.") }
        }
        if json { result += "]" }; try Task.checkCancellation(); return result
    }
}
