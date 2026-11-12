import Foundation
import Testing
import SwiftASN1
@testable import CertificateCore
struct CertificateCoreTests {
    func fixture(_ name: String) throws -> Data { try Data(contentsOf:Bundle.module.resourceURL!.appendingPathComponent("Fixtures/"+name)) }
    @Test func fieldAndFingerprintParityWithOpenSSL() throws {
        let data = try fixture("certificate.der"), r = CertificateProcessor.inspect(data)
        let e = try #require(r.entries.first)
        #expect(e.parsed); #expect(e.subject.contains("OU=One") && e.subject.contains("OU=Two")); #expect(e.subject.contains("example.test"))
        let expected = String(decoding:try fixture("fingerprint.txt"),as:UTF8.self).uppercased()
        #expect(expected.contains(e.sha256)); #expect(expected.contains(e.sha1))
        let spki = try #require(e.spki); #expect(expected.contains(CertificateDisplay.digest(spki).replacingOccurrences(of:":",with:"")))
        #expect(try PublicKeyMaterialImporter.spki(spki).bits == 2048)
        #expect(try PublicKeyMaterialImporter.read(String(decoding:fixture("public.pem"),as:UTF8.self)).spki == spki)
    }
    @Test func knownExtensionsAndUnknownCriticalRemainVisible() throws {
        let e = CertificateDER.inspect(try fixture("certificate.der"))
        #expect(e.extensions.contains { $0.oid == "2.5.29.17" && $0.fields.contains { $0.value == "::1" } })
        #expect(e.extensions.contains { $0.oid == "2.5.29.37" && $0.fields.count == 2 })
        #expect(e.extensions.contains { $0.oid == "2.5.29.15" && $0.fields.contains { $0.value == "Digital signature" } })
        let unknown = try #require(e.extensions.first { $0.oid == "1.2.3.4" })
        #expect(unknown.critical && unknown.issue != nil && !unknown.bytes.isEmpty)
        #expect(e.issues.contains { $0.contains("Critical extension not interpreted") })
    }
    @Test func envelopeExactRangesWhitespaceAndExport() throws {
        let der = try fixture("certificate.der"), pem = PEMEnvelopeReader.encode(der,label:"CERTIFICATE")
        let source = " \r\n"+pem+"\n\t"+pem+"\n"
        let blocks = try PEMEnvelopeReader.read(source,allowed:["CERTIFICATE"],maximumCount:2)
        #expect(blocks.count == 2 && blocks[0].der == der && blocks[1].der == der)
        for b in blocks { #expect((source as NSString).substring(with:b.range) == pem) }
        let r = CertificateProcessor.inspect(Data(source.utf8)); #expect(r.entries.map(\.id) == [0,1])
        #expect(r.entries[1].der == der && r.entries[1].sourceRange == blocks[1].range)
        #expect(try PEMEnvelopeReader.read(r.entries[0].pem,allowed:["CERTIFICATE"])[0].der == der)
    }
    @Test func rejectsJunkLabelsPaddingAndMalformedDER() throws {
        let pem = PEMEnvelopeReader.encode(Data([1,2,3]),label:"CERTIFICATE")
        for source in ["junk"+pem,pem+"junk",pem.replacingOccurrences(of:"END CERTIFICATE",with:"END PUBLIC KEY"),pem.replacingOccurrences(of:"AQID",with:"AR=="),pem.replacingOccurrences(of:"CERTIFICATE",with:"PRIVATE KEY")] {
            #expect(throws:(any Error).self) { try PEMEnvelopeReader.read(source,allowed:["CERTIFICATE"]) }
        }
        for data in [Data([0x30,0]),Data([0x30,0x80,0,0]),Data([0x30,0x84,0xff,0xff,0xff,0xff]),try fixture("certificate.der")+Data([0])] {
            #expect(CertificateDER.inspect(data).parsed == false)
        }
    }
    @Test func bundlePartialAndResourceBoundaries() throws {
        let valid = String(decoding:try fixture("certificate.pem"),as:UTF8.self)
        let bad = PEMEnvelopeReader.encode(Data([0x30,0]),label:"CERTIFICATE")
        let r = CertificateProcessor.inspect(Data((valid+"\n"+bad).utf8))
        #expect(r.entries.count == 2 && r.entries[0].parsed && !r.entries[1].parsed && r.status == .completedWithIssues)
        #expect(CertificateProcessor.inspect(Data(Array(repeating:valid,count:64).joined(separator:"\n").utf8)).entries.count == 64)
        #expect(CertificateProcessor.inspect(Data(Array(repeating:valid,count:65).joined(separator:"\n").utf8)).status == .resourceLimit)
        #expect(CertificateProcessor.inspect(Data(repeating:0,count:CertificateLimits.file+1)).status == .resourceLimit)
        #expect(CertificateProcessor.inspect(Data(repeating:0,count:CertificateLimits.certificate+1)).status == .resourceLimit)
    }
    @Test func validityBoundariesAreNotTrust() throws {
        let e = CertificateDER.inspect(try fixture("certificate.der")), a = try #require(e.notBefore), b = try #require(e.notAfter)
        #expect(e.validity(at:a) == "Within validity period"); #expect(e.validity(at:b) == "Within validity period")
        #expect(e.validity(at:a.addingTimeInterval(-1)) == "Not yet valid"); #expect(e.validity(at:b.addingTimeInterval(1)) == "Expired")
        #expect(!e.fields.contains { $0.value == "Trusted" })
    }
    @Test func unknownAlgorithmStillInspectsAndSafeDisplayPreservesSource() throws {
        var data = try fixture("certificate.der")
        let oid = Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01])
        let range = try #require(data.range(of:oid)); data[range.upperBound-1] = 99
        let e = CertificateDER.inspect(data)
        #expect(e.parsed && e.der == data); #expect(e.fields.contains { $0.name == "Public-key algorithm" && $0.value.contains("99") })
        #expect(CertificateDisplay.safe("a\u{202e}\u{0}😀") == "a\\u{202E}\\u{0000}😀")
    }
    @Test func regularFileLimitsAndCancellation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        let bytes = try fixture("certificate.der"); try bytes.write(to:url)
        #expect(try CertificateFileLoader.read(url) == bytes)
        #expect(throws:(any Error).self) { try CertificateFileLoader.read(url,limit:10) }
        #expect(throws:(any Error).self) { try CertificateFileLoader.read(FileManager.default.temporaryDirectory) }
        let task = Task { () -> CertificateResult in
            do { try await Task.sleep(for:.milliseconds(10)) } catch {}
            return CertificateProcessor.inspect(bytes)
        }; task.cancel(); #expect(await task.value.status == .cancelled)
    }
    @Test @MainActor func sessionPrivacyUIOnlyPreferencesAndClearRace() async throws {
        let name = "test.cert."+UUID().uuidString, defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let session = CertificateWorkspaceSession(defaults:defaults)
        session.input = String(decoding:try fixture("certificate.pem"),as:UTF8.self)
        await session.run().value; #expect(session.selected?.parsed == true)
        session.wordWrap = false; session.showSource(); #expect(session.target != nil)
        let job = session.run(); session.clear(); await job.value
        #expect(session.input.isEmpty && session.result == nil && !session.busy)
        let fresh = CertificateWorkspaceSession(defaults:defaults)
        #expect(fresh.input.isEmpty && fresh.result == nil && fresh.wordWrap == false)
        #expect(Set(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("developerToolbox.certificate") }).isSubset(of:["developerToolbox.certificate.wordWrap","developerToolbox.certificate.localDates","developerToolbox.certificate.inspectOnPaste"]))
    }
}


