import AppKit
import SwiftUI
import CryptoKit
@testable import Developer_Toolbox

@main struct CertificatePasswordJWTNativeProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        setbuf(stdout,nil); NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await run(); print("T030_032_NATIVE_PASSED") } catch { print("T030_032_NATIVE_FAILED \(error)"); exit(1) }
            exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func all<T: NSView>(_ type:T.Type,_ view:NSView) -> [T] { ((view as? T).map {[$0]} ?? [])+view.subviews.flatMap {all(type,$0)} }
    @MainActor static func check(_ condition:@autoclosure () -> Bool,_ name:String) throws { guard condition() else {throw Failure.check(name)}; print("T030_032_NATIVE_OK \(name)") }
    @MainActor static func settle(_ host:NSView,_ ms:Int = 150) async { try? await Task.sleep(for:.milliseconds(ms));host.layoutSubtreeIfNeeded();host.displayIfNeeded() }
    @MainActor static func run() async throws {
        let name = "test.native.security."+UUID().uuidString, defaults = UserDefaults(suiteName:name)!
        defer {defaults.removePersistentDomain(forName:name)}
        let host = NSHostingView(rootView:AnyView(EmptyView()))
        let window = NSWindow(contentRect:.init(x:50,y:50,width:1250,height:850),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.contentView = host;window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        let reduced = CommandLine.arguments.contains("--reduce-motion")
        let cert = CertificateWorkspaceSession(defaults:defaults)
        host.rootView = AnyView(CertificateInspectorView(workspace:cert));await settle(host)
        guard let editor = all(NSTextView.self,host).first(where:{$0.accessibilityLabel() == "Certificate PEM input"}) else {throw Failure.check("certificate-editor")}
        let editorID = ObjectIdentifier(editor)
        window.makeFirstResponder(editor)
        let pem = try String(contentsOf:Bundle.main.url(forResource:"certificate",withExtension:"pem")!,encoding:.utf8)
        editor.insertText(pem,replacementRange:.init(location:0,length:editor.string.utf16.count))
        await cert.run().value;await settle(host)
        try check(cert.selected?.parsed == true,"certificate-native-edit-inspect")
        editor.undoManager?.undo();await settle(host);try check(cert.input.isEmpty && cert.result == nil,"certificate-undo-invalidates-result")
        editor.undoManager?.redo();await settle(host);await cert.run().value
        let preserved = cert.input
        window.appearance = NSAppearance(named:.darkAqua);window.setContentSize(.init(width:420,height:850));await settle(host)
        try check(ObjectIdentifier(all(NSTextView.self,host).first(where:{$0.accessibilityLabel() == "Certificate PEM input"})!) == editorID,"certificate-editor-retained-at-breakpoint")
        try check(cert.input == preserved,"certificate-theme-layout-preserves-input")
        cert.showSource();await settle(host);try check(cert.target != nil,"certificate-source-navigation")
        window.setContentSize(.init(width:1250,height:850));window.makeFirstResponder(nil);await settle(host)
        let initialWidth = editor.enclosingScrollView!.frame.width
        withAnimation(reduced ? nil : .easeInOut(duration:0.2)) {cert.inputCollapsed = true}
        var widths: [CGFloat] = []
        for _ in 0..<14 {await settle(host,20);widths.append(editor.enclosingScrollView!.frame.width)}
        print("T030_NATIVE_COLLAPSE widths=\(widths) reduced=\(reduced)")
        try check(reduced || widths.contains {$0 > 2 && $0 < initialWidth-2},"collapse-has-intermediate-layout")
        withAnimation(reduced ? nil : .easeInOut(duration:0.2)) {cert.inputCollapsed = false};await settle(host,300)
        try check(cert.input == preserved,"collapse-expand-preserves-input")
        let export = CertificateExportDocument(cert.selected!.der)
        try check(export.bytes == cert.selected!.der,"certificate-export-frozen-bytes")
        let strength = PasswordStrengthWorkspaceSession(defaults:defaults);strength.autoEstimate = false
        window.setContentSize(.init(width:950,height:850));host.rootView = AnyView(PasswordStrengthView(workspace:strength));await settle(host)
        strength.password = "password";await strength.estimate().value;await settle(host)
        try check(strength.result?.score == 0,"actual-jsc-in-native-workspace")
        let secure = all(NSSecureTextField.self,host);try check(!secure.isEmpty,"native-secure-input")
        strength.revealed = true;await settle(host);try check(strength.password == "password" && strength.result?.score == 0,"reveal-does-not-clear")
        window.appearance = NSAppearance(named:.aqua);window.setContentSize(.init(width:390,height:850));await settle(host)
        try check(strength.password == "password","password-theme-layout-preserves-input")
        strength.clear();await settle(host);try check(strength.password.isEmpty && strength.result == nil,"password-clear")
        let verify = JWTVerifierWorkspaceSession(defaults:defaults)
        host.rootView = AnyView(JWTVerifierView(workspace:verify));window.setContentSize(.init(width:1250,height:850));await settle(host)
        let secret = String(repeating:"synthetic-key-",count:4), h = JWTSigningProvider.base64URL(Data(#"{"alg":"HS256"}"#.utf8)), p = JWTSigningProvider.base64URL(Data(#"{"exp":9999999999}"#.utf8))
        let message = h+"."+p
        let token = message+"."+JWTSigningProvider.base64URL(Data(HMAC<SHA256>.authenticationCode(for:Data(message.utf8),using:SymmetricKey(data:Data(secret.utf8)))))
        verify.token = token;verify.key = secret;verify.format = .secretUTF8;verify.algorithm = .hs256
        await verify.run().value;await settle(host);try check(verify.result?.signature == .matches && verify.result?.claimsPassed == true,"native-jwt-verification")
        let tokenEditor = try require(all(NSTextView.self,host).first(where:{$0.accessibilityLabel() == "JWT Verifier token input"}),"token-editor")
        let identity = ObjectIdentifier(tokenEditor)
        window.setContentSize(.init(width:420,height:850));window.appearance = NSAppearance(named:.darkAqua);await settle(host)
        try check(ObjectIdentifier(all(NSTextView.self,host).first(where:{$0.accessibilityLabel() == "JWT Verifier token input"})!) == identity,"jwt-editor-identity-stable")
        try check(verify.token == token && verify.result?.signature == .matches,"jwt-theme-layout-preserves-verdict")
        verify.token += "x";await settle(host);try check(verify.result == nil,"jwt-input-invalidates-verdict")
        verify.clear();try check(verify.key.isEmpty && verify.algorithm == nil,"jwt-clear")
        try check(CertificateWorkspaceSession(defaults:defaults).input.isEmpty && PasswordStrengthWorkspaceSession(defaults:defaults).password.isEmpty && JWTVerifierWorkspaceSession(defaults:defaults).token.isEmpty,"fresh-sessions-empty")
    }
    static func require<T>(_ value:T?,_ name:String) throws -> T {guard let value else {throw Failure.check(name)};return value}
}
