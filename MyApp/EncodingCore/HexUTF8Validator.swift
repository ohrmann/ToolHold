import Foundation

/// RFC 3629 sequence validation with exact detection/lead byte offsets. Never repairs bytes.
enum HexUTF8Validator {
    struct Failure: Sendable, Equatable {
        let code: HexBytesIssue.Code
        let offset: Int
        let lead: Int?
        let message: String
    }
    static func firstFailure(_ bytes: Data) throws -> Failure? {
        var i = 0, steps = 0
        while i < bytes.count {
            if steps & 4095 == 0 { try Task.checkCancellation() }; steps += 1
            let b = bytes[bytes.startIndex + i]
            if b < 128 { i += 1; continue }
            let length: Int, low: UInt8, high: UInt8
            switch b {
            case 0xC2...0xDF: length = 2; low = 0x80; high = 0xBF
            case 0xE0: length = 3; low = 0xA0; high = 0xBF
            case 0xE1...0xEC, 0xEE...0xEF: length = 3; low = 0x80; high = 0xBF
            case 0xED: length = 3; low = 0x80; high = 0x9F
            case 0xF0: length = 4; low = 0x90; high = 0xBF
            case 0xF1...0xF3: length = 4; low = 0x80; high = 0xBF
            case 0xF4: length = 4; low = 0x80; high = 0x8F
            default: return .init(code: .invalidLead, offset: i, lead: nil,
                message: "This byte cannot start a UTF-8 character. Bytes were preserved; no replacement text was created.")
            }
            for k in 1..<length {
                guard i + k < bytes.count else {
                    return .init(code: .truncatedUTF8, offset: bytes.count, lead: i,
                        message: "UTF-8 sequence is incomplete at end of bytes. Bytes were preserved.")
                }
                let next = bytes[bytes.startIndex + i + k]
                guard (0x80...0xBF).contains(next) else {
                    return .init(code: .continuation, offset: i + k, lead: i,
                        message: "Expected a UTF-8 continuation byte (80–BF). Bytes were preserved.")
                }
                if k == 1 && !(low...high).contains(next) {
                    return .init(code: .restrictedSecond, offset: i + k, lead: i,
                        message: "This second byte would encode an overlong value, surrogate, or value above U+10FFFF. Bytes were preserved.")
                }
            }
            i += length
        }
        try Task.checkCancellation(); return nil
    }
}
