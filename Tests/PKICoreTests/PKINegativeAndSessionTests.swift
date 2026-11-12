import Foundation
import Testing
import Security
import CertificateCore
@testable import PKICore

func fixture(_ name: String) throws -> Data { try Data(contentsOf: #require(Bundle.module.url(forResource:name,withExtension:nil,subdirectory:"Fixtures"))) }

@Test func providedChainPoliciesAndIndependentFixture() async throws {
    let e = PKIEngine(), leaf = try fixture("leaf.pem"), intermediate = try fixture("intermediate.pem"), root = try fixture("root.pem")
    let cert = try #require(CertificateProcessor.inspect(leaf).entries.first), now = try #require(cert.notBefore).addingTimeInterval(60)
    let valid = try await e.validateChain(leaf:leaf,intermediates:intermediate,roots:root,policy:0,host:"localhost",at:now,system:false)
    #expect(valid.valid && valid.chain.count == 3); #expect(valid.report.contains("PUBLIC TEST")); #expect(valid.report.contains("Revocation: not checked"))
    #expect(try await e.validateChain(leaf:leaf,intermediates:intermediate,roots:root,policy:0,host:"127.0.0.1",at:now,system:false).valid)
    #expect(try await !e.validateChain(leaf:leaf,intermediates:intermediate,roots:root,policy:0,host:"wrong.example",at:now,system:false).valid)
    #expect(try await !e.validateChain(leaf:leaf,intermediates:Data(),roots:root,policy:2,host:"",at:now,system:false).valid)
    #expect(try await !e.validateChain(leaf:leaf,intermediates:intermediate,roots:root,policy:1,host:"",at:now,system:false).valid)
    #expect(try await !e.validateChain(leaf:leaf,intermediates:intermediate,roots:root,policy:2,host:"",at:now.addingTimeInterval(400*86400),system:false).valid)
    await #expect(throws:Error.self) { try await e.validateChain(leaf:leaf,intermediates:intermediate,roots:Data(),policy:2,host:"",at:now,system:false) }
    await #expect(throws:Error.self) { try await e.validateChain(leaf:leaf,intermediates:Data(),roots:intermediate,policy:2,host:"",at:now,system:false) }
    let system = try await e.validateChain(leaf:leaf,intermediates:intermediate,roots:Data(),policy:0,host:"localhost",at:now,system:true)
    #expect(!system.valid); #expect(system.report.contains("Network fetch: disabled"))
}
@Test func importedKeyPossessionAndCSRSignatureTamper() async throws {
    let engine = PKIEngine(), leaf = try fixture("leaf.pem")
    #expect(try await engine.match(certificate:leaf,certificateIndex:0,privateKey:fixture("leaf-key.pem"),password:"").0)
    #expect(try await !engine.match(certificate:leaf,certificateIndex:0,privateKey:fixture("root-key.pem"),password:"").0)
    let csr = try await engine.inspectCSR(fixture("leaf.csr")); #expect(csr.signatureValid)
    var tampered = csr.object.data; tampered[tampered.count-1] ^= 1
    #expect(try await !engine.inspectCSR(tampered).signatureValid)
    var draft = PKIGenerationDraft(); draft.useImportedKey = true; draft.importedKey = String(decoding:try fixture("leaf-key.pem"),as:UTF8.self)
    let generated = try await engine.generate(draft,csr:false)
    #expect(try await engine.match(certificate:generated.object.data,certificateIndex:0,privateKey:fixture("leaf-key.pem"),password:"").0)
}
@Test func malformedEnvelopesLimitsAndPasswords() async throws {
    let e = PKIEngine(), cert = try #require(CertificateProcessor.inspect(fixture("leaf.pem")).entries.first)
    for invalid in [Data(),Data([0x30,0x84,0xff,0xff,0xff,0xff]),cert.der + Data([0]),Data("-----BEGIN PRIVATE KEY-----\nAAAA\n-----END CERTIFICATE-----".utf8)] {
        await #expect(throws:Error.self) { try await e.convert(invalid) }
    }
    await #expect(throws:Error.self) { try await e.convert(cert.der,hint:"PUBLIC KEY") }
    let g = try await e.generate(PKIGenerationDraft(),csr:false), token = await e.token()
    for password in ["","abc\0def",String(repeating:"x",count:1025)] { await #expect(throws:Error.self) { try await e.exportKey(token:token,key:g.key.handle,password:password,unencrypted:false) } }
    let key = try await e.exportKey(token:token,key:g.key.handle,password:"  pass e\u{301}  ",unencrypted:false)
    let inspector = PKIEngine()
    #expect(try await inspector.inspectKey(Data(key.pem.utf8),password:"  pass e\u{301}  ").consistent)
    do { _ = try await inspector.inspectKey(Data(key.pem.utf8),password:"pass é"); Issue.record("Wrong exact password accepted") } catch let failure as PKIFailure { #expect(failure.status == .needsPassword) }
    await e.clear()
    await #expect(throws:Error.self) { try await e.exportKey(token:token,key:g.key.handle,password:"pass",unencrypted:false) }
}
@Test func legacyEmptyPasswordAndPFXIntegrity() async throws {
    let e = PKIEngine(), legacy = try fixture("legacy.p12")
    await #expect(throws:Error.self) { try await e.openPFX(legacy,password:"fixture",legacy:false,unverified:false) }
    let imported = try await e.openPFX(legacy,password:"fixture",legacy:true,unverified:false)
    #expect(imported.verified && imported.bags.count == 3)
    let subset = try await e.subsetPFX(token:await e.token(),key:try #require(imported.bags.first(where: { $0.key >= 0 })).key,leaf:try #require(imported.bags.first(where: { $0.certificate >= 0 })).certificate,extras:[],name:"Fixture",password:"modern")
    #expect(try await e.openPFX(subset,password:"modern",legacy:false,unverified:false).bags.count == 2)
    #expect(try await e.openPFX(fixture("empty-password.p12"),password:"",legacy:true,unverified:false).verified)
    var damaged = legacy; damaged[damaged.count-1] ^= 1
    await #expect(throws:Error.self) { try await e.openPFX(damaged,password:"fixture",legacy:true,unverified:false) }
    await #expect(throws:Error.self) { try await e.openPFX(legacy,password:"incorrect",legacy:true,unverified:false) }
    await #expect(throws:Error.self) { try await e.createPFX(privateKey:fixture("leaf-key.pem"),certificate:fixture("leaf.pem"),extras:Data(),password:"emoji🔑",keyPassword:"",name:"fixture") }
}
@Test func profilesTypedSANAndAppleCertificateConsumer() async throws {
    let e = PKIEngine()
    for profile in PKIProfile.allCases {
        var draft = PKIGenerationDraft(); draft.profile = profile; draft.commonName = "PUBLIC TEST Ω"; draft.sans.append(.init(kind:.dns,value:"bücher.example"))
        let g = try await e.generate(draft,csr:false), cert = CertificateDER.inspect(g.object.data)
        #expect(cert.parsed); #expect(cert.extensions.contains { $0.oid == "2.5.29.19" && $0.critical })
        let apple = try #require(SecCertificateCreateWithData(nil,g.object.data as CFData))
        #expect(SecCertificateCopyData(apple) as Data == g.object.data); #expect(SecCertificateCopyKey(apple) != nil)
        if profile == .server { #expect(try await e.validateChain(leaf:g.object.data,intermediates:Data(),roots:g.object.data,policy:0,host:"localhost",at:.now,system:false).valid) }
    }
    for value in ["bad..example","foo.*.example","127.0.0.1","x\0.example","*.com"] {
        var d = PKIGenerationDraft(); d.sans = [.init(kind:.dns,value:value)]; await #expect(throws:Error.self) { try await e.generate(d,csr:false) }
    }
}
@Test @MainActor func workspaceRevisionCancellationExportAndPrivacy() async throws {
    let s = PKIWorkspace(tool:.certificate)
    let first = s.run(); s.draft.commonName = "different"; await first.value
    #expect(s.result == nil && !s.busy)
    await s.run().value
    guard case .generated = s.result else { Issue.record("Generation missing"); return }
    let unchanged = s.draft; s.draft = unchanged; #expect(s.result != nil)
    s.masked = false; s.concealSecrets(); #expect(s.masked && s.newPassword.isEmpty)
    #expect(s.result != nil)
    s.clear(); #expect(s.result == nil && s.token == nil && s.password.isEmpty)
    await s.run().value; #expect(s.result != nil && s.token != nil)
    let fresh = PKIWorkspace(tool:.matcher); #expect(fresh.input.isEmpty && fresh.second.isEmpty && fresh.result == nil)
    let k = PKIWorkspace(tool:.key); k.input = String(decoding:try fixture("leaf-key.pem"),as:UTF8.self)
    let running = k.run(); k.cancel(); await running.value; #expect(k.result == nil && k.status == .cancelled)
}
@Test func batchExpiryBundleDuplicatesSymlinksAndReports() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:folder) }
    let pem = try fixture("leaf.pem"), cert = try #require(CertificateProcessor.inspect(pem).entries.first)
    try (pem + pem).write(to:folder.appendingPathComponent("=bundle.pem")); try Data("not a cert".utf8).write(to:folder.appendingPathComponent("invalid.txt"))
    try FileManager.default.createSymbolicLink(atPath:folder.appendingPathComponent("link.pem").path,withDestinationPath:folder.appendingPathComponent("=bundle.pem").path)
    let report = await Task.detached { PKIExpirationScanner.scan([folder],at:cert.notAfter!.addingTimeInterval(-86400),threshold:30) }.value
    #expect(report.files == 2 && report.rows.count == 4)
    let certs = report.rows.filter { $0.issue == nil }; #expect(certs.count == 2 && certs[0].sha256 == certs[1].sha256)
    #expect(certs[0].state(at:report.evaluatedAt,threshold:30) == "Expiring soon")
    #expect(certs[0].state(at:cert.notAfter!,threshold:30) == "Expiring soon")
    #expect(certs[0].state(at:cert.notAfter!.addingTimeInterval(1),threshold:30) == "Expired")
    #expect(String(decoding:report.csv(),as:UTF8.self).contains("'=bundle.pem"))
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(PKIExpirationReport.self,from:report.json()).rows.count == report.rows.count)
    #expect(!PKIExpirationScanner.scan(Array(repeating:folder,count:1001)).complete)
    let task = Task.detached { PKIExpirationScanner.scan(Array(repeating:folder,count:1000)) }; task.cancel(); #expect(await !task.value.complete)
}

@Test func appleMemoryOnlyPFXInteroperability() async throws {
    guard #available(macOS 15,iOS 18,*) else { return }
    let e = PKIEngine()
    let data = try await e.createPFX(privateKey:fixture("leaf-key.pem"),certificate:fixture("leaf.pem"),extras:fixture("intermediate.pem"),password:"fixture",keyPassword:"",name:"Public synthetic fixture")
    var items: CFArray?
    let status = SecPKCS12Import(data as CFData,[kSecImportExportPassphrase:"fixture",kSecImportToMemoryOnly:true] as CFDictionary,&items)
    #expect(status == errSecSuccess)
    #expect((items as? [[String:Any]])?.first?[kSecImportItemIdentity as String] != nil)
}

@Test func multiIdentityLosslessRewriteAndUnverifiedGuards() async throws {
    let e = PKIEngine(), input = try fixture("multiple.p12")
    let original = try await e.openPFX(input,password:"fixture",legacy:false,unverified:false)
    #expect(original.bags.count == 4 && original.rewritable)
    #expect(original.bags.filter { $0.key >= 0 }.allSatisfy { $0.matchingCertificates.count == 1 })
    let changed = try await e.repackagePFX(token:await e.token(),password:"new fixture")
    let roundtrip = try await e.openPFX(changed,password:"new fixture",legacy:false,unverified:false)
    #expect(roundtrip.bags.map(\.certificateDER) == original.bags.map(\.certificateDER))
    #expect(roundtrip.bags.map(\.summary) == original.bags.map(\.summary))
    for name in ["unknown-attribute.p12","duplicate-attribute.p12"] {
        let info = try await e.openPFX(fixture(name),password:"fixture",legacy:false,unverified:false)
        #expect(info.verified && !info.rewritable && info.bags.count == 4)
        await #expect(throws:Error.self) { try await e.repackagePFX(token:await e.token(),password:"changed") }
    }
    let unverified = try fixture("no-mac.p12")
    await #expect(throws:Error.self) { try await e.openPFX(unverified,password:"fixture",legacy:false,unverified:false) }
    let info = try await e.openPFX(unverified,password:"fixture",legacy:false,unverified:true)
    #expect(!info.verified && !info.rewritable)
    await #expect(throws:Error.self) { try await e.exportKey(token:await e.token(),key:0,password:"x",unencrypted:false) }
    do { _ = try await e.openPFX(fixture("excessive-kdf.p12"),password:"fixture",legacy:false,unverified:false); Issue.record("KDF limit bypass") }
    catch let error as PKIFailure { #expect(error.status == .resourceLimit) }
}
@Test func truncatedAndMutatedASN1NeverPublishesArtifacts() async throws {
    let e = PKIEngine(), source = try fixture("multiple.p12")
    for length in [0,1,2,5,32,source.count/2,source.count-1] { await #expect(throws:Error.self) { try await e.openPFX(source.prefix(length),password:"fixture",legacy:false,unverified:false) } }
    for offset in [0,1,10,32,source.count-1] { var bytes = source; bytes[offset] ^= 255; await #expect(throws:Error.self) { try await e.openPFX(bytes,password:"fixture",legacy:false,unverified:false) } }
    let malformed = Data([0x30,0x11,0x30,0x0d,0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x05,0x0d,0x30,0x00,0x04,0x00])
    await #expect(throws:Error.self) { try await e.inspectKey(malformed,password:"fixture") }
}

@Test func restrictedPSSParametersAreRespected() async throws {
    let e = PKIEngine(), key = try fixture("pss-key.pem")
    let der = try #require(try await e.convert(key).first?.data)
    let info = try await e.inspectKey(key,password:"")
    #expect(info.algorithm == "RSA-PSS" && info.publicDetails.contains("384"))
    let token = await e.token(), inspector = PKIEngine()
    for plain in [false,true] {
        let exported = try await e.exportKey(token:token,key:info.handle,password:"public-pss-marker",unencrypted:plain)
        for bytes in [exported.data,Data(exported.pem.utf8)] {
            let restored = try await inspector.inspectKey(bytes,password:plain ? "" : "public-pss-marker")
            #expect(restored.algorithm == "RSA-PSS" && restored.spki == info.spki && restored.consistent)
            #expect(try await inspector.match(certificate:fixture("pss-cert.pem"),certificateIndex:0,privateKey:bytes,password:plain ? "" : "public-pss-marker").0)
        }
    }
    for bytes in [key,der] {
        #expect(try await inspector.match(certificate:fixture("pss-cert.pem"),certificateIndex:0,privateKey:bytes,password:"").0)
    }
    for bytes in [info.spki,Data(info.publicPEM.utf8)] {
        let restored = try await inspector.inspectKey(bytes,password:"")
        #expect(restored.algorithm == "RSA-PSS" && !restored.isPrivate && restored.spki == info.spki)
    }
}

@Test func strictChainCriticalSANWeakSignaturePathLengthAndConstraints() async throws {
    let e = PKIEngine(), root = try fixture("root.pem"), intermediate = try fixture("intermediate.pem"), leaf = try fixture("leaf.pem")
    for name in ["cn-only.pem","critical.pem","sha1.pem"] {
        let result = try await e.validateChain(leaf:fixture(name),intermediates:Data(),roots:root,policy:0,host:"localhost",at:.now,system:false)
        #expect(!result.valid,"Unexpected trust for \(name)")
    }
    for anchor in ["pathlen-zero.pem","name-constraints.pem"] {
        #expect(try await !e.validateChain(leaf:leaf,intermediates:intermediate,roots:fixture(anchor),policy:0,host:"localhost",at:.now,system:false).valid)
    }
    await #expect(throws:Error.self) { try await e.validateChain(leaf:leaf,intermediates:intermediate,roots:root,policy:0,host:"localhost",at:Date(timeIntervalSince1970:.infinity),system:false) }
}
