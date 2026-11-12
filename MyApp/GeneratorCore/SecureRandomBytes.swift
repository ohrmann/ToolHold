import Foundation
import Security

/// The production provider has no non-secure fallback. Injection is internal for deterministic tests.
enum SecureRandomBytes {
    static func read(_ count: Int) throws -> [UInt8] {
        guard (1...4096).contains(count) else { throw IdentifierIssue(.resourceLimit, "Random buffer limit reached.") }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw IdentifierIssue(.entropyUnavailable, "Secure randomness is unavailable. Try again.") }
        return bytes
    }
}
