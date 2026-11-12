import Foundation
import Security
import SwiftASN1
#if canImport(CertificateCore)
import CertificateCore
#endif
import CToolboxPKI

@globalActor public actor PKIExecution { public static let shared = PKIExecution() }

/// One serial executor for all PKI windows. No C handle crosses the actor boundary.
@PKIExecution public final class PKIEngine {
    private var context: PKIHandle?
    private var artifactID = UUID()
    private var lastPFX: PKIPFXInfo?
    public nonisolated init() {}
    public func clear() { context = nil; lastPFX = nil; artifactID = UUID() }
    public func clear(ifCurrent token: UUID) { if artifactID == token { clear() } }
    public func version() -> String { String(cString: tb_pki_version()) }
    private func fresh() throws -> PKIHandle { try Task.checkCancellation(); let c = try PKIHandle(); context = c; lastPFX = nil; artifactID = UUID(); return c }
    private func current(_ token: UUID) throws -> PKIHandle { guard token == artifactID, let context else { throw PKIFailure("Result is no longer current") }; try Task.checkCancellation(); return context }
    public func token() -> UUID { artifactID }
    static func password(_ s: String, export: Bool = false, pfx: Bool = false) throws {
        guard !s.utf8.contains(0), s.utf8.count <= 1024 else { throw PKIFailure("Passwords cannot contain NUL and must fit in 1024 UTF-8 bytes") }
        if export && s.isEmpty { throw PKIFailure("Enter an export password") }
        if export && pfx && s.unicodeScalars.contains(where: { $0.value > 0xffff }) { throw PKIFailure("For portable PFX export use BMP characters or an ASCII passphrase; the password was not modified") }
    }
    private func key(_ data: Data, password: String, c: PKIHandle) throws -> Int32 {
        try Self.password(password)
        let objects = try objects(data, hint: nil, c: c, validate: false)
        guard objects.count == 1, let object = objects.first, object.label.contains("KEY") else { throw PKIFailure("Choose one private or public key") }
        let index = object.data.withUnsafeBytes { raw in tb_pki_key_load(c.raw, raw.bindMemory(to: UInt8.self).baseAddress, raw.count, object.label, password) }
        guard index >= 0 else { throw c.error() }; return index
    }
    private func info(_ index: Int32, c: PKIHandle) throws -> PKIKeyInfo {
        let priv = tb_pki_key_is_private(c.raw, index) != 0
        let valid = tb_pki_key_check(c.raw, index, priv ? 1 : 0) != 0
        let spki = try c.bytes { tb_pki_key_public(c.raw, index, $0) }
        return .init(handle: index, algorithm: String(cString: tb_pki_key_algorithm(c.raw, index)), bits: Int(tb_pki_key_bits(c.raw, index)), isPrivate: priv, spki: spki, consistent: valid, publicDetails:String(decoding:try c.bytes { tb_pki_key_details(c.raw,index,$0) },as:UTF8.self))
    }
    static let labels: Set<String> = ["CERTIFICATE", "CERTIFICATE REQUEST", "NEW CERTIFICATE REQUEST", "PUBLIC KEY", "RSA PUBLIC KEY", "PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY", "ENCRYPTED PRIVATE KEY"]
    private func objects(_ data: Data, hint: String?, c: PKIHandle, validate: Bool = true) throws -> [PKIObject] {
        guard !data.isEmpty else { throw PKIFailure("Enter PEM text or open a DER file") }
        if let text = String(data:data,encoding:.utf8), text.contains("Proc-Type:") || text.contains("DEK-Info:") || text.hasPrefix("Bag Attributes") { throw PKIFailure("Legacy PEM headers and Bag Attributes are not supported; use a plain PEM envelope or encrypted PKCS#8",status:.unsupported) }
        guard data.count <= PKILimits.file else { throw PKIFailure("Input exceeds 4 MiB", status: .resourceLimit) }
        let objects: [PKIObject]
        if let text = String(data: data, encoding: .utf8), text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-----") {
            objects = try PEMEnvelopeReader.read(text, allowed: Self.labels, maximumCount: 64).enumerated().map { .init(id: $0.offset, label: $0.element.label, data: $0.element.der, sourceRange: $0.element.range) }
        } else {
            guard data.count <= PKILimits.object else { throw PKIFailure("DER object exceeds 256 KiB", status: .resourceLimit) }
            // Strict DER consumes the entire input and rejects BER/non-minimal wrappers.
            _ = try DER.parse(Array(data))
            let types = hint.map { [$0] } ?? ["CERTIFICATE", "CERTIFICATE REQUEST", "PUBLIC KEY", "PRIVATE KEY", "ENCRYPTED PRIVATE KEY", "RSA PUBLIC KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY"]
            var matches: [String] = []
            for type in types {
                let probe = try PKIHandle()
                let valid = data.withUnsafeBytes { tb_pki_schema(probe.raw, $0.bindMemory(to: UInt8.self).baseAddress, $0.count, type) }
                if valid != 0 { matches.append(type) }
            }
            guard matches.count == 1, let type = matches.first else { throw PKIFailure(matches.isEmpty ? "Unsupported DER object; PFX belongs in PKCS#12 Manager" : "Ambiguous DER: choose the object type", status: .unsupported) }
            objects = [.init(id: 0, label: type, data: data, sourceRange: nil)]
        }
        for object in objects {
            try Task.checkCancellation(); _ = try DER.parse(Array(object.data))
            if validate {
                let valid = object.data.withUnsafeBytes { tb_pki_schema(c.raw, $0.bindMemory(to: UInt8.self).baseAddress, $0.count, object.label) }
                guard valid != 0 else { throw c.error() }
            }
        }
        return objects
    }
    public func convert(_ data: Data, hint: String? = nil) throws -> [PKIObject] { let c = try fresh(); return try objects(data, hint: hint, c: c) }
    public func inspectKey(_ data: Data, password: String) throws -> PKIKeyInfo { let c = try fresh(); var value = try info(key(data, password: password, c: c), c: c); value.sourceFingerprint = try objects(data,hint:nil,c:c,validate:false).first?.fingerprint; return value }
    public func generate(_ draft: PKIGenerationDraft, csr: Bool) throws -> PKIGenerated {
        let c = try fresh(); let validated = try PKINameAndSAN.validate(draft, csr: csr)
        let keyIndex: Int32
        if draft.useImportedKey { keyIndex = try key(Data(draft.importedKey.utf8), password: draft.keyPassword, c: c) }
        else { keyIndex = tb_pki_key_generate(c.raw, draft.algorithm.name, draft.algorithm.bits); guard keyIndex >= 0 else { throw c.error() } }
        try Task.checkCancellation()
        let names = validated.fields.map { (strdup($0.0), strdup($0.1)) }, sans = validated.sans.map { (Int32($0.kind.rawValue), strdup($0.value)) }
        defer { for (a,b) in names { free(a); free(b) }; for (_,b) in sans { free(b) } }
        guard names.allSatisfy({ $0.0 != nil && $0.1 != nil }), sans.allSatisfy({ $0.1 != nil }) else { throw PKIFailure("Allocation failed", status: .failed) }
        let fields = names.map { TBPKIField(oid: UnsafePointer($0.0!), value: UnsafePointer($0.1!)) }
        let rows = sans.map { TBPKISAN(type: $0.0, value: UnsafePointer($0.1!)) }
        let bytes = try c.bytes { out in fields.withUnsafeBufferPointer { f in rows.withUnsafeBufferPointer { s in
            tb_pki_generate(c.raw, keyIndex, csr ? 1 : 0, f.baseAddress, f.count, s.baseAddress, s.count, Int32(draft.profile.rawValue), Int32(draft.pathLength), Int64(draft.notBefore.timeIntervalSince1970), Int64(draft.notAfter.timeIntervalSince1970), out)
        } } }
        let result = PKIObject(id: 0, label: csr ? "CERTIFICATE REQUEST" : "CERTIFICATE", data: bytes, sourceRange: nil)
        if csr { _ = try csrInfo(result, c: c) } else { guard CertificateDER.inspect(bytes).parsed else { throw PKIFailure("Generated certificate failed independent structure check", status: .failed) } }
        try Task.checkCancellation(); return .init(object: result, key: try info(keyIndex, c: c))
    }
    public func exportKey(token: UUID, key: Int32, password: String, unencrypted: Bool) throws -> PKIObject {
        try Self.password(password, export: !unencrypted); let c = try current(token)
        if lastPFX != nil && lastPFX?.verified != true { throw PKIFailure("Private extraction requires authenticated PFX integrity", status: .unsupported) }
        let bytes = try c.bytes { tb_pki_key_private(c.raw, key, password, unencrypted ? 1 : 0, $0) }
        // Read-back the exact exported bytes before handing them to the exporter.
        let verify = try PKIHandle(); let label = unencrypted ? "PRIVATE KEY" : "ENCRYPTED PRIVATE KEY"
        let index = bytes.withUnsafeBytes { tb_pki_key_load(verify.raw, $0.bindMemory(to: UInt8.self).baseAddress, $0.count, label, password) }
        guard index >= 0, try info(index, c: verify).spki == info(key, c: c).spki else { throw PKIFailure("Private export self-check failed", status: .failed) }
        return .init(id: 0, label: label, data: bytes, sourceRange: nil)
    }
    private func csrInfo(_ object: PKIObject, c: PKIHandle) throws -> PKICSRInfo {
        var report = TBPKIBuffer(), spki = TBPKIBuffer(); defer { tb_pki_buffer_free(report); tb_pki_buffer_free(spki) }
        let valid = object.data.withUnsafeBytes { tb_pki_csr_inspect(c.raw, $0.bindMemory(to: UInt8.self).baseAddress, $0.count, &report, &spki) }
        guard valid >= 0 else { throw c.error() }
        let text = String(decoding: Data(bytes: report.bytes, count: report.count), as: UTF8.self)
        return .init(object: object, signatureValid: valid == 1, summary: text.components(separatedBy: "\n").map { CertificateDisplay.safe($0) }.joined(separator: "\n"), spki: Data(bytes: spki.bytes, count: spki.count))
    }
    public func inspectCSR(_ data: Data) throws -> PKICSRInfo {
        let c = try fresh(), items = try objects(data, hint: nil, c: c)
        guard items.count == 1, let object = items.first, object.label.contains("REQUEST") else { throw PKIFailure("Choose one PKCS#10 request") }
        return try csrInfo(object, c: c)
    }
    private func certificates(_ data: Data, c: PKIHandle) throws -> [Int32] {
        guard !data.isEmpty else { return [] }
        return try objects(data, hint: "CERTIFICATE", c: c).map { item in
            guard item.label == "CERTIFICATE" else { throw PKIFailure("Choose certificate objects only") }
            let i = item.data.withUnsafeBytes { tb_pki_cert_load(c.raw, $0.bindMemory(to: UInt8.self).baseAddress, $0.count) }
            guard i >= 0 else { throw c.error() }; return i
        }
    }
    public func match(certificate: Data, certificateIndex: Int, privateKey: Data, password: String) throws -> (Bool, PKIKeyInfo) {
        let c = try fresh(), certs = try certificates(certificate, c: c)
        guard certs.indices.contains(certificateIndex) else { throw PKIFailure("Select a certificate") }
        let k = try key(privateKey, password: password, c: c), result = tb_pki_match(c.raw, certs[certificateIndex], k)
        guard result >= 0 else { throw c.error() }; return (result == 1, try info(k, c: c))
    }
    public func openPFX(_ data: Data, password: String, legacy: Bool, unverified: Bool) throws -> PKIPFXInfo {
        try Self.password(password); let c = try fresh()
        let result = try readPFX(data, password: password, legacy: legacy, unverified: unverified, c: c); lastPFX = result; return result
    }
    private func readPFX(_ data: Data, password: String, legacy: Bool, unverified: Bool, c: PKIHandle) throws -> PKIPFXInfo {
        guard data.count <= PKILimits.pfx else { throw PKIFailure("PFX exceeds 8 MiB", status: .resourceLimit) }
        _ = try BER.parse(Array(data))
        let ok = data.withUnsafeBytes { tb_pki_pfx_open(c.raw, $0.bindMemory(to: UInt8.self).baseAddress, $0.count, password, legacy ? 1 : 0, unverified ? 1 : 0) }
        guard ok != 0 else { throw c.error() }
        var bags = try (0..<tb_pki_pfx_count(c.raw)).map { i in
            let k = tb_pki_pfx_key(c.raw, i), x = tb_pki_pfx_cert(c.raw, i)
            var certificateDER: Data?
            if x >= 0 {
                let bag = try c.bytes { tb_pki_pfx_bag_der(c.raw,i,$0) }
                func children(_ node: ASN1Node) throws -> [ASN1Node] { guard case .constructed(let values) = node.content else { throw PKIFailure("Invalid certificate bag") }; return Array(values) }
                let fields = try children(DER.parse(Array(bag)))
                guard fields.count >= 2 else { throw PKIFailure("Invalid certificate bag") }
                let wrapper = try children(fields[1]); guard wrapper.count == 1 else { throw PKIFailure("Invalid certificate bag") }
                let certBag = try children(wrapper[0]); guard certBag.count == 2 else { throw PKIFailure("Invalid certificate bag") }
                let inner = try children(certBag[1]); guard inner.count == 1, inner[0].identifier == .octetString, case .primitive(let raw) = inner[0].content else { throw PKIFailure("Invalid certificate bag") }
                let exact = Data(raw); _ = try DER.parse(Array(exact))
                guard exact == (try c.bytes { tb_pki_cert_der(c.raw,x,$0) }) else { throw PKIFailure("Noncanonical certificate bag cannot be exported losslessly",status:.unsupported) }
                certificateDER = exact
            }
            let text = String(cString: tb_pki_pfx_description(c.raw, i)).components(separatedBy: "\n").map { CertificateDisplay.safe($0) }.joined(separator: "\n")
            return PKIBag(id: Int(i), key: k, certificate: x, summary: text, certificateDER: certificateDER, publicKey: k >= 0 ? try info(k, c: c) : nil)
        }
        let certs = bags.filter { $0.certificate >= 0 }.map(\.certificate)
        for i in bags.indices where bags[i].key >= 0 { bags[i].matchingCertificates = certs.filter { tb_pki_public_match(c.raw,$0,bags[i].key) == 1 } }
        return .init(bags: bags, verified: tb_pki_pfx_verified(c.raw) != 0, rewritable: tb_pki_pfx_rewritable(c.raw) != 0, protection: String(decoding:try c.bytes { tb_pki_pfx_info(c.raw,$0) },as:UTF8.self))
    }
    public func createPFX(privateKey: Data?, certificate: Data, extras: Data, password: String, keyPassword: String, name: String) throws -> Data {
        try Self.password(password, export: true, pfx: true); guard !name.utf8.contains(0), name.utf8.count <= 256 else { throw PKIFailure("Friendly name must fit in 256 bytes and contain no NUL") }
        let c = try fresh(), leafs = try certificates(certificate, c: c), additional = try certificates(extras, c: c)
        guard leafs.count <= 1, !leafs.isEmpty || !additional.isEmpty else { throw PKIFailure("Choose one leaf certificate or a certificate-only bundle") }
        let k = try privateKey.map { try key($0, password: keyPassword, c: c) } ?? -1
        let output = try c.bytes { out in additional.withUnsafeBufferPointer { tb_pki_pfx_create(c.raw, k, leafs.first ?? -1, $0.baseAddress, $0.count, name, password, out) } }
        let check = try PKIHandle(), decoded = try readPFX(output, password: password, legacy: false, unverified: false, c: check)
        guard decoded.verified, decoded.bags.filter({ $0.key >= 0 }).count == (k >= 0 ? 1 : 0), decoded.bags.filter({ $0.certificate >= 0 }).count == leafs.count + additional.count else { throw PKIFailure("PFX read-back check failed", status: .failed) }
        try verifyPFXContents(decoded,c:c,key:k,certificates:leafs+additional)
        return output
    }
    private func verifyPFXContents(_ result: PKIPFXInfo, c: PKIHandle, key: Int32, certificates: [Int32]) throws {
        let expected = try certificates.map { index in try c.bytes { tb_pki_cert_der(c.raw,index,$0) } }
        var actual = result.bags.compactMap(\.certificateDER)
        for data in expected { guard let index = actual.firstIndex(of:data) else { throw PKIFailure("PFX certificate read-back differs",status:.failed) }; actual.remove(at:index) }
        guard actual.isEmpty else { throw PKIFailure("Unexpected PFX certificate",status:.failed) }
        let keys = result.bags.compactMap(\.publicKey)
        if key >= 0 { guard keys.count == 1, keys[0].consistent, try keys[0].spki == info(key,c:c).spki else { throw PKIFailure("PFX key read-back differs",status:.failed) } }
        else if !keys.isEmpty { throw PKIFailure("Unexpected private key",status:.failed) }
    }
    public func repackagePFX(token: UUID, password: String) throws -> Data {
        try Self.password(password, export: true, pfx: true); let c = try current(token)
        guard let original = lastPFX, original.verified, original.rewritable else { throw PKIFailure("Whole-container rewrite is not safe for this inventory", status: .unsupported) }
        let output = try c.bytes { tb_pki_pfx_repackage(c.raw, password, $0) }
        let verify = try PKIHandle(), result = try readPFX(output, password: password, legacy: false, unverified: false, c: verify)
        guard result.bags.count == original.bags.count, result.verified else { throw PKIFailure("PFX inventory self-check failed", status: .failed) }
        for (a,b) in zip(original.bags, result.bags) {
            guard a.certificateDER == b.certificateDER, a.publicKey?.spki == b.publicKey?.spki, a.summary == b.summary else { throw PKIFailure("PFX repackage would change an inventory entry", status: .failed) }
        }
        return output
    }
    public func subsetPFX(token: UUID, key: Int32, leaf: Int32, extras: [Int32], name: String, password: String) throws -> Data {
        try Self.password(password, export: true, pfx: true); let c = try current(token)
        guard lastPFX?.verified == true else { throw PKIFailure("Subset export requires authenticated integrity", status: .unsupported) }
        guard name.utf8.count <= 256, !name.utf8.contains(0) else { throw PKIFailure("Invalid friendly name") }
        let output = try c.bytes { out in extras.withUnsafeBufferPointer { tb_pki_pfx_create(c.raw, key, leaf, $0.baseAddress, $0.count, name, password, out) } }
        let verify = try PKIHandle(), result = try readPFX(output, password: password, legacy: false, unverified: false, c: verify)
        guard result.verified, result.bags.filter({ $0.key >= 0 }).count == (key >= 0 ? 1 : 0), result.bags.filter({ $0.certificate >= 0 }).count == extras.count + (leaf >= 0 ? 1 : 0) else { throw PKIFailure("Subset export self-check failed", status: .failed) }
        try verifyPFXContents(result,c:c,key:key,certificates:(leaf >= 0 ? [leaf] : [])+extras)
        return output
    }
    public func validateChain(leaf: Data, intermediates: Data, roots: Data, policy: Int, host: String, at: Date, system: Bool) throws -> PKIChainResult {
        guard at.timeIntervalSince1970.isFinite, (0...253402300799).contains(at.timeIntervalSince1970) else { throw PKIFailure("Verification date must be between 1970 and 9999") }
        let c = try fresh(), l = try certificates(leaf, c: c), i = try certificates(intermediates, c: c), r = system ? [] : try certificates(roots, c: c)
        guard l.count == 1, l.count + i.count + r.count <= 64 else { throw PKIFailure("Choose one leaf; maximum 64 certificates total") }
        let canonicalHost = policy == 0 ? try PKINameAndSAN.host(host) : ""
        if system { return try systemTrust(c: c, leaf: l[0], intermediates: i, policy: policy, host: canonicalHost, at: at) }
        var buffer = TBPKIBuffer(); defer { tb_pki_buffer_free(buffer) }
        let result = i.withUnsafeBufferPointer { ii in r.withUnsafeBufferPointer { rr in tb_pki_chain(c.raw, l[0], ii.baseAddress, ii.count, rr.baseAddress, rr.count, Int32(policy), canonicalHost, Int64(at.timeIntervalSince1970), &buffer) } }
        guard result >= 0 else { throw c.error() }
        let text = "Evaluated: \(CertificateDisplay.date(at))\n" + String(decoding: Data(bytes: buffer.bytes, count: buffer.count), as: UTF8.self)
        return .init(valid: result == 1, report: text.components(separatedBy: "\n").map { CertificateDisplay.safe($0) }.joined(separator: "\n"), chain: try (0..<tb_pki_chain_count(c.raw)).map { index in try c.bytes { tb_pki_cert_der(c.raw,tb_pki_chain_certificate(c.raw,index),$0) } })
    }
    private func systemTrust(c: PKIHandle, leaf: Int32, intermediates: [Int32], policy: Int, host: String, at: Date) throws -> PKIChainResult {
        let certs = try ([leaf] + intermediates).map { i -> SecCertificate in
            let data = try c.bytes { tb_pki_cert_der(c.raw, i, $0) }; guard let cert = SecCertificateCreateWithData(nil, data as CFData) else { throw PKIFailure("System certificate parser rejected input", status: .unsupported) }; return cert
        }
        let p = policy == 2 ? SecPolicyCreateBasicX509() : SecPolicyCreateSSL(policy == 0, policy == 0 ? host as CFString : nil)
        var trust: SecTrust?; guard SecTrustCreateWithCertificates(certs as CFArray, p, &trust) == errSecSuccess, let trust,
            SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess, SecTrustSetVerifyDate(trust, at as CFDate) == errSecSuccess else { throw PKIFailure("Could not configure offline system trust", status: .failed) }
        var error: CFError?; let evaluated = SecTrustEvaluateWithError(trust, &error)
        let sanMatches = policy != 0 || tb_pki_cert_hostname(c.raw,leaf,host) == 1
        let valid = evaluated && sanMatches
        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate] ?? []).map { SecCertificateCopyData($0) as Data }
        let summary = chain.enumerated().map { "\($0.offset + 1). \(CertificateDisplay.safe(CertificateDER.inspect($0.element).subject))" }.joined(separator: "\n")
        return .init(valid: valid, report: "System trust on this device: \(valid ? "Passed" : "Not trusted")\nSAN-only service identity: \(policy == 0 ? (sanMatches ? "Passed" : "Failed") : "Not applicable")\nNetwork fetch: disabled\nFresh revocation: not checked\nSystem store/cache may supply intermediates\nEvaluated: \(CertificateDisplay.date(at))\nOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nError code: \(error.map { CFErrorGetCode($0) } ?? 0)\n\(summary)", chain: chain)
    }
}
