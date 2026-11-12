import Foundation
import CryptoKit

struct PassphraseWordlist: Sendable {
    static let checksum = "addd35536511597a02fa0a9ff1e5284677b8883b83e986e43f15a3db996b903e"
    static let identifier = "eff-long-2016-v1"
    let words: [String]
    let version: String
    private static let cached: Result<Self, SecretIssue> = {
        do {
            #if SWIFT_PACKAGE
            let bundle = Bundle.module
            #else
            let bundle = Bundle.main
            #endif
            guard let url = bundle.url(forResource: "eff_large_wordlist", withExtension: "txt"),
                  let manifestURL = bundle.url(forResource: "eff_wordlist_manifest", withExtension: "json") else { throw unavailable }
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
            guard manifest.id == identifier, manifest.sha256 == checksum, manifest.entries == 7776 else { throw unavailable }
            return .success(try Self(data: data))
        } catch { return .failure(unavailable) }
    }()
    static var unavailable: SecretIssue { .init(.dictionaryUnavailable, "The bundled English wordlist is unavailable or damaged.") }
    static func bundled() throws -> Self { try cached.get() }
    /// Exact pinned resource, not a mutable/imported dictionary. Checks run once on the generation worker.
    init(data: Data) throws {
        guard data.count < 200_000, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == Self.checksum,
              let text = String(data: data, encoding: .utf8) else { throw Self.unavailable }
        let lines = text.split(separator: "\n")
        guard lines.count == 7776 else { throw Self.unavailable }
        var words = [String](), ids = Set<String>(), unique = Set<String>()
        words.reserveCapacity(7776)
        for line in lines {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].utf8.count == 5, parts[0].utf8.allSatisfy({ (49...54).contains($0) }),
                  !parts[1].isEmpty, parts[1].utf8.allSatisfy({ (97...122).contains($0) || $0 == 45 }),
                  !parts[1].hasPrefix("-"), !parts[1].hasSuffix("-"), !parts[1].contains("--"),
                  ids.insert(String(parts[0])).inserted, unique.insert(String(parts[1])).inserted else { throw Self.unavailable }
            words.append(String(parts[1]))
        }
        self.words = words; version = Self.identifier + ":" + Self.checksum
    }
    private struct Manifest: Decodable { let id: String; let entries: Int; let sha256: String }
}
