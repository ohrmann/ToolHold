import Foundation

enum JWTClaimsPolicyEvaluator {
    static func evaluate(_ inspection: JWTInspectionResult, policy: JWTClaimsPolicy, now: Date) throws -> ([JWTVerificationCheck],Date?) {
        guard (0...300).contains(policy.skew), let doc = inspection.parts[.payload]?.document else { throw JWTVerificationFailure("Claims policy is invalid or payload is unavailable.") }
        var checks: [JWTVerificationCheck] = [], expires: Date?
        func node(_ name: String) -> JSONStructureNode? { JWKReader.member(name,0,in:doc) }
        func add(_ name: String, _ state: JWTVerificationCheck.State, _ message: String) { checks.append(.init(id:name,state:state,message:message)) }
        let time = policy.customTime ? policy.reference : now
        guard time.timeIntervalSince1970.isFinite, abs(time.timeIntervalSince1970) < 1e12 else { throw JWTVerificationFailure("Reference time is outside the supported device-clock range.") }
        let before = JWTNumericDate.reference(time.addingTimeInterval(Double(-policy.skew)))
        let after = JWTNumericDate.reference(time.addingTimeInterval(Double(policy.skew)))
        for name in ["exp","nbf","iat"] {
            let required = name == "exp" ? policy.requireExp : name == "nbf" ? policy.requireNbf : policy.requireIat
            guard let n = node(name) else { add(name,required ? .failed : .notPresent,required ? "Required time claim is absent." : "Not present; not required."); continue }
            guard n.kind == .number, let raw = n.scalar else { add(name,.failed,"NumericDate must be a JSON number."); continue }
            let number = JSONNumberLiteral(validatedLiteral:raw)
            if name == "iat" && !policy.checkFutureIat { add(name,.notConfigured,"Numeric type checked; future-issued policy is disabled."); continue }
            if name != "iat" && !policy.checkTime { add(name,.notConfigured,"Time comparison is disabled."); continue }
            let passed = name == "exp" ? before < number : name == "nbf" ? after >= number : after >= number
            add(name,passed ? .passed : .failed,passed ? "Time check passed at the reference snapshot." : name == "exp" ? "Expired at the reference time." : name == "nbf" ? "Not-before time has not been reached." : "Issued-at time is in the future.")
            if name == "exp", !policy.customTime, let value = try? number.doubleValue(), value.isFinite, abs(value) < 1e12 { expires = Date(timeIntervalSince1970:value+Double(policy.skew)) }
        }
        for (name, enabled, expected) in [("iss",policy.issuerEnabled,policy.issuer),("aud",policy.audienceEnabled,policy.audience),("sub",policy.subjectEnabled,policy.subject)] {
            guard let n = node(name) else { add(name,enabled ? .failed : .notConfigured,enabled ? "Required configured claim is absent." : "Expected value not configured."); continue }
            let strings: [String]
            if name == "aud", n.kind == .array, !n.children.isEmpty, n.children.allSatisfy({ doc.nodes[$0].kind == .string }) { strings = n.children.compactMap { doc.nodes[$0].scalar } }
            else if n.kind == .string, let scalar = n.scalar { strings = [scalar] }
            else { add(name,.failed,"Registered claim has an invalid type."); continue }
            guard enabled else { add(name,.notConfigured,"Expected value not configured; identity was not checked."); continue }
            let passed = strings.contains { $0.unicodeScalars.elementsEqual(expected.unicodeScalars) }
            add(name,passed ? .passed : .failed,passed ? "Exact configured value matched." : "Configured value does not match.")
        }
        if let jti = node("jti"), jti.kind != .string { add("jti",.failed,"JWT ID must be a string; uniqueness is not checked.") }
        return (checks,expires)
    }
}
