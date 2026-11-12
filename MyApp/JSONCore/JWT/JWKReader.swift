import Foundation
import CryptoKit
#if SWIFT_PACKAGE
import CertificateCore
import EncodingCore
#endif

enum JWKReader {
    static func exact(_ a: String?, _ b: String) -> Bool { a?.unicodeScalars.elementsEqual(b.unicodeScalars) == true }
    static func member(_ name: String, _ id: Int, in doc: JSONStructureDocument) -> JSONStructureNode? {
        doc.nodes[id].children.map { doc.nodes[$0] }.first { exact($0.key,name) }
    }
    static func document(_ source: String) throws -> (JSONStructureDocument, [Int]) {
        let r = JSONProcessor.inspectStructure(source)
        if case .resourceLimit = r.result.status { throw JWTVerificationFailure("JWK JSON resource limit reached.", resource: true) }
        guard let doc = r.document, doc.nodes[0].kind == .object, doc.nodes[0].children.allSatisfy({ doc.nodes[$0].occurrences == 1 }) else { throw JWTVerificationFailure("Expected a unique-member JWK object or JWKS envelope.") }
        if let keys = member("keys",0,in:doc) {
            guard keys.kind == .array, !keys.children.isEmpty, keys.children.count <= 100 else { throw JWTVerificationFailure("JWKS must contain 1–100 key entries.", resource: keys.children.count > 100) }
            return (doc, keys.children)
        }
        return (doc,[0])
    }
    static func choices(_ source: String) throws -> [JWTKeyChoice] {
        let (doc, ids) = try document(source)
        return ids.enumerated().map { ordinal,id in
            let type = member("kty",id,in:doc)?.scalar ?? "Unknown"
            let kid = member("kid",id,in:doc)?.scalar ?? "No kid"
            let curve = member("crv",id,in:doc)?.scalar ?? ""
            let label = "\(ordinal+1) · \(CertificateDisplay.safe(type,limit:24)) · \(CertificateDisplay.safe(kid,limit:48)) \(CertificateDisplay.safe(curve,limit:12))"
            let supported = ["RSA","oct"].contains(type) || (type == "EC" && ["P-256","P-384","P-521"].contains(curve)) || (type == "OKP" && curve == "Ed25519")
            return .init(id:ordinal,title:label,supported:doc.nodes[id].kind == .object && supported)
        }
    }
    struct Key { var material: PublicKeyMaterial?; var secret: Data?; var identity: String; var kid: String? }
    static func key(_ source: String, index: Int?, algorithm: JWTSigningAlgorithm, tokenKid: String?) throws -> Key {
        let (doc, ids) = try document(source)
        guard let index, ids.indices.contains(index) else { throw JWTVerificationFailure("Explicitly select a local JWK entry before verification.") }
        let id = ids[index], root = doc.nodes[id]
        guard root.kind == .object else { throw JWTVerificationFailure("The selected key entry is not an object.") }
        // Inspect the whole selected subtree, not a truncated diagnostic list.
        var stack = [id]
        while let current = stack.popLast() {
            try Task.checkCancellation()
            if doc.nodes[current].occurrences > 1 { throw JWTVerificationFailure("Duplicate JWK property names are ambiguous.") }
            stack += doc.nodes[current].children
        }
        func n(_ name: String) -> JSONStructureNode? { member(name,id,in:doc) }
        func text(_ name: String, required: Bool = true) throws -> String? {
            guard let node = n(name) else { if required { throw JWTVerificationFailure("Missing required JWK property: \(name).") }; return nil }
            guard node.kind == .string, let value = node.scalar else { throw JWTVerificationFailure("JWK property \(name) must be a string.") }; return value
        }
        for name in ["d","p","q","dp","dq","qi","oth"] where n(name) != nil { throw JWTVerificationFailure("Use public verification material, not private JWK parameters.") }
        if let alg = try text("alg",required:false), !exact(alg,algorithm.rawValue) { throw JWTVerificationFailure("JWK alg does not allow the expected algorithm.") }
        if let use = try text("use",required:false), !exact(use,"sig") { throw JWTVerificationFailure("JWK use must permit signatures.") }
        if let operations = n("key_ops") {
            let names = operations.children.compactMap { doc.nodes[$0].scalar.map { Array($0.unicodeScalars.map(\.value)) } }
            guard operations.kind == .array, Set(names).count == names.count, operations.children.allSatisfy({ doc.nodes[$0].kind == .string }), operations.children.contains(where: { exact(doc.nodes[$0].scalar,"verify") }) else { throw JWTVerificationFailure("JWK key_ops does not permit verification.") }
        }
        let kid = try text("kid",required:false)
        if let kid, let tokenKid, !exact(kid,tokenKid) { throw JWTVerificationFailure("Selected JWK kid differs from the token kid.") }
        func bytes(_ name: String) throws -> Data {
            let encoded = try text(name)!
            guard encoded.utf16.prefix(65537).count <= 65536 else { throw JWTVerificationFailure("JWK property exceeds the key-size limit.",resource:true) }
            do { return try JWTBase64URLDecoder.decode(encoded,maximumLength:65536) }
            catch { throw JWTVerificationFailure("Invalid Base64URL in JWK \(name).") }
        }
        let type = try text("kty")!, material: PublicKeyMaterial
        var canonical = ""
        switch type {
        case "oct":
            guard algorithm.family == .hmac else { throw JWTVerificationFailure("An oct key is only accepted for an explicit HMAC algorithm.") }
            let data = try bytes("k"); return .init(secret:data,identity:"Shared secret · local JWK #\(index+1)",kid:kid)
        case "RSA":
            guard algorithm.family == .rsa else { throw JWTVerificationFailure("RSA key does not match the expected algorithm family.") }
            let n = try bytes("n"), e = try bytes("e")
            guard !n.isEmpty, n.first != 0, !e.isEmpty, e.first != 0, n.count <= 1024, e.count <= 8 else { throw JWTVerificationFailure("Invalid RSA Base64urlUInt size or leading zero.") }
            material = try PublicKeyMaterialImporter.rsaPKCS1(PublicKeyDEREncoding.tlv(0x30, PublicKeyDEREncoding.integer(n)+PublicKeyDEREncoding.integer(e)))
            canonical = "{\"e\":\"\(JWTSigningProvider.base64URL(e))\",\"kty\":\"RSA\",\"n\":\"\(JWTSigningProvider.base64URL(n))\"}"
        case "EC":
            guard algorithm.family == .ec else { throw JWTVerificationFailure("EC key does not match the expected algorithm family.") }
            let curve = try text("crv")!, x = try bytes("x"), y = try bytes("y")
            let length: Int
            switch curve { case "P-256": length = 32; case "P-384": length = 48; case "P-521": length = 66; default: throw JWTVerificationFailure("Unsupported JWK curve.") }
            guard x.count == length, y.count == length else { throw JWTVerificationFailure("EC coordinates must use the exact curve width.") }
            material = try PublicKeyMaterialImporter.spki(PublicKeyDEREncoding.ecSPKI(Data([4])+x+y,curve:curve))
            canonical = "{\"crv\":\"\(curve)\",\"kty\":\"EC\",\"x\":\"\(JWTSigningProvider.base64URL(x))\",\"y\":\"\(JWTSigningProvider.base64URL(y))\"}"
        case "OKP":
            guard algorithm.family == .ed, try text("crv") == "Ed25519" else { throw JWTVerificationFailure("Use an Ed25519 key for this algorithm.") }
            let x = try bytes("x"); material = try PublicKeyMaterialImporter.spki(PublicKeyDEREncoding.edSPKI(x))
            canonical = "{\"crv\":\"Ed25519\",\"kty\":\"OKP\",\"x\":\"\(JWTSigningProvider.base64URL(x))\"}"
        default: throw JWTVerificationFailure("Unsupported JWK key type.")
        }
        return .init(material:material, identity:"JWK SHA-256 thumbprint · " + JWTSigningProvider.base64URL(Data(SHA256.hash(data:Data(canonical.utf8)))), kid:kid)
    }
}
