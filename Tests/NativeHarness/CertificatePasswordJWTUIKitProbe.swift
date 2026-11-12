import UIKit
import SwiftUI
@testable import Developer_Toolbox

@main @MainActor final class CertificatePasswordJWTUIKitProbe: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let suite = "test.uikit.security."+UUID().uuidString
    func application(_ application: UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]? = nil) -> Bool { setbuf(stdout,nil); return true }
    func application(_ application:UIApplication,configurationForConnecting session:UISceneSession,options:UIScene.ConnectionOptions) -> UISceneConfiguration { let c = UISceneConfiguration(name:"Default",sessionRole:session.role);c.delegateClass = SecurityToolsProbeScene.self;return c }
    func connect(_ scene:UIWindowScene) {
        window = UIWindow(windowScene:scene); window?.makeKeyAndVisible()
        Task { @MainActor in do { try await run();print("T030_032_UIKIT_PASSED");exit(0) } catch {print("T030_032_UIKIT_FAILED \(error)");exit(1)} }
    }
    enum Failure:Error {case check(String)}
    func check(_ value:@autoclosure () -> Bool,_ name:String) throws {guard value() else {throw Failure.check(name)};print("T030_032_UIKIT_OK \(name)")}
    func all<T:UIView>(_ type:T.Type,_ view:UIView) -> [T] { ((view as? T).map {[$0]} ?? [])+view.subviews.flatMap {all(type,$0)} }
    func settle(_ ms:Int = 150) async {try? await Task.sleep(for:.milliseconds(ms));window?.layoutIfNeeded()}
    struct Vector:Decodable {let alg:String, token:String, key:String;var publicKey:String?}
    func run() async throws {
        let defaults = UserDefaults(suiteName:suite)!;defer {defaults.removePersistentDomain(forName:suite)}
        let cert = CertificateWorkspaceSession(defaults:defaults)
        let host = UIHostingController(rootView:AnyView(CertificateInspectorView(workspace:cert)))
        window?.rootViewController = host;await settle(300)
        guard let input = all(UITextView.self,host.view).first(where:{$0.accessibilityLabel == "Certificate PEM input"}) else {throw Failure.check("certificate-editor")}
        let identity = ObjectIdentifier(input)
        let pem = try String(contentsOf:Bundle.main.url(forResource:"certificate",withExtension:"pem")!,encoding:.utf8)
        let previousPasteboard = UIPasteboard.general.items;defer {UIPasteboard.general.items = previousPasteboard}
        UIPasteboard.general.string = pem;input.becomeFirstResponder();input.paste(nil)
        for _ in 0..<30 {if cert.result != nil {break};await settle(50)}
        try check(cert.selected?.parsed == true,"native-paste-inspects-certificate")
        input.undoManager?.undo();await settle();try check(cert.input.isEmpty && cert.result == nil,"certificate-undo-invalidates")
        input.undoManager?.redo();await settle();await cert.run().value;input.resignFirstResponder()
        host.overrideUserInterfaceStyle = .dark;await settle()
        try check(ObjectIdentifier(all(UITextView.self,host.view).first(where:{$0.accessibilityLabel == "Certificate PEM input"})!) == identity,"theme-retains-native-input")
        cert.showSource();await settle();try check(cert.target != nil,"source-anchor")
        let strength = PasswordStrengthWorkspaceSession(defaults:defaults);strength.autoEstimate = false
        host.rootView = AnyView(PasswordStrengthView(workspace:strength));await settle()
        let fields = all(UITextField.self,host.view);try check(fields.contains {$0.isSecureTextEntry},"native-secure-field")
        guard let field = fields.first(where:{$0.isSecureTextEntry}) else {throw Failure.check("secure-field")}
        field.becomeFirstResponder();UIPasteboard.general.string = "password";field.paste(nil);await strength.estimate().value;await settle()
        try check(strength.password == "password" && strength.result?.score == 0,"password-paste-real-jsc")
        let kept = strength.password;UIPasteboard.general.string = "bad\nline";field.paste(nil);await settle()
        try check(strength.password == kept && strength.rejection != nil,"newline-paste-rejected-before-mutation")
        field.undoManager?.undo();await settle();try check(strength.password.isEmpty,"password-native-undo")
        field.undoManager?.redo();await settle();try check(strength.password == kept,"password-native-redo")
        field.resignFirstResponder();strength.revealed = true;await settle();try check(strength.password == kept,"reveal-preserves-password")
        strength.clear();await settle();try check(strength.result == nil && strength.password.isEmpty,"password-clear")
        let verify = JWTVerifierWorkspaceSession(defaults:defaults)
        let vectors = try JSONDecoder().decode([Vector].self,from:Data(contentsOf:Bundle.main.url(forResource:"vectors",withExtension:"json")!))
        for vector in vectors {
            let r = await Task.detached {JWTVerifierProcessor.process(.init(token:vector.token,key:vector.publicKey ?? vector.key,algorithm:.init(rawValue:vector.alg),format:vector.publicKey == nil ? .secretUTF8 : .publicPEM))}.value
            try check(r.signature == .matches,"crypto-"+vector.alg)
        }
        host.rootView = AnyView(JWTVerifierView(workspace:verify));await settle()
        let v = vectors[0];verify.token = v.token;verify.key = v.key;verify.algorithm = .hs256;verify.format = .secretUTF8
        await verify.run().value;await settle();try check(verify.result?.signature == .matches,"jwt-native-workspace")
        guard let tokenInput = all(UITextView.self,host.view).first(where:{$0.accessibilityLabel == "JWT Verifier token input"}) else {throw Failure.check("token-input")}
        let tokenIdentity = ObjectIdentifier(tokenInput);host.overrideUserInterfaceStyle = .light;await settle()
        try check(ObjectIdentifier(all(UITextView.self,host.view).first(where:{$0.accessibilityLabel == "JWT Verifier token input"})!) == tokenIdentity,"jwt-theme-editor-identity")
        verify.token += "x";await settle();try check(verify.result == nil,"jwt-stale-verdict-invalidated")
        verify.clear();try check(verify.token.isEmpty && verify.key.isEmpty && verify.algorithm == nil,"jwt-clear")
        try check(CertificateWorkspaceSession(defaults:defaults).input.isEmpty && PasswordStrengthWorkspaceSession(defaults:defaults).password.isEmpty && JWTVerifierWorkspaceSession(defaults:defaults).key.isEmpty,"new-session-empty")
    }
}
@MainActor final class SecurityToolsProbeScene: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions) {if let windowScene = scene as? UIWindowScene {(UIApplication.shared.delegate as? CertificatePasswordJWTUIKitProbe)?.connect(windowScene)}}
}
