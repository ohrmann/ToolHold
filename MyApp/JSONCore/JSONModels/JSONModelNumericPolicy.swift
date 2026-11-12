import Foundation

enum JSONModelNumericPolicy {
    /// Checks the entire merged sample group; no first-sample promotion shortcuts.
    static func type(nodes: [Int], document: JSONStructureDocument, language: JSONModelLanguage) throws -> (name: String, fallback: Bool) {
        var allInt64 = true, allIntegerLexemes = true, decimalOK = true, dotnetOK = true, doubleOK = true, safeIntegral = true
        var firstBad: Int?
        for (index, id) in nodes.enumerated() {
            if index & 127 == 0 { try Task.checkCancellation() }
            let raw = document.nodes[id].scalar ?? "0"
            let literal = JSONNumberLiteral(validatedLiteral: raw)
            let integerLexeme = !raw.contains(where: { $0 == "." || $0 == "e" || $0 == "E" })
            allIntegerLexemes = allIntegerLexemes && integerLexeme
            allInt64 = allInt64 && integerLexeme && Int64(raw) != nil
            if language == .swift { decimalOK = decimalOK && (try? literal.decimalValue()) != nil }
            if language == .cSharp { dotnetOK = dotnetOK && dotnetDecimal(raw) }
            if language == .typeScript || language == .kotlin {
                let inSafeRange = literal >= JSONNumberLiteral(validatedLiteral: "-9007199254740991") && literal <= JSONNumberLiteral(validatedLiteral: "9007199254740991")
                if literal.isInteger && !inSafeRange { safeIntegral = false; firstBad = firstBad ?? id }
                if let value = try? literal.doubleValue(), let roundTrip = try? JSONNumberLiteral(value), roundTrip == literal { }
                else { doubleOK = false; firstBad = firstBad ?? id }
            }
            if language == .java {
                // Jackson StreamReadConstraints default; BigDecimal scale is a signed Int32.
                let exponent = raw.firstIndex(where: { $0 == "e" || $0 == "E" }).map { String(raw[raw.index(after: $0)...]) }
                if raw.utf8.count > 1000 || exponent.map({ Int32($0) == nil || $0 == "-2147483648" }) == true {
                    throw JSONModelFailure(status: .unsupported, code: "MODEL-JAVA-NUMBER-LIMIT",
                        message: "The sample number exceeds the Jackson 2 numeric token or BigDecimal scale limits.", range: document.nodes[id].range)
                }
                if !integerLexeme, let exponent, let e = Int64(exponent) {
                    let mantissa = raw.prefix { $0 != "e" && $0 != "E" }
                    let fraction = mantissa.firstIndex(of: ".").map { mantissa.distance(from: mantissa.index(after: $0), to: mantissa.endIndex) } ?? 0
                    let scale = Int64(fraction) - e
                    if scale < Int64(Int32.min) || scale > Int64(Int32.max) {
                        throw JSONModelFailure(status: .unsupported, code: "MODEL-JAVA-NUMBER-LIMIT", message: "The sample number exceeds the BigDecimal scale range.", range: document.nodes[id].range)
                    }
                }
            }
        }
        switch language {
        case .swift:
            if allInt64 { return ("Int64", false) }
            guard decimalOK else { throw JSONModelFailure(status: .unsupported, code: "MODEL-SWIFT-NUMBER-RANGE", message: "A sample number cannot be represented exactly by Swift Decimal. No Double or String substitution was made.", range: nodes.first(where: { (try? JSONNumberLiteral(validatedLiteral: document.nodes[$0].scalar ?? "0").decimalValue()) == nil }).map { document.nodes[$0].range }) }
            return ("Decimal", false)
        case .cSharp: return allInt64 ? ("long", false) : dotnetOK ? ("decimal", false) : ("JsonElement", true)
        case .java: return allInt64 ? ("Long", false) : allIntegerLexemes ? ("BigInteger", false) : ("BigDecimal", false)
        case .kotlin:
            if allInt64 { return ("Long", false) }
            return !allIntegerLexemes && doubleOK && safeIntegral ? ("Double", false) : ("JsonElement", true)
        case .typeScript:
            guard doubleOK && safeIntegral else { throw JSONModelFailure(status: .unsupported, code: "MODEL-TS-NUMBER-RANGE", message: "A sample number cannot be read safely with JavaScript JSON.parse. Choose another language for this number; bigint and string were not substituted.", range: (firstBad ?? nodes.first).map { document.nodes[$0].range }) }
            return ("number", false)
        }
    }

    /// .NET Decimal's 96-bit coefficient / scale 0...28, without exponent expansion.
    static func dotnetDecimal(_ raw: String) -> Bool {
        let lower = raw.lowercased(), pieces = lower.split(separator: "e", omittingEmptySubsequences: false)
        let mantissa = pieces[0].hasPrefix("-") ? pieces[0].dropFirst() : pieces[0][...]
        let coefficient = mantissa.utf8.filter { $0 != 46 }
        var digits = Array(coefficient.drop(while: { $0 == 48 }))
        if digits.isEmpty { return true }
        guard pieces.count == 1 || Int(pieces[1]) != nil else { return false }
        let exponent = pieces.count == 2 ? Int(pieces[1])! : 0
        let fraction = mantissa.firstIndex(of: ".").map { mantissa.distance(from: mantissa.index(after: $0), to: mantissa.endIndex) } ?? 0
        let (initialScale, overflow) = fraction.subtractingReportingOverflow(exponent)
        guard !overflow else { return false }
        var scale = initialScale
        while digits.last == 48, scale > 0 { digits.removeLast(); scale -= 1 }
        guard scale <= 28 else { return false }
        if scale < 0 {
            guard scale >= -29, digits.count - scale <= 29 else { return false }
            digits += Array(repeating: 48, count: -scale)
        }
        let maximum = Array("79228162514264337593543950335".utf8)
        return digits.count < maximum.count || (digits.count == maximum.count && !maximum.lexicographicallyPrecedes(digits))
    }
}
