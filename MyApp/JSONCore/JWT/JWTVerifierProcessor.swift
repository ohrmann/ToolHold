import Foundation
#if SWIFT_PACKAGE
import CertificateCore
#endif

enum JWTVerifierProcessor {
    static func process(_ request: JWTVerifierRequest, now: Date = .now, budget: JWTBudget = .init()) -> JWTVerifierResult {
        var result = JWTVerifierResult(evaluatedAt:now, revision:request.revision)
        result.referenceTime = request.policy.customTime ? request.policy.reference : now
        result.policySummary = "Reference: \(request.policy.customTime ? "custom UTC" : "device clock") · clock skew: \(request.policy.skew)s · exp/nbf checking: \(request.policy.checkTime ? "on" : "off")"
        do {
            try budget.check()
            let inspection = JWTProcessor.inspect(request.token,budget:budget); result.inspection = inspection
            if inspection.processing == .cancelled { throw CancellationError() }
            if inspection.processing == .resourceLimit { throw JWTVerificationFailure("Token processing limit reached.",resource:true) }
            result.profile = inspection.profile == .unsupported || inspection.representation == .jweCandidate || !inspection.interpretationAvailable ? .unsupported : .malformed
            if [JWTComponent.header,.payload].contains(where:{ component in
                guard let doc = inspection.parts[component]?.document else { return false }
                return doc.nodes[0].children.contains { doc.nodes[$0].occurrences > 1 }
            }) { result.profile = .ambiguous }
            guard inspection.processing == .completed, inspection.representation == .compact,
                  inspection.profile != .unsupported, inspection.interpretationAvailable,
                  let header = inspection.parts[.header]?.document, let payload = inspection.parts[.payload]?.document,
                  header.nodes[0].kind == .object, payload.nodes[0].kind == .object,
                  let token = inspection.token, let declared = inspection.algorithm,
                  let signature = inspection.parts[.signature]?.bytes else { throw JWTVerificationFailure("Token framing, JSON or critical header semantics are invalid or unsupported.") }
            result.profile = .supported
            guard header.nodes[0].children.allSatisfy({ header.nodes[$0].occurrences == 1 }), payload.nodes[0].children.allSatisfy({ payload.nodes[$0].occurrences == 1 }) else { result.profile = .ambiguous; throw JWTVerificationFailure("Duplicate top-level header or claim names make this profile ambiguous.") }
            guard declared != "none", !signature.isEmpty else { result.profile = .unsupported; throw JWTVerificationFailure("Unsigned tokens cannot be signature-verified.") }
            guard JWTSigningAlgorithm(rawValue:declared) != nil else { result.profile = .unsupported; throw JWTVerificationFailure("Token declares an unsupported signing algorithm.") }
            guard let algorithm = request.algorithm, algorithm != .none else { throw JWTVerificationFailure("Explicitly choose the expected algorithm.") }
            result.algorithm = algorithm.rawValue
            guard declared == algorithm.rawValue else { throw JWTVerificationFailure("Declared alg differs from the expected algorithm. No fallback was attempted.") }
            if let cty = JWKReader.member("cty",0,in:header)?.scalar, ["jwt","application/jwt"].contains(cty.lowercased()) { result.profile = .unsupported; throw JWTVerificationFailure("Nested JWT content is not supported.") }
            for n in ["enc","zip"] where JWKReader.member(n,0,in:header) != nil { result.profile = .unsupported; throw JWTVerificationFailure("Encrypted or compressed token profiles are not supported.") }
            for name in ["typ","cty","kid"] {
                if let node = JWKReader.member(name,0,in:header), node.kind != .string { result.profile = .malformed; throw JWTVerificationFailure("Header \(name) must be a string.") }
            }
            let kidNode = JWKReader.member("kid",0,in:header)
            if let kidNode, kidNode.kind != .string { throw JWTVerificationFailure("Token kid must be a string.") }
            guard let dot = token.lastIndex(of:"."), token[..<dot].utf8.allSatisfy({ $0 < 128 }) else { throw JWTVerificationFailure("Signing segments must be ASCII.") }
            try budget.check()
            let (valid, identity, notes) = try JWTVerificationProvider.verify(request,algorithm:algorithm,tokenKid:kidNode?.scalar,message:Data(token[..<dot].utf8),signature:signature,now:now)
            try budget.check()
            result.keyIdentity = identity; result.keyNotes = notes; result.signature = valid ? .matches : .doesNotMatch
            result.message = valid ? "Signature matches. Key provenance and issuer trust are not established by this operation." : "Signature does not match the supplied key and algorithm."
            if valid {
                let (checks,expiry) = try JWTClaimsPolicyEvaluator.evaluate(inspection,policy:request.policy,now:now)
                result.checks = checks; result.expiresAt = expiry; result.claimsEvaluated = true
            }
        } catch is CancellationError { result.processing = .cancelled; result.signature = .notChecked; result.message = "Cancelled" }
        catch is JWTBudget.Limit { result.processing = .resourceLimit; result.signature = .notChecked; result.message = "Verification time limit reached." }
        catch let e as JWTVerificationFailure { result.processing = e.resource ? .resourceLimit : .completed; result.message = e.message }
        catch let e as CertificateFailure { result.processing = e.kind == .resource ? .resourceLimit : .completed; result.message = e.message }
        catch { result.processing = .failed; result.message = "Key import or verification could not be completed." }
        return result
    }
}
