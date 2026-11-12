import Foundation

public enum ExactByteProfile: String, Codable, CaseIterable, Sendable {
    case text, hex, base64, base64URL
    public var title: String { switch self { case .text: "Text (UTF-8)"; case .hex: "Hex"; case .base64: "Base64 (padded)"; case .base64URL: "Base64URL (unpadded)" } }
}
public struct ExactByteFailure: Error, Sendable {
    public let message: String
    public let range: NSRange
    public let resourceLimit: Bool
    public init(_ message: String, range: NSRange = .init(location: 0, length: 0), resourceLimit: Bool = false) {
        self.message = message; self.range = range; self.resourceLimit = resourceLimit
    }
}
/// Narrow public adapter. Existing forgiving codec policies remain unchanged.
public enum ExactByteInputDecoder {
    public static func decode(_ text: String, profile: ExactByteProfile, inputLimit: Int = 262_144, byteLimit: Int = 1_048_576) throws -> Data {
        guard text.utf16.prefix(inputLimit + 1).count <= inputLimit else { throw ExactByteFailure("Input exceeds \(inputLimit) UTF-16 units.", resourceLimit: true) }
        try Task.checkCancellation()
        var result = Data()
        switch profile {
        case .text:
            do { result = try Base64TextCodec.encode(text, encoding: .utf8, limit: byteLimit) }
            catch let failure as Base64Failure { throw ExactByteFailure(failure.message, resourceLimit: true) }
        case .hex:
            var high: UInt8?, offset = 0
            for scalar in text.unicodeScalars {
                if offset & 4095 == 0 { try Task.checkCancellation() }
                let digit: UInt8
                switch scalar.value { case 48...57: digit = UInt8(scalar.value - 48); case 65...70: digit = UInt8(scalar.value - 55); case 97...102: digit = UInt8(scalar.value - 87)
                default: throw ExactByteFailure("Expected a hexadecimal digit; separators and prefixes are not allowed.", range: .init(location: offset, length: scalar.utf16.count)) }
                if let first = high { result.append(first * 16 + digit); high = nil } else { high = digit }
                offset += scalar.utf16.count
            }
            if high != nil { throw ExactByteFailure("Expected a second hexadecimal digit.", range: .init(location: offset, length: 0)) }
        case .base64, .base64URL:
            var scanner = Base64PolicyScanner(alphabet: profile == .base64 ? .standard : .urlSafe, mode: .strict)
            var canonical = Data(), offset = 0
            do {
                for scalar in text.unicodeScalars {
                    if offset & 4095 == 0 { try Task.checkCancellation(); canonical.append(scanner.drain()) }
                    if profile == .base64URL && scalar.value == 61 { throw ExactByteFailure("Base64URL input must not contain padding.", range: .init(location: offset, length: 1)) }
                    try scanner.consume(scalar.value, at: Int64(offset), length: scalar.utf16.count); offset += scalar.utf16.count
                }
                _ = try scanner.finish(at: Int64(offset)); canonical.append(scanner.drain())
            } catch let error as Base64ScanFailure { throw ExactByteFailure(error.message, range: .init(location: Int(error.offset), length: error.length)) }
            guard let bytes = Data(base64Encoded: canonical) else { throw ExactByteFailure("Cannot decode the validated input.") }
            result = bytes
        }
        guard result.count <= byteLimit else { throw ExactByteFailure("Decoded input exceeds \(byteLimit) bytes.", resourceLimit: true) }
        try Task.checkCancellation(); return result
    }
}
