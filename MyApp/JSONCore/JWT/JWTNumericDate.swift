import Foundation

struct JWTTimeObservation: Sendable {
    let status: String
    let date: String
}
struct JWTTimeEvaluation: Sendable {
    let evaluatedAt: String
    let values: [Int: JWTTimeObservation]
    let notes: [String]
}
enum JWTNumericDate {
    static func reference(_ now: Date) -> JSONNumberLiteral {
        // Device clock is sampled once, explicitly at millisecond resolution.
        let ms = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        let magnitude = ms.magnitude
        let raw = "\(ms < 0 ? "-" : "")\(magnitude / 1000).\(String(format: "%03llu", magnitude % 1000))"
        return JSONNumberLiteral(validatedLiteral: raw)
    }
    static func evaluate(_ result: JWTInspectionResult, now: Date = .now, local: Bool = false, zone: TimeZone = .current) -> JWTTimeEvaluation {
        let reference = reference(now), timezone = local ? zone : TimeZone(secondsFromGMT: 0)!
        var values: [Int: JWTTimeObservation] = [:], byName: [String: JSONNumberLiteral] = [:], notes: [String] = []
        for claim in result.claims {
            guard let raw = claim.numericDate else { continue }
            let number = JSONNumberLiteral(validatedLiteral: raw)
            let status: String
            if !result.interpretationAvailable { status = "Interpretation unavailable" }
            else if claim.ambiguous { status = "Ambiguous" }
            else {
                switch claim.name {
                case "exp": status = reference >= number ? "Expired" : "Expiration is in the future"
                case "nbf": status = reference < number ? "Not yet valid" : "Not-before time reached"
                default: status = reference < number ? "Issued in the future" : "Issued at or before evaluation time"
                }
                byName[claim.name] = number
            }
            values[claim.id] = .init(status: status, date: calendar(number, zone: timezone))
        }
        if !result.hasRootDuplicates && result.interpretationAvailable {
            if let exp = byName["exp"], let nbf = byName["nbf"] {
                if exp < nbf { notes.append("Expiration precedes not-before time.") }
                else if exp == nbf { notes.append("Expiration and not-before define an empty time window.") }
            }
            if let exp = byName["exp"], let iat = byName["iat"], iat > exp { notes.append("Issued-at time is after expiration.") }
        }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return .init(evaluatedAt: "Evaluated at \(formatter.string(from: now)) · device clock · millisecond precision", values: values, notes: notes)
    }
    static func calendar(_ number: JSONNumberLiteral, zone: TimeZone) -> String {
        guard number >= JSONNumberLiteral(-62_135_596_800), number < JSONNumberLiteral(253_402_300_800),
              let value = try? number.doubleValue() else { return "Outside date display range · raw NumericDate preserved" }
        let date = Date(timeIntervalSince1970: value)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS XXXXX"
        return formatter.string(from: date) + " · " + zone.identifier + " · approximate calendar display"
    }
}
