import Foundation
import Security
import Testing
@testable import PKICore

@MainActor private func waitForExport(_ workspace: PKIWorkspace) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while workspace.busy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    #expect(!workspace.busy)
}

@Test @MainActor func protectedKeyConfirmationRequiresExactBytesAndRoundTrips() async throws {
    let workspace = PKIWorkspace(tool: .certificate)
    await workspace.run().value
    guard case .generated(let generated) = workspace.result else { Issue.record("Missing synthetic certificate"); return }
    let composed = "synthetic-\u{00E9}-pass", decomposed = "synthetic-e\u{0301}-pass"
    // Never include password/key values in assertion diagnostics.
    for (first, second) in [(composed, decomposed), (decomposed, composed), ("first", "second")] {
        workspace.newPassword = first; workspace.confirmPassword = second
        let matches = workspace.exportPasswordsMatch
        #expect(!matches)
        workspace.privateExport(key: generated.key.handle, unencrypted: false, pem: true)
        #expect(workspace.status == .invalidInput && workspace.pendingExport == nil && !workspace.busy)
    }
    for (password, pem) in [(composed, true), (decomposed, false)] {
        workspace.newPassword = password; workspace.confirmPassword = password
        #expect(workspace.exportPasswordsMatch)
        workspace.privateExport(key: generated.key.handle, unencrypted: false, pem: pem)
        try await waitForExport(workspace)
        let artifact = try #require(workspace.pendingExport)
        #expect(artifact.sensitive)
        let inspector = PKIEngine(), restored = try await inspector.inspectKey(artifact.bytes, password: password)
        #expect(restored.spki == generated.key.spki && restored.consistent)
        let other = pem ? decomposed : composed
        await #expect(throws: Error.self) { try await inspector.inspectKey(artifact.bytes, password: other) }
    }
    workspace.privateExport(key: generated.key.handle, unencrypted: false, pem: true)
    workspace.cancel()
    try await Task.sleep(for: .milliseconds(100))
    #expect(workspace.pendingExport == nil && workspace.result != nil)
}

@Test @MainActor func csrAndImportedKeyExportsUseExactConfirmation() async throws {
    for tool in [PKITool.csr, .key] {
        let workspace = PKIWorkspace(tool: tool)
        if tool == .key { workspace.input = String(decoding: try fixture("leaf-key.pem"), as: UTF8.self) }
        await workspace.run().value
        let handle: Int32
        switch workspace.result {
        case .generated(let value): handle = value.key.handle
        case .key(let value): handle = value.handle
        default: Issue.record("Missing synthetic private key"); return
        }
        workspace.newPassword = "synthetic-\u{00E9}"
        workspace.confirmPassword = "synthetic-e\u{0301}"
        workspace.privateExport(key: handle, unencrypted: false, pem: true)
        #expect(workspace.status == .invalidInput && workspace.pendingExport == nil)
        workspace.confirmPassword = workspace.newPassword
        workspace.privateExport(key: handle, unencrypted: false, pem: true)
        try await waitForExport(workspace)
        #expect(workspace.pendingExport != nil)
    }
}

@Test @MainActor func pfxCreateSubsetAndPasswordChangeRejectByteDistinctConfirmation() async throws {
    let create = PKIWorkspace(tool: .pfx); create.mode = 1
    create.input = String(decoding: try fixture("leaf.pem"), as: UTF8.self)
    create.second = String(decoding: try fixture("leaf-key.pem"), as: UTF8.self)
    create.newPassword = "synthetic-\u{00E9}"; create.confirmPassword = "synthetic-e\u{0301}"
    await create.run().value
    #expect(create.status == .invalidInput && create.message == "Export passwords do not match" && create.result == nil)
    let check = PKIEngine()
    let passwords = ["synthetic-ascii", "synthetic-\u{00E9}", "synthetic-e\u{0301}"]
    for password in passwords {
        create.newPassword = password; create.confirmPassword = password
        await create.run().value
        guard case .package(let bytes) = create.result else { Issue.record("Missing synthetic PFX"); return }
        #expect(try await check.openPFX(bytes, password: password, legacy: false, unverified: false).verified)
        // The app's shipping targets support this API. Earlier package deployment
        // targets still run confirmation checks; never fall back to Keychain import.
        if #available(macOS 15.0, iOS 18.0, *) {
            var identities: CFArray?
            let appleReadback = SecPKCS12Import(bytes as CFData,[kSecImportExportPassphrase:password,kSecImportToMemoryOnly:true] as CFDictionary,&identities) == errSecSuccess
            #expect(appleReadback)
        }
        let wrong = password.utf8.elementsEqual(passwords[1].utf8) ? passwords[2] : passwords[1]
        await #expect(throws: Error.self) { try await check.openPFX(bytes, password: wrong, legacy: false, unverified: false) }
    }

    let inspect = PKIWorkspace(tool: .pfx)
    try inspect.load(try fixture("multiple.p12"), name: "public-test.p12", slot: 0)
    inspect.password = "fixture"; await inspect.run().value
    #expect(inspect.result != nil)
    for subset in [false, true] {
        inspect.newPassword = "synthetic-\u{00E9}"; inspect.confirmPassword = "synthetic-e\u{0301}"
        inspect.repackage(subset: subset)
        #expect(inspect.status == .invalidInput && inspect.message == "Export passwords do not match" && inspect.pendingExport == nil)
        for password in passwords {
            inspect.newPassword = password; inspect.confirmPassword = password
            inspect.repackage(subset: subset); try await waitForExport(inspect)
            let artifact = try #require(inspect.pendingExport)
            #expect(try await check.openPFX(artifact.bytes, password: password, legacy: false, unverified: false).verified)
            if #available(macOS 15.0, iOS 18.0, *) {
                var identities: CFArray?
                let appleReadback = SecPKCS12Import(artifact.bytes as CFData,[kSecImportExportPassphrase:password,kSecImportToMemoryOnly:true] as CFDictionary,&identities) == errSecSuccess
                #expect(appleReadback)
            }
            let wrong = password.utf8.elementsEqual(passwords[1].utf8) ? passwords[2] : passwords[1]
            await #expect(throws: Error.self) { try await check.openPFX(artifact.bytes, password: wrong, legacy: false, unverified: false) }
        }
    }
}