extension CertificateCoreTests {
    func replacingTBS(_ transform: ([ASN1Node]) throws -> Data) throws -> Data {
        let fields = try CertificateDER.children(DER.parse(Array(fixture("certificate.der"))))
        return PublicKeyDEREncoding.tlv(0x30,try transform(CertificateDER.children(fields[0]))+Data(fields[1].encodedBytes)+Data(fields[2].encodedBytes))
    }
    @Test func time2050HugeSerialAndMalformedKnownExtension() throws {
        let data = try replacingTBS { nodes in
            var encoded = nodes.map { Data($0.encodedBytes) }
            encoded[1] = PublicKeyDEREncoding.integer(Data([0x7f])+Data(repeating:0x99,count:40))
            let start = PublicKeyDEREncoding.tlv(0x18,Data("20500101000000Z".utf8)), end = PublicKeyDEREncoding.tlv(0x18,Data("20500201000000Z".utf8))
            encoded[4] = PublicKeyDEREncoding.tlv(0x30,start+end)
            return PublicKeyDEREncoding.tlv(0x30,encoded.reduce(Data(),+))
        }
        let e = CertificateDER.inspect(data)
        #expect(e.parsed);#expect(e.fields.first { $0.name == "Serial number · hex" }?.value.count == 82)
        #expect(CertificateDisplay.date(try #require(e.notBefore)).hasPrefix("2050-01-01"))
        let ext = CertificateExtensions.decode(id:0,oid:"2.5.29.17",critical:false,bytes:Data([4,1,0]))
        #expect(ext.issue?.contains("Malformed extension") == true && ext.bytes == Data([4,1,0]))
        let futureUsage = CertificateExtensions.decode(id:0,oid:"2.5.29.15",critical:true,bytes:Data([3,3,0,0,1]))
        #expect(futureUsage.issue?.contains("unknown bits") == true)
    }
    @Test func duplicateExtensionsAndAlgorithmMismatchAreIssues() throws {
        let data = try replacingTBS { nodes in
            var encoded = nodes.map { Data($0.encodedBytes) }
            encoded[2] = PublicKeyDEREncoding.tlv(0x30,Data([6,3,0x2a,3,4]))
            let wrapper = nodes.last!, list = try CertificateDER.children(wrapper,tag:wrapper.identifier)[0]
            let ext = try CertificateDER.children(list)
            let bytes = ext.map {Data($0.encodedBytes)}.reduce(Data(),+) + Data(ext[0].encodedBytes)
            encoded[encoded.count-1] = PublicKeyDEREncoding.tlv(0xa3,PublicKeyDEREncoding.tlv(0x30,bytes))
            return PublicKeyDEREncoding.tlv(0x30,encoded.reduce(Data(),+))
        }
        let e = CertificateDER.inspect(data)
        #expect(e.parsed && e.issues.contains {$0.contains("Duplicate extension")} && e.issues.contains {$0.contains("signature algorithm identifiers differ")})
    }
    @Test @MainActor func importPreferenceAndBinarySourceSnapshot() async throws {
        let name = "test.cert.import."+UUID().uuidString, defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let session = CertificateWorkspaceSession(defaults:defaults);session.inspectOnPaste = false
        let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/certificate.der")
        await session.importFile(url).value
        let expected = try fixture("certificate.der")
        #expect(session.result == nil && session.fileSource == expected)
        await session.run().value;#expect(session.selected?.parsed == true)
        session.usePEM();#expect(session.fileSource == nil && session.input.hasPrefix("-----BEGIN CERTIFICATE"))
        let obsolete = session.run();session.editInput();await obsolete.value
        #expect(session.result == nil && session.fileSource == nil)
    }
}
