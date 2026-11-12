import Foundation

enum JWTEncoderProcessor {
    static func process(_ request: JWTEncoderRequest, mode: JWTEncoderMode = .generate, budget: JWTBudget = .init(), now: Date = .now) -> JWTEncoderResult {
        var result = JWTEncoderResult()
        do {
            try budget.check()
            let header = try parse(request.header, component: .header, result: &result)
            let payload = try parse(request.payload, component: .payload, result: &result)
            try budget.check()
            let algorithm = try header.flatMap { try checkHeader($0, result: &result, budget: budget) }
            if let payload { try checkClaims(payload, now: now, result: &result, budget: budget) }
            guard let header, let payload, let algorithm, !result.issues.contains(where: { $0.severity == .error }) else {
                if result.status == .checked { result.status = .invalidInput }
                return result
            }
            if mode == .jsonOnly { return result }
            let key = try JWTSigningProvider.prepare(request, algorithm: algorithm)
            try budget.check()
            if algorithm == .none { result.add(.init(code: "UNSIGNED", component: .operation, severity: .warning, message: "Unsigned token. No integrity protection. Use for testing only.")) }
            if algorithm == .edDSA { result.add(.init(code: "LEGACY-EDDSA", component: .operation, severity: .warning, message: "Legacy EdDSA identifier (Ed25519 only). Prefer Ed25519 for new integrations.")) }
            let headerText = request.serialization == .preserve ? request.header : try compact(header, budget: budget)
            let payloadText = request.serialization == .preserve ? request.payload : try compact(payload, budget: budget)
            func encodedLength(_ count: Int) -> Int { count / 3 * 4 + (count % 3 == 0 ? 0 : count % 3 + 1) }
            let total = encodedLength(headerText.utf8.count) + encodedLength(payloadText.utf8.count) + encodedLength(key.signatureBytes) + 2
            guard total <= JWTEncoderLimits.token else {
                throw JWTSigningFailure(code: "TOKEN-SIZE", message: "Generated JWT would exceed 262,144 ASCII bytes. Reduce the JSON or use Compact JSON.", status: .resourceLimit)
            }
            guard mode == .generate else { return result }
            let signingInput = JWTSigningProvider.base64URL(Data(headerText.utf8)) + "." + JWTSigningProvider.base64URL(Data(payloadText.utf8))
            try budget.check()
            let signature: Data
            do { signature = try key.sign(Data(signingInput.utf8)) }
            catch let error as JWTSigningFailure { throw error }
            catch { throw JWTSigningProvider.failed }
            try budget.check()
            let token = signingInput + "." + JWTSigningProvider.base64URL(signature)
            result.artifact = .init(revision: request.revision, token: token, algorithm: algorithm)
            result.status = .generated
        } catch is CancellationError { result.status = .cancelled; result.artifact = nil }
        catch is JWTBudget.Limit { result.status = .resourceLimit; result.add(.init(code: "ENCODER-DEADLINE", component: .operation, severity: .error, message: "Processing time limit reached. Input is preserved.")) }
        catch let failure as JWTSigningFailure {
            result.status = failure.status
            result.add(.init(code: failure.code, component: failure.code.hasPrefix("KEY-") ? .key : .operation, severity: .error, message: failure.message))
        } catch { result.status = .cryptoFailure; result.add(.init(code: "ENCODER-FAILURE", component: .operation, severity: .error, message: "The operation could not be completed.")) }
        return result
    }
    private static func parse(_ source: String, component: JWTEncoderIssue.Component, result: inout JWTEncoderResult) throws -> JSONStructureDocument? {
        let parsed = JSONProcessor.inspectStructure(source)
        if parsed.result.status == .cancelled { throw CancellationError() }
        if case .resourceLimit = parsed.result.status { result.status = .resourceLimit }
        for diagnostic in parsed.result.diagnostics where diagnostic.severity == .error {
            result.add(.init(code: diagnostic.code, component: component, severity: .error, message: diagnostic.message,
                             diagnostic: diagnostic, context: .make(source: source, diagnostic: diagnostic)))
        }
        guard let doc = parsed.document else { return nil }
        if doc.nodes[0].kind != .object { add("JWT-OBJECT", "JWT header and claims must be JSON objects.", doc.nodes[0].range, in: doc, component: component, result: &result) }
        if source.unicodeScalars.first?.value == 0xfeff { add("JWT-BOM", "A byte order mark is not supported in JWT JSON.", .init(location: 0, length: 1), in: doc, component: component, result: &result) }
        for node in doc.nodes {
            if node.id & 255 == 0 { try Task.checkCancellation() }
            if node.occurrences > 1 { add("JWT-DUPLICATE", "Duplicate member names are not supported by this encoder profile.", node.keyRange ?? node.range, in: doc, component: component, result: &result) }
        }
        return doc
    }
    private static func add(_ code: String, _ message: String, _ range: NSRange, in doc: JSONStructureDocument, component: JWTEncoderIssue.Component, result: inout JWTEncoderResult, severity: JSONDiagnostic.Severity = .error) {
        guard result.issues.count < 100 else { result.issueCount += 1; return }
        let position = JSONSourceCoordinates(doc.source).location(at: range.location)
        let diagnostic = JSONDiagnostic(severity: severity, code: code, message: message, range: range, line: position.line, column: position.column)
        result.add(.init(code: code, component: component, severity: severity, message: message, diagnostic: diagnostic, context: .make(source: doc.source, diagnostic: diagnostic)))
    }
    private static func checkHeader(_ doc: JSONStructureDocument, result: inout JWTEncoderResult, budget: JWTBudget) throws -> JWTSigningAlgorithm? {
        guard doc.nodes[0].kind == .object else { return nil }
        var found = false
        var algorithm: JWTSigningAlgorithm?
        let unsupported: Set<String> = ["crit", "b64", "enc", "zip", "jku", "jwk", "x5u", "x5c", "x5t", "x5t#S256"]
        for id in doc.nodes[0].children {
            try budget.check()
            let node = doc.nodes[id], name = node.key ?? ""
            if name == "alg" {
                found = true
                if node.kind != .string {
                    add("JWT-ALG-TYPE", "Header 'alg' must be a string.", node.range, in: doc, component: .header, result: &result)
                } else if let value = node.scalar, let supported = JWTSigningAlgorithm(rawValue: value) {
                    // Duplicate names are rejected by parse(), never resolve an occurrence.
                    if node.occurrences == 1 { algorithm = supported }
                } else {
                    add("JWT-ALG-UNSUPPORTED", "Header 'alg' is not a supported signing algorithm.", node.range, in: doc, component: .header, result: &result)
                    if result.status != .resourceLimit { result.status = .unsupported }
                }
            }
            if ["typ", "kid", "cty"].contains(name), node.kind != .string { add("JWT-HEADER-TYPE", "Header '\(name)' must be a string.", node.range, in: doc, component: .header, result: &result) }
            let nestedContent = name == "cty" && ["jwt", "application/jwt"].contains(node.scalar?.lowercased() ?? "")
            if name == "cty", node.kind == .string, !nestedContent {
                add("JWT-CTY-NOTE", "The content-type header is preserved as metadata; the payload remains a JSON Claims Set.", node.range, in: doc, component: .header, result: &result, severity: .warning)
            }
            if unsupported.contains(name) || nestedContent {
                add("JWT-HEADER-UNSUPPORTED", "Header '\(name)' is outside this compact JWT encoder profile.", node.keyRange ?? node.range, in: doc, component: .header, result: &result)
                if result.status != .resourceLimit { result.status = .unsupported }
            }
        }
        if !found { add("JWT-ALG-MISSING", "Add an 'alg' string to the Header, or choose an algorithm to insert it.", .init(location: doc.nodes[0].range.location + 1, length: 0), in: doc, component: .header, result: &result) }
        return algorithm
    }
    private static func checkClaims(_ doc: JSONStructureDocument, now: Date, result: inout JWTEncoderResult, budget: JWTBudget) throws {
        guard doc.nodes[0].kind == .object else { return }
        var inspection = JWTInspectionResult()
        try JWTClaimsInspector.inspect(doc, result: &inspection, budget: budget)
        for issue in inspection.issues where issue.code == "JWT-CLAIM-TYPE" {
            add(issue.code, issue.message, issue.anchor?.range ?? doc.nodes[0].range, in: doc, component: .payload, result: &result)
        }
        let evaluation = JWTNumericDate.evaluate(inspection, now: now)
        for claim in inspection.claims where !claim.ambiguous {
            if let status = evaluation.values[claim.id]?.status, ["Expired", "Not yet valid", "Issued in the future"].contains(status) {
                add("JWT-TIME-NOTE", "\(claim.name): \(status.lowercased()) at the device clock snapshot. No claim was changed.", claim.range, in: doc, component: .payload, result: &result, severity: .warning)
            }
        }
        for note in evaluation.notes { result.add(.init(code: "JWT-TIME-WINDOW", component: .payload, severity: .warning, message: note)) }
    }
    /// Arena emitter uses only captured ranges, not a second grammar or numeric conversion.
    private static func compact(_ doc: JSONStructureDocument, budget: JWTBudget) throws -> String {
        let source = doc.source as NSString
        var text = ""
        func emit(_ id: Int) throws {
            try budget.check()
            let node = doc.nodes[id]
            if node.kind == .array || node.kind == .object {
                text += node.kind == .array ? "[" : "{"
                for (index, child) in node.children.enumerated() {
                    if index > 0 { text += "," }
                    if let key = doc.nodes[child].keyRange { text += source.substring(with: key) + ":" }
                    try emit(child)
                }
                text += node.kind == .array ? "]" : "}"
            } else { text += source.substring(with: node.range) }
        }
        try emit(0); return text
    }
    /// UI projection only. Signing resolves the algorithm from its own strict snapshot.
    /// Call off the main thread; malformed, duplicate or unsupported headers have no selection.
    static func headerAlgorithm(_ source: String) -> JWTSigningAlgorithm? {
        guard let doc = JSONProcessor.inspectStructure(source).document,
              doc.nodes[0].kind == .object,
              !doc.nodes.contains(where: { $0.occurrences > 1 }),
              let node = doc.nodes[0].children.map({ doc.nodes[$0] }).first(where: { $0.key == "alg" }),
              node.kind == .string, let value = node.scalar else { return nil }
        return JWTSigningAlgorithm(rawValue: value)
    }
    static func algorithmEdit(header: String, algorithm: JWTSigningAlgorithm) -> (NSRange, String)? {
        guard header.utf16.prefix(JWTEncoderLimits.json + 1).count <= JWTEncoderLimits.json else { return nil }
        if header.utf8.allSatisfy({ [9, 10, 13, 32].contains($0) }) {
            return (.init(location: 0, length: header.utf16.count), "{\n  \"alg\": \"\(algorithm.rawValue)\",\n  \"typ\": \"JWT\"\n}")
        }
        let parsed = JSONProcessor.inspectStructure(header)
        guard let doc = parsed.document, doc.nodes[0].kind == .object, !doc.nodes.contains(where: { $0.occurrences > 1 }) else { return nil }
        if let node = doc.nodes[0].children.map({ doc.nodes[$0] }).first(where: { $0.key == "alg" }) { return (node.range, "\"\(algorithm.rawValue)\"") }
        return (.init(location: NSMaxRange(doc.nodes[0].range) - 1, length: 0), (doc.nodes[0].children.isEmpty ? "" : ",") + "\"alg\":\"\(algorithm.rawValue)\"")
    }
}
