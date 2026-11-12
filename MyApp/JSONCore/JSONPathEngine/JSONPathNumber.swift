import Foundation

/// Decimal comparison without binary conversion or exponent expansion. Working data only.
struct JSONPathNumber: Sendable {
    let sign: Int
    let digits: [UInt8]
    let order: SignedDigits

    init(_ lexeme: String) {
        let bytes = Array(lexeme.utf8)
        let negative = bytes.first == 45
        let start = negative ? 1 : 0
        let e = bytes.firstIndex(where: { $0 == 69 || $0 == 101 }) ?? bytes.count
        let dot = bytes[start..<e].firstIndex(of: 46) ?? e
        let raw = bytes[start..<e].filter { $0 != 46 }
        let first = raw.firstIndex(where: { $0 != 48 }) ?? raw.count
        let last = raw.lastIndex(where: { $0 != 48 }) ?? first
        sign = first == raw.count ? 0 : negative ? -1 : 1
        digits = first < raw.count ? Array(raw[first...last]) : []
        let exponent = e < bytes.count ? String(decoding: bytes[(e + 1)...], as: UTF8.self) : "0"
        order = SignedDigits(exponent).adding(dot - start - first)
    }
    func compare(_ other: Self) -> Int {
        if sign != other.sign { return sign < other.sign ? -1 : 1 }
        if sign == 0 { return 0 }
        let magnitude = order.compare(other.order)
        if magnitude != 0 { return magnitude * sign }
        for i in 0..<max(digits.count, other.digits.count) {
            let a = i < digits.count ? digits[i] : 48
            let b = i < other.digits.count ? other.digits[i] : 48
            if a != b { return (a < b ? -1 : 1) * sign }
        }
        return 0
    }

    struct SignedDigits: Sendable {
        let sign: Int
        let digits: [UInt8]
        init(_ text: String) {
            let raw = Array(text.utf8.filter { $0 != 43 && $0 != 45 })
            let first = raw.firstIndex(where: { $0 != 48 }) ?? raw.count
            digits = Array(raw.dropFirst(first))
            sign = digits.isEmpty ? 0 : text.first == "-" ? -1 : 1
        }
        private init(sign: Int, digits: [UInt8]) {
            let first = digits.firstIndex(where: { $0 != 48 }) ?? digits.count
            self.digits = Array(digits.dropFirst(first)); self.sign = self.digits.isEmpty ? 0 : sign
        }
        func compare(_ other: Self) -> Int {
            if sign != other.sign { return sign < other.sign ? -1 : 1 }
            return Self.magnitude(digits, other.digits) * sign
        }
        private static func magnitude(_ a: [UInt8], _ b: [UInt8]) -> Int {
            if a.count != b.count { return a.count < b.count ? -1 : 1 }
            if a == b { return 0 }; return a.lexicographicallyPrecedes(b) ? -1 : 1
        }
        func adding(_ value: Int) -> Self {
            let other = Self(String(value))
            if sign == 0 { return other }; if other.sign == 0 { return self }
            let sum = sign == other.sign
            let comparison = Self.magnitude(digits, other.digits)
            let larger = comparison >= 0 ? digits : other.digits
            let smaller = comparison >= 0 ? other.digits : digits
            var out: [UInt8] = [], carry = 0
            let a = Array(larger.reversed()), b = Array(smaller.reversed())
            for i in 0..<a.count {
                var n = Int(a[i]) - 48 + (sum ? 1 : -1) * (i < b.count ? Int(b[i]) - 48 : 0) + carry
                if sum { carry = n / 10; n %= 10 }
                else { carry = n < 0 ? -1 : 0; if n < 0 { n += 10 } }
                out.append(UInt8(n + 48))
            }
            if sum && carry > 0 { out.append(UInt8(carry + 48)) }
            return Self(sign: sum ? sign : comparison >= 0 ? sign : other.sign, digits: out.reversed())
        }
    }
}
