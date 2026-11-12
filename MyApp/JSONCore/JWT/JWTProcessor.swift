import Foundation
#if SWIFT_PACKAGE
import EncodingCore
#endif

enum JWTProcessor {
    static let maximumLength = 262_144
    static func inspect(_ input: String, budget: JWTBudget = .init()) -> JWTInspectionResult {
        var result = inspectBody(input, budget: budget)
        // Coordinates are prepared off the main thread once per coordinate space.
        let inputCoordinates = JSONSourceCoordinates(String(decoding: input.utf16.prefix(maximumLength), as: UTF16.self))
        let coordinates = Dictionary(uniqueKeysWithValues: result.parts.compactMap { key, part in
            part.text.map { (key, JSONSourceCoordinates($0)) }
        })
        for index in result.issues.indices {
            guard let anchor = result.issues[index].anchor else { continue }
            let location: (line: Int, column: Int)?
            let label: String
            switch anchor.space {
            case .input: location = inputCoordinates.location(at: anchor.range.location); label = "Input"
            case .json(let part): location = coordinates[part]?.location(at: anchor.range.location); label = part.rawValue + " decoded JSON"
            case .bytes(let part): result.issues[index].location = part.rawValue + " decoded byte region"; continue
            }
            if let location { result.issues[index].location = "\(label) · line \(location.line), column \(location.column) (UTF-16)" }
        }
        return result
    }
    private static func inspectBody(_ input: String, budget: JWTBudget) -> JWTInspectionResult {
        var result = JWTInspectionResult()
        do {
            try budget.check()
            guard input.utf16.prefix(maximumLength + 1).count <= maximumLength else {
                result.processing = .resourceLimit
                result.add(.init(code: "JWT-SIZE", component: .input, severity: .error, message: "Input exceeds 262,144 UTF-16 code units.")); return result
            }
            let units = Array(input.utf16), white: Set<UInt16> = [9,10,13,32]
            var start = 0, end = units.count
            while start < end && white.contains(units[start]) { start += 1 }
            while end > start && white.contains(units[end - 1]) { end -= 1 }
            let outer = start != 0 || end != units.count
            var bearer = false
            if end - start >= 6, String(decoding: units[start..<start+6], as: UTF16.self).lowercased() == "bearer",
               end - start == 6 || units[start + 6] == 32 {
                bearer = true; start += 6
                while start < end && units[start] == 32 { start += 1 }
            }
            if outer || bearer { result.add(.init(code: "JWT-ENVELOPE", component: .input, severity: .note, message: "Bearer prefix / surrounding whitespace ignored for inspection. Input is unchanged.")) }
            guard start < end else {
                result.profile = .issues
                result.add(.init(code: "JWT-EMPTY", component: .input, severity: .error, message: "Enter a token.", anchor: .init(space: .input, range: .init(location: start, length: 0)))); return result
            }
            let token = String(decoding: units[start..<end], as: UTF16.self); result.token = token
            let dots = (start..<end).filter { units[$0] == 46 }
            let ranges = zip([start] + dots.map { $0 + 1 }, dots + [end]).map { NSRange(location: $0.0, length: $0.1 - $0.0) }
            if ranges.count == 5 {
                result.representation = .jweCandidate; result.profile = .unsupported; result.interpretationAvailable = false
                result.add(.init(code: "JWT-JWE", component: .input, severity: .note, message: "Five-segment JWE-style representation. Encryption and validity are not evaluated."))
                try decodePart(.header, range: ranges[0], input: input, result: &result, budget: budget)
                result.profile = .unsupported; return result
            }
            guard ranges.count == 3, !token.contains("~") else {
                result.representation = token.contains("~") ? .unsupported : .malformed
                result.add(.init(code: "JWT-FRAMING", component: .input, severity: .error, message: "Expected one compact token with three dot-separated segments. JSON serialization, disclosures and detached representations are not supported.", anchor: .init(space: .input, range: .init(location: end, length: 0))))
                return result
            }
            try decodePart(.header, range: ranges[0], input: input, result: &result, budget: budget)
            let canDecodePayload = try inspectHeader(&result, budget: budget)
            if canDecodePayload { try decodePart(.payload, range: ranges[1], input: input, result: &result, budget: budget) }
            else {
                result.parts[.payload] = .init(component: .payload, encoded: (input as NSString).substring(with: ranges[1]), inputRange: ranges[1])
                result.interpretationAvailable = false
            }
            try decodePart(.signature, range: ranges[2], input: input, result: &result, budget: budget)
            if let alg = result.algorithm {
                if alg == "none" && ranges[2].length == 0 { result.unsigned = true; result.add(.init(code: "JWT-UNSIGNED", component: .signature, severity: .warning, message: "Unsigned token. No integrity protection is provided.")) }
                else if (alg == "none") != (ranges[2].length == 0) {
                    result.add(.init(code: "JWT-SIGNATURE-SHAPE", component: .signature, severity: .error, message: "Signature segment contradicts the declared algorithm.", anchor: .init(space: .input, range: ranges[2])))
                }
            }
            if let document = result.parts[.payload]?.document, document.nodes[0].kind == .object {
                try JWTClaimsInspector.inspect(document, result: &result, budget: budget)
            }
            try budget.check()
            return result
        } catch is JWTBudget.Limit {
            return .init(processing: .resourceLimit, profile: .issues, issues: [.init(code: "JWT-DEADLINE", component: .input, severity: .error, message: "Processing time limit reached. Input is preserved.")], issueCount: 1)
        } catch is CancellationError { return .init(processing: .cancelled) }
        catch { return .init(processing: .failure, profile: .issues, issues: [.init(code: "JWT-PROCESS", component: .input, severity: .error, message: "Inspection could not be completed.")], issueCount: 1) }
    }
    private static func decodePart(_ component: JWTComponent, range: NSRange, input: String, result: inout JWTInspectionResult, budget: JWTBudget) throws {
        try budget.check()
        let encoded = (input as NSString).substring(with: range)
        var part = JWTPart(component: component, encoded: encoded, inputRange: range)
        defer { result.parts[component] = part }
        if encoded.isEmpty && component != .signature {
            result.add(.init(code: "JWT-EMPTY-SEGMENT", component: component, severity: .error, message: "Expected a nonempty encoded JSON object.", anchor: .init(space: .input, range: range))); return
        }
        do { part.bytes = try JWTBase64URLDecoder.decode(encoded) }
        catch let failure as JWTBase64URLDecoder.Failure {
            result.add(.init(code: "JWT-BASE64URL", component: component, severity: .error, message: failure.message,
                anchor: .init(space: .input, range: .init(location: range.location + failure.offset, length: failure.length)))); return
        }
        try budget.check()
        guard component != .signature, let data = part.bytes else { return }
        guard let text = String(data: data, encoding: .utf8) else {
            result.add(.init(code: "JWT-UTF8", component: component, severity: .error, message: "Decoded segment is not valid UTF-8.", anchor: .init(space: .bytes(component), range: .init(location: 0, length: data.count)), related: [.init(space: .input, range: range)])); return
        }
        part.text = text
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            part.text = String(decoding: data, as: UTF8.self) // Foundation may consume the BOM in its strict decoder.
            result.add(.init(code: "JWT-BOM", component: component, severity: .error, message: "A byte order mark is not allowed in this JWT profile.", anchor: .init(space: .json(component), range: .init(location: 0, length: 1)))); return
        }
        if component == .payload && result.nestedContent {
            // A nested compact JWT is text, not a JSON Claims Set. Show raw data
            // without mislabelling a supported outer encoding as malformed JSON.
            let first = text.unicodeScalars.first { ![9, 10, 13, 32].contains($0.value) }
            if first?.value != 123 { return }
        }
        let parsed = JSONProcessor.inspectStructure(text); try budget.check()
        if parsed.result.status == .cancelled { throw CancellationError() }
        if case .resourceLimit = parsed.result.status { result.processing = .resourceLimit }
        part.document = parsed.document
        for diagnostic in parsed.result.diagnostics {
            result.add(.init(code: diagnostic.code, component: component, severity: diagnostic.severity == .error ? .error : .warning,
                message: diagnostic.message, anchor: .init(space: .json(component), range: diagnostic.range),
                related: diagnostic.related.map { .init(space: .json(component), range: $0.range) } + [.init(space: .input, range: range)], diagnostic: diagnostic,
                context: .make(source: text, diagnostic: diagnostic)))
        }
        if let document = parsed.document {
            part.presentation = try JWTJSONPresentation.make(document, budget: budget)
            if document.nodes[0].kind != .object {
                result.add(.init(code: "JWT-OBJECT", component: component, severity: .error, message: "JWT header and claims must be JSON objects.", anchor: .init(space: .json(component), range: document.nodes[0].range)))
            }
        }
    }
    private static func inspectHeader(_ result: inout JWTInspectionResult, budget: JWTBudget) throws -> Bool {
        guard let doc = result.parts[.header]?.document, doc.nodes[0].kind == .object else { result.interpretationAvailable = false; return true }
        let children = doc.nodes[0].children
        var ambiguous = false
        for id in children {
            try budget.check()
            let node = doc.nodes[id]
            if node.occurrences > 1 {
                ambiguous = true
                result.add(.init(code: "JWT-DUPLICATE-HEADER", component: .header, severity: .error, message: "Duplicate header name; header semantics are ambiguous.", anchor: .init(space: .json(.header), range: node.keyRange ?? node.range)))
            }
        }
        if ambiguous { return false }
        func node(_ name: String) -> JSONStructureNode? { children.first(where: { doc.nodes[$0].key?.unicodeScalars.elementsEqual(name.unicodeScalars) == true }).map { doc.nodes[$0] } }
        func issue(_ code: String, _ message: String, _ n: JSONStructureNode?, severity: JWTIssue.Severity = .error) -> JWTIssue {
            .init(code: code, component: .header, severity: severity, message: message, anchor: .init(space: .json(.header), range: n?.range ?? .init(location: doc.nodes[0].range.location + 1, length: 0)))
        }
        if let alg = node("alg"), alg.kind == .string, let value = alg.scalar, !value.isEmpty { result.algorithm = value }
        else { result.add(issue("JWT-ALG", "Expected a unique nonempty string 'alg' header.", node("alg"))) }
        for name in ["typ", "cty"] {
            if let n = node(name) {
                if n.kind != .string { result.add(issue("JWT-HEADER-TYPE", "Expected a string type or content-type header.", n)) }
                else if name == "typ", n.scalar?.lowercased() != "jwt" { result.add(issue("JWT-TYP", "Declared type differs from JWT; the declaration is not authenticated.", n, severity: .note)) }
            }
        }
        var encoded = true
        if let b64 = node("b64") {
            if b64.kind != .boolean { result.add(issue("JWT-B64", "Expected boolean 'b64'. Payload encoding is unknown.", b64)); encoded = false }
            else if b64.scalar == "false" {
                result.add(issue("JWT-UNENCODED", "Unencoded payloads are not supported by this JWT profile.", b64, severity: .note)); result.profile = .unsupported; encoded = false
            }
        }
        if let cty = node("cty"), cty.scalar?.uppercased() == "JWT" {
            result.add(issue("JWT-NESTED", "Nested content is not interpreted recursively.", cty, severity: .warning)); result.interpretationAvailable = false; result.nestedContent = true; result.profile = .unsupported
        }
        if let crit = node("crit") {
            let names = crit.children.map { doc.nodes[$0] }
            let valid = crit.kind == .array && !names.isEmpty && names.allSatisfy { $0.kind == .string && !($0.scalar ?? "").isEmpty }
            let scalarNames = names.map { Array(($0.scalar ?? "").unicodeScalars.map(\.value)) }
            if !valid || Set(scalarNames).count != names.count { result.add(issue("JWT-CRIT", "Critical header list must contain unique nonempty names.", crit)); result.interpretationAvailable = false }
            else {
                let forbidden: Set<String> = ["alg","jku","jwk","kid","x5u","x5c","x5t","x5t#S256","typ","cty","crit"]
                for n in names {
                    let name = n.scalar ?? ""
                    if node(name) == nil || forbidden.contains(name) { result.add(issue("JWT-CRIT-MEMBER", "Critical header name is absent or is not an allowed extension.", n)); result.interpretationAvailable = false }
                    else if name != "b64" || node("b64")?.scalar != "true" {
                        result.add(issue("JWT-CRIT-UNSUPPORTED", "Critical extension semantics are not supported.", n, severity: .warning)); result.profile = .unsupported; result.interpretationAvailable = false
                    }
                }
            }
        }
        return encoded
    }
}
