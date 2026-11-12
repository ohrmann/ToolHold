import Foundation
import Testing
@testable import PKICore

@Test func exporterOutcomesAreDistinctAndSanitized() throws {
    let url = URL(fileURLWithPath: "/public-marker")
    #expect(PKIExportOutcome(.success(url)) == .success)
    #expect(PKIExportOutcome(.failure(CancellationError())) == .cancelled)
    let cases: [(Error, PKIExportOutcome)] = [
        (NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError), .cancelled),
        (NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError), .permissionDenied),
        (NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)), .permissionDenied),
        (NSError(domain: "NSFileProviderErrorDomain", code: -1000), .unavailable),
        (NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError), .failed),
        (NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError), .failed)
    ]
    for (error, expected) in cases {
        let raw = error as NSError
        let wrapped = NSError(domain: raw.domain, code: raw.code, userInfo: [NSLocalizedDescriptionKey: "PUBLIC-SENSITIVE-MARKER", NSFilePathErrorKey: "/PUBLIC-SENSITIVE-MARKER"])
        let outcome = PKIExportOutcome(.failure(wrapped))
        #expect(outcome == expected && !outcome.message.contains("PUBLIC-SENSITIVE-MARKER"))
    }
    let nested = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
    #expect(PKIExportOutcome(.failure(nested)) == .permissionDenied)
}

@Test @MainActor func concealmentRetainsResultsCancelsLateExportsAndIsWindowLocal() async throws {
    let workspace = PKIWorkspace(tool: .certificate), otherWindow = PKIWorkspace(tool: .key)
    await workspace.run().value
    guard case .generated(let generated) = workspace.result else { Issue.record("No synthetic result"); return }
    workspace.masked = false; otherWindow.masked = false
    workspace.newPassword = "public-marker"; workspace.confirmPassword = "public-marker"
    workspace.privateExport(key: generated.key.handle, unencrypted: false, pem: true)
    workspace.concealSecrets()
    try await Task.sleep(for: .milliseconds(200))
    #expect(workspace.masked && workspace.newPassword.isEmpty && workspace.confirmPassword.isEmpty)
    #expect(workspace.pendingExport == nil && !workspace.busy && workspace.result != nil && workspace.token != nil)
    #expect(!otherWindow.masked)
    workspace.newPassword = "retry-marker"; workspace.confirmPassword = "retry-marker"
    workspace.privateExport(key: generated.key.handle, unencrypted: false, pem: true)
    for _ in 0..<400 { if !workspace.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
    #expect(workspace.pendingExport != nil && workspace.masked)
    workspace.concealSecrets()
    #expect(workspace.pendingExport == nil && workspace.result != nil)
}

@Test @MainActor func backgroundConcealmentDoesNotDiscardCompletedPFX() async throws {
    let workspace = PKIWorkspace(tool: .pfx); workspace.mode = 1
    workspace.input = String(decoding: try fixture("leaf.pem"), as: UTF8.self)
    workspace.newPassword = "public-marker"; workspace.confirmPassword = "public-marker"
    await workspace.run().value
    guard case .package(let original) = workspace.result else { Issue.record("No synthetic PFX"); return }
    workspace.concealSecrets()
    guard case .package(let retained) = workspace.result else { Issue.record("Completed PFX lost"); return }
    #expect(original == retained && workspace.masked && workspace.newPassword.isEmpty && workspace.confirmPassword.isEmpty)
}

@Test @MainActor func concealmentRunsWindowLocalResponderCommandsBeforeMasking() {
    let workspace = PKIWorkspace(tool:.key), other = PKIWorkspace(tool:.key), id = UUID()
    workspace.masked = false; other.masked = false
    var calledBeforeMask = false, otherCalled = false
    workspace.setConcealAction(id:id) { calledBeforeMask = !workspace.masked }
    other.setConcealAction(id:UUID()) { otherCalled = true }
    workspace.concealSecrets()
    #expect(calledBeforeMask && workspace.masked && !otherCalled && !other.masked)
    workspace.removeConcealAction(id:id); workspace.masked = false; calledBeforeMask = false
    workspace.concealSecrets()
    #expect(!calledBeforeMask && workspace.masked)
}
