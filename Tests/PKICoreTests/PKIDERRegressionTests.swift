import Foundation
import Testing
import CertificateCore
@testable import PKICore

@Test func exportedKeysAreAcceptedAcrossToolsAndEnvelopes() async throws {
    for algorithm in PKIAlgorithm.allCases {
        let generator = PKIEngine(); var draft = PKIGenerationDraft(); draft.algorithm = algorithm
        let generated = try await generator.generate(draft, csr: false)
        let token = await generator.token(), inspector = PKIEngine(), converter = PKIEngine()
        for plain in [false, true] {
            let key = try await generator.exportKey(token: token, key: generated.key.handle, password: "public-test-password", unencrypted: plain)
            for bytes in [key.data, Data(key.pem.utf8)] {
                let info = try await inspector.inspectKey(bytes, password: plain ? "" : "public-test-password")
                #expect(info.consistent && info.isPrivate && info.spki == generated.key.spki)
                let objects = try await converter.convert(bytes)
                #expect(objects.count == 1 && objects[0].label == key.label && objects[0].data == key.data)
                let matcher = PKIEngine()
                #expect(try await matcher.match(certificate: generated.object.data, certificateIndex: 0, privateKey: bytes, password: plain ? "" : "public-test-password").0)
                let packager = PKIEngine()
                let pfx = try await packager.createPFX(privateKey: bytes, certificate: generated.object.data, extras: Data(), password: "public-container-password", keyPassword: plain ? "" : "public-test-password", name: "Synthetic")
                #expect(try await packager.openPFX(pfx, password: "public-container-password", legacy: false, unverified: false).verified)
            }
        }
        for bytes in [generated.key.spki, Data(generated.key.publicPEM.utf8)] {
            let info = try await inspector.inspectKey(bytes, password: "")
            #expect(!info.isPrivate && info.consistent && info.spki == generated.key.spki)
            #expect(try await converter.convert(bytes).first?.label == "PUBLIC KEY")
            await #expect(throws: Error.self) { try await inspector.match(certificate: generated.object.data, certificateIndex: 0, privateKey: bytes, password: "") }
        }
        let other = try await inspector.generate(draft, csr: false)
        let otherKey = try await inspector.exportKey(token: await inspector.token(), key: other.key.handle, password: "", unencrypted: true)
        #expect(try await converter.match(certificate: generated.object.data, certificateIndex: 0, privateKey: otherKey.data, password: "").0 == false)
    }
}

@Test func keySchemasRejectWrongLabelsAndMalformedDER() async throws {
    let engine = PKIEngine(), generated = try await engine.generate(PKIGenerationDraft(), csr: false)
    let key = try await engine.exportKey(token: await engine.token(), key: generated.key.handle, password: "", unencrypted: true)
    let converter = PKIEngine()
    for label in ["EC PRIVATE KEY", "RSA PRIVATE KEY", "RSA PUBLIC KEY"] {
        await #expect(throws: Error.self) { try await converter.convert(Data(PEMEnvelopeReader.encode(key.data, label: label).utf8)) }
        await #expect(throws: Error.self) { try await converter.convert(key.data, hint: label) }
        await #expect(throws: Error.self) { try await converter.convert(generated.key.spki, hint: label) }
    }
    for bytes in [key.data, generated.key.spki] {
        for length in [0, 1, 2, 5, bytes.count / 2, bytes.count - 1] {
            await #expect(throws: Error.self) { try await converter.inspectKey(bytes.prefix(length), password: "") }
        }
        await #expect(throws: Error.self) { try await converter.inspectKey(bytes + Data([0]), password: "") }
    }
    for bytes in [Data([0x30,0x80,0,0]), Data([0x30,0x84,0xff,0xff,0xff,0xff]), Data([0x30,3,2,1,0])] {
        await #expect(throws: Error.self) { try await converter.inspectKey(bytes, password: "") }
    }
}

@Test func legacyKeyEnvelopesRemainStrictAndInteroperate() async throws {
    for (name, label) in [("legacy-rsa-private.der", "RSA PRIVATE KEY"), ("legacy-rsa-public.der", "RSA PUBLIC KEY"), ("legacy-prime256v1.der", "EC PRIVATE KEY"), ("legacy-secp384r1.der", "EC PRIVATE KEY"), ("legacy-secp521r1.der", "EC PRIVATE KEY")] {
        let bytes = try fixture(name), pem = PEMEnvelopeReader.encode(bytes, label: label)
        let engine = PKIEngine(), converter = PKIEngine()
        let baseline = try await engine.inspectKey(bytes, password: "")
        for input in [bytes, Data(pem.utf8)] {
            let info = try await engine.inspectKey(input, password: "")
            #expect(info.consistent && info.spki == baseline.spki)
            #expect(try await converter.convert(input).first?.label == label)
            if info.isPrivate {
                let exported = try await engine.exportKey(token: await engine.token(), key: info.handle, password: "public-marker", unencrypted: false)
                #expect(try await converter.inspectKey(exported.data, password: "public-marker").spki == info.spki)
                var draft = PKIGenerationDraft(); draft.useImportedKey = true; draft.importedKey = pem
                let certificate = try await engine.generate(draft, csr: false)
                #expect(try await converter.match(certificate: certificate.object.data, certificateIndex: 0, privateKey: input, password: "").0)
            }
        }
        let wrong = label == "EC PRIVATE KEY" ? "RSA PRIVATE KEY" : "EC PRIVATE KEY"
        await #expect(throws: Error.self) { try await converter.convert(bytes, hint: wrong) }
        await #expect(throws: Error.self) { try await converter.inspectKey(bytes + Data([0]), password: "") }
        await #expect(throws: Error.self) { try await converter.inspectKey(bytes.dropLast(), password: "") }
    }
}
