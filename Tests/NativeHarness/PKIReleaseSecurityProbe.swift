// Public markers only. No key source is ever revealed or captured by this harness.
import AppKit
import SwiftUI
import Observation
import Darwin
@testable import Developer_Toolbox

@MainActor @Observable final class PKIReleasePhase { var value = ScenePhase.active }
struct PKIReleaseRoot: View {
    var workspace: PKIWorkspace
    var phase: PKIReleasePhase
    var body: some View { PKIWorkspaceView(workspace:workspace).environment(\.scenePhase,phase.value) }
}
@main struct PKIReleaseSecurityProbe: App {
    enum Failure: Error { case check(String) }
    @MainActor static func check(_ ok: Bool,_ label: String) throws {
        guard ok else { throw Failure.check(label) }; print("PASS " + label)
    }
    @MainActor static func pause(_ ms: Int = 250) async { try? await Task.sleep(for:.milliseconds(ms)) }
    @MainActor static func views<T:NSView>(_ type:T.Type,_ root:NSView)->[T] { ((root as? T).map { [$0] } ?? []) + root.subviews.flatMap { views(type,$0) } }
    var body: some Scene {
        WindowGroup {
            Text("Public-marker security probe").frame(width:300,height:100).task { @MainActor in
                setbuf(stdout,nil)
                do { try await Self.run(); print("SECURITY_PROBE_PASSED"); exit(0) }
                catch { print("SECURITY_PROBE_FAILED \(error)"); exit(1) }
            }
        }
    }
    @MainActor static func run() async throws {
        NSApp.accessibilitySetValue(true,forAttribute:NSAccessibility.Attribute(rawValue:"AXEnhancedUserInterface"))
        let phase = PKIReleasePhase(), workspace = PKIWorkspace(tool:.key)
        workspace.input = "PUBLIC-NONSECRET-LIFECYCLE-MARKER"; workspace.masked = false
        let host = NSHostingView(rootView:PKIReleaseRoot(workspace:workspace,phase:phase))
        let window = NSWindow(contentRect:.init(x:40,y:40,width:1000,height:800),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate()
        await pause(600)
        guard let editor = views(NSTextView.self,host).first(where: { $0.string == "PUBLIC-NONSECRET-LIFECYCLE-MARKER" }) else { throw Failure.check("marker editor mounted") }
        try check(!editor.isHiddenOrHasHiddenAncestor && editor.isAccessibilityElement(),"revealed native view and accessibility")
        phase.value = .inactive; await pause()
        try check(!workspace.masked && !editor.isHiddenOrHasHiddenAncestor,"inactive preserves reveal")
        phase.value = .background; await pause()
        try check(workspace.masked && editor.isHiddenOrHasHiddenAncestor && !editor.isAccessibilityElement(),"background conceals native view and accessibility")
        phase.value = .active; await pause()
        try check(workspace.masked && editor.isHiddenOrHasHiddenAncestor,"foreground does not reveal")
        workspace.masked = false; await pause()
        try check(!editor.isHiddenOrHasHiddenAncestor,"explicit reveal restores marker")
        NotificationCenter.default.post(name:NSApplication.didResignActiveNotification,object:NSApp); await pause()
        try check(workspace.masked && editor.isHiddenOrHasHiddenAncestor,"macOS application deactivation conceals")
        let wrapper = PKIExportDocument(Data("PUBLIC-WRAPPER".utf8)).makeFileWrapper()
        try check(wrapper.fileAttributes[FileAttributeKey.type.rawValue] != nil,"FileWrapper keeps required type")
        let folder = PKIDirectoryDocument(files:["marker":Data("PUBLIC".utf8)]).makeFileWrapper()
        try check(folder.fileAttributes[FileAttributeKey.type.rawValue] != nil,"directory wrapper keeps required type")
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("dt-public-native-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:local) }
        try PKISecureLocalExport.coordinatedWrite(Data("PUBLIC-SANDBOX-EXPORT".utf8),to:local)
        try check(try Data(contentsOf:local) == Data("PUBLIC-SANDBOX-EXPORT".utf8),"actual sandbox local writer readback")
        if CommandLine.arguments.contains("--system-save") {
            // Native system picker, public payload; sandbox Powerbox grants tested by actual OK.
            let directory = URL(fileURLWithPath:"/private/tmp/dt-final-remediation/mac-system-save",isDirectory:true)
            let panel = NSSavePanel(); panel.directoryURL = directory; panel.nameFieldStringValue = "public-marker.pem"
            var finished = false, outcome = "BLOCKED"
            panel.beginSheetModal(for:window) { response in
                defer { finished = true }
                guard response == .OK, let url = panel.url else { outcome = "CANCELLED"; return }
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do { try PKISecureLocalExport.write(Data("PUBLIC-SYSTEM-SAVE".utf8),to:url); outcome = "PASS" }
                catch { outcome = "FAIL-" + String(describing:PKIExportOutcome(.failure(error))) }
            }
            await pause(1200); panel.ok(nil)
            for _ in 0..<60 { if finished { break }; await pause(100) }
            if !finished { panel.cancel(nil) }
            print("SYSTEM_SAVE_" + outcome)
            try check(outcome == "PASS","actual native Save with sandbox and selected local path")
        }
        window.close()
    }
}
