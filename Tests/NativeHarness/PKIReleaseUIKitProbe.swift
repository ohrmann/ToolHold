// Synthetic inputs only; runs on Simulator or an explicitly provisioned physical test harness.
import UIKit
import SwiftUI
import Observation
@testable import Developer_Toolbox

@MainActor @Observable final class PKIReleaseUIKitPhase { var value = ScenePhase.active }
struct PKIReleaseUIKitRoot: View {
    var workspace: PKIWorkspace
    var phase: PKIReleaseUIKitPhase
    var body: some View { PKIWorkspaceView(workspace:workspace).environment(\.scenePhase,phase.value) }
}
@main @MainActor final class PKIReleaseUIKitProbe: UIResponder, UIApplicationDelegate, UIWindowSceneDelegate {
    var window: UIWindow?
    func application(_ application:UIApplication,configurationForConnecting session:UISceneSession,options:UIScene.ConnectionOptions)->UISceneConfiguration {
        let configuration = UISceneConfiguration(name:"Public security probe",sessionRole:session.role)
        configuration.delegateClass = PKIReleaseUIKitProbe.self
        return configuration
    }
    func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let phase = PKIReleaseUIKitPhase(), workspace = PKIWorkspace(tool:.key)
        workspace.input = "PUBLIC-NONSECRET-DEVICE-MARKER"; workspace.masked = false
        let window = UIWindow(windowScene:scene)
        window.rootViewController = UIHostingController(rootView:PKIReleaseUIKitRoot(workspace:workspace,phase:phase)); self.window = window
        window.makeKeyAndVisible()
        Task { @MainActor in
            do { try await run(workspace,phase:phase,window:window); print("DEVICE_SECURITY_PROBE_PASSED"); exit(0) }
            catch { print("DEVICE_SECURITY_PROBE_FAILED \(error)"); exit(1) }
        }
    }
    enum Failure: Error { case check(String) }
    func check(_ ok: Bool,_ label: String) throws { guard ok else { throw Failure.check(label) }; print("PASS "+label) }
    func views<T:UIView>(_ type:T.Type,_ root:UIView)->[T] { ((root as? T).map { [$0] } ?? []) + root.subviews.flatMap { views(type,$0) } }
    func hidden(_ view:UIView)->Bool { view.isHidden || view.alpha == 0 || (view.superview.map(hidden) ?? false) }
    func pause() async { try? await Task.sleep(for:.milliseconds(350)) }
    func run(_ workspace:PKIWorkspace,phase:PKIReleaseUIKitPhase,window:UIWindow) async throws {
        await pause()
        guard let editor = views(UITextView.self,window).first(where: { $0.text == "PUBLIC-NONSECRET-DEVICE-MARKER" }) else { throw Failure.check("marker mounted") }
        _ = editor.becomeFirstResponder(); await pause()
        try check(editor.isFirstResponder,"focused native editor")
        try check(!hidden(editor) && editor.isAccessibilityElement,"native UIKit marker visible/accessibility")
        phase.value = .inactive; await pause(); try check(!workspace.masked && !hidden(editor),"inactive preserves reveal")
        phase.value = .background; await pause(); try check(workspace.masked && hidden(editor) && !editor.isAccessibilityElement,"background conceals native UIKit and accessibility")
        phase.value = .active; await pause(); try check(workspace.masked && hidden(editor),"foreground does not reveal")
        workspace.masked = false; await pause(); try check(!hidden(editor) && editor.superview != nil,"explicit reveal reattaches same native editor")
        workspace.concealSecrets(); await pause()
        let generator = PKIEngine(), inspector = PKIEngine()
        for algorithm in [PKIAlgorithm.p256,.ed25519,.rsa2048] {
            var draft = PKIGenerationDraft(); draft.algorithm = algorithm
            let generated = try await generator.generate(draft,csr:false)
            for plain in [false,true] {
                let key = try await generator.exportKey(token:await generator.token(),key:generated.key.handle,password:"public-\u{00e9}",unencrypted:plain)
                for bytes in [key.data,Data(key.pem.utf8)] {
                    let restored = try await inspector.inspectKey(bytes,password:plain ? "" : "public-\u{00e9}")
                    try check(restored.consistent && restored.spki == generated.key.spki,"device DER/PEM readback "+algorithm.rawValue)
                    try check(try await inspector.match(certificate:generated.object.data,certificateIndex:0,privateKey:bytes,password:plain ? "" : "public-\u{00e9}").0,"device possession proof "+algorithm.rawValue)
                }
            }
            try check(try await inspector.inspectKey(generated.key.spki,password:"").spki == generated.key.spki,"device SPKI "+algorithm.rawValue)
        }
        let wrapper = PKIExportDocument(Data("PUBLIC-WRAPPER".utf8)).makeFileWrapper()
        try check(wrapper.fileAttributes[FileAttributeKey.type.rawValue] != nil,"device FileWrapper type retained")
        let protection = wrapper.fileAttributes[FileAttributeKey.protectionKey.rawValue]
        try check((protection as? FileProtectionType) == .complete || (protection as? String) == FileProtectionType.complete.rawValue,"device wrapper requests complete file protection")
    }
}
