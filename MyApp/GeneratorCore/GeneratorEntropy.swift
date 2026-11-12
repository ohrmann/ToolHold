import Foundation

enum GeneratorEntropy {
    /// Probability DP avoids subtracting near-equal huge powers in inclusion/exclusion.
    static func password(length: Int, groupSizes: [Int], requireEveryGroup: Bool) throws -> Double {
        let total = groupSizes.reduce(0, +)
        guard length > 0, total >= 2, groupSizes.count <= 4, groupSizes.allSatisfy({ $0 > 0 }) else { throw SecretIssue(.invalidOptions, "Invalid entropy parameters.") }
        var bits = Double(length) * log2(Double(total))
        if requireEveryGroup {
            let masks = 1 << groupSizes.count
            var previous = [Double](repeating: 0, count: masks); previous[0] = 1
            for _ in 0..<length {
                var next = [Double](repeating: 0, count: masks)
                for mask in 0..<masks {
                    for (group, size) in groupSizes.enumerated() {
                        next[mask] += Double(size) / Double(total) * previous[mask & ~(1 << group)]
                    }
                }
                previous = next
            }
            guard previous[masks - 1] > 0 else { throw SecretIssue(.invalidOptions, "Length cannot satisfy the required groups.") }
            bits += log2(previous[masks - 1])
        }
        guard bits.isFinite, bits >= 0 else { throw SecretIssue(.invalidOptions, "Unable to calculate generator entropy.") }
        return bits
    }
    static func passphrase(words: Int, dictionarySize: Int, appendDigit: Bool) -> Double {
        Double(words) * log2(Double(dictionarySize)) + (appendDigit ? log2(10) : 0)
    }
}
