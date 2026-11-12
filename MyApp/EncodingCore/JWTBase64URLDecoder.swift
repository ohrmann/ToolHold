import Foundation

/// JWT's unpadded, canonical profile. The general Base64 tool keeps its own policy.
public enum JWTBase64URLDecoder {
    public struct Failure: Error, Sendable {
        public let offset: Int
        public let length: Int
        public let message: String
    }
    public static func decode(_ text: String, maximumLength: Int = 262_144) throws -> Data {
        guard text.utf16.prefix(maximumLength + 1).count <= maximumLength else {
            throw Failure(offset: 0, length: 0, message: "Encoded segment exceeds the processing limit.")
        }
        var scanner = Base64PolicyScanner(alphabet: .urlSafe, mode: .strict)
        var canonical = Data(), offset = 0
        do {
            for scalar in text.unicodeScalars {
                if offset & 1023 == 0 { try Task.checkCancellation(); canonical.append(scanner.drain()) }
                if scalar.value == 61 { throw Failure(offset: offset, length: 1, message: "JWT segments must not contain '=' padding.") }
                try scanner.consume(scalar.value, at: Int64(offset), length: scalar.utf16.count)
                offset += scalar.utf16.count
            }
            _ = try scanner.finish(at: Int64(offset)); canonical.append(scanner.drain())
        } catch let error as Base64ScanFailure {
            throw Failure(offset: Int(error.offset), length: error.length, message: error.message)
        }
        try Task.checkCancellation()
        guard let data = Data(base64Encoded: canonical) else {
            throw Failure(offset: 0, length: 0, message: "The validated segment could not be decoded.")
        }
        return data
    }
}
