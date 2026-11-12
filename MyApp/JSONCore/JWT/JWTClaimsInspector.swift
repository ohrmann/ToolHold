import Foundation

enum JWTClaimsInspector {
    static let descriptions: [String: String] = [
        "iss": "Issuer · not authenticated", "sub": "Subject · not authenticated", "aud": "Intended audience · not checked against an application",
        "jti": "Token identifier · uniqueness not checked", "exp": "Expiration time · Unix seconds", "nbf": "Not-before time · Unix seconds", "iat": "Issued-at time · Unix seconds"
    ]
    static func inspect(_ document: JSONStructureDocument, result: inout JWTInspectionResult, budget: JWTBudget) throws {
        for id in document.nodes[0].children {
            try budget.check()
            let node = document.nodes[id], name = node.key ?? "", duplicate = node.occurrences > 1
            if duplicate {
                result.hasRootDuplicates = true
                result.add(.init(code: "JWT-DUPLICATE-CLAIM", component: .payload, severity: .error, message: "Duplicate claim name; no occurrence is selected for interpretation.", anchor: .init(space: .json(.payload), range: node.keyRange ?? node.range)))
            }
            let validType: Bool
            switch name {
            case "exp", "nbf", "iat": validType = node.kind == .number
            case "iss", "sub", "jti": validType = node.kind == .string
            case "aud": validType = node.kind == .string || (node.kind == .array && node.children.allSatisfy { document.nodes[$0].kind == .string })
            default: validType = true
            }
            if !validType {
                result.add(.init(code: "JWT-CLAIM-TYPE", component: .payload, severity: .error, message: "Registered claim has an unexpected JSON type.", anchor: .init(space: .json(.payload), range: node.range)))
            }
            if name == "aud", node.kind == .array, node.children.isEmpty {
                result.add(.init(code: "JWT-AUDIENCE-EMPTY", component: .payload, severity: .note, message: "No audiences listed.", anchor: .init(space: .json(.payload), range: node.range)))
            }
            result.claimRows.append(id); result.claimRowNumbers[id] = result.claimRows.count
            result.claims.append(.init(id: id, name: name, namePreview: JSONTreePreview.make(name, budget: 80).text,
                kind: node.kind, preview: JSONTreePreview.make(node.summary, budget: 160).text,
                explanation: descriptions[name] ?? "Custom claim", ambiguous: duplicate,
                numericDate: ["exp", "nbf", "iat"].contains(name) && node.kind == .number ? node.scalar : nil, range: node.range))
        }
        result.missingTimeClaims = ["exp", "nbf", "iat"].filter { name in !result.claims.contains { $0.name == name } }
    }
}
