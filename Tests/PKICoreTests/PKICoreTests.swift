import Foundation
import Testing
import CertificateCore
@testable import PKICore

@Test func backendCanInitialize() async throws { let e = PKIEngine(); #expect(await e.version().contains("4.0.3")) }
@Test func generatedCertificateKeyCSRAndPFX() async throws {
    for alg in [PKIAlgorithm.p256, .p384, .p521, .ed25519, .rsa2048, .rsa3072, .rsa4096] {
        let engine = PKIEngine(); var draft = PKIGenerationDraft(); draft.algorithm = alg
        let result = try await engine.generate(draft, csr: false), token = await engine.token()
        #expect(result.key.consistent); #expect(CertificateDER.inspect(result.object.data).parsed)
        let encrypted = try await engine.exportKey(token: token, key: result.key.handle, password: "synthetic-pass", unencrypted: false)
        let inspector = PKIEngine(), info = try await inspector.inspectKey(Data(encrypted.pem.utf8), password: "synthetic-pass")
        #expect(info.spki == result.key.spki)
        let matcher = PKIEngine(), match = try await matcher.match(certificate: result.object.data, certificateIndex: 0, privateKey: Data(encrypted.pem.utf8), password: "synthetic-pass")
        #expect(match.0)
        await #expect(throws: Error.self) { try await matcher.match(certificate: result.object.data, certificateIndex: 0, privateKey: Data(info.publicPEM.utf8), password: "") }
        let pfx = PKIEngine(), bytes = try await pfx.createPFX(privateKey: Data(encrypted.pem.utf8), certificate: result.object.data, extras: Data(), password: "new-password", keyPassword: "synthetic-pass", name: "Synthetic")
        let inventory = try await pfx.openPFX(bytes, password: "new-password", legacy: false, unverified: false)
        #expect(inventory.verified && inventory.rewritable); #expect(inventory.bags.count == 2)
        let rewrapped = try await pfx.repackagePFX(token: await pfx.token(), password: "changed-password")
        let check = PKIEngine(); #expect(try await check.openPFX(rewrapped, password: "changed-password", legacy: false, unverified: false).bags.count == 2)
        let csr = try await engine.generate(draft, csr: true)
        #expect(try await inspector.inspectCSR(csr.object.data).signatureValid)
    }
}
@Test func conversionPreservesBytesAndEncryptedEnvelope() async throws {
    let engine = PKIEngine(), generated = try await engine.generate(PKIGenerationDraft(), csr: false)
    let encrypted = try await engine.exportKey(token: await engine.token(), key: generated.key.handle, password: "fixture", unencrypted: false)
    let converter = PKIEngine(), items = try await converter.convert(Data((generated.object.pem + "\n" + encrypted.pem).utf8))
    #expect(items.count == 2); #expect(items[0].data == generated.object.data); #expect(items[1].data == encrypted.data)
}
