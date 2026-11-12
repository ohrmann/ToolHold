import UIKit
import SwiftUI
@testable import Developer_Toolbox

@main final class TextToolsUIKitProbe:UIResponder,UIApplicationDelegate {
 var window:UIWindow?
 func application(_ app:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool{setbuf(stdout,nil);return true}
 func application(_ app:UIApplication,configurationForConnecting session:UISceneSession,options:UIScene.ConnectionOptions)->UISceneConfiguration{let c=UISceneConfiguration(name:"Default",sessionRole:session.role);c.delegateClass=TextToolsProbeScene.self;return c}
 func connect(_ scene:UIWindowScene){window=UIWindow(windowScene:scene);window?.makeKeyAndVisible();Task{@MainActor in do{try await run();print("TEXT_UIKIT_PASSED");exit(0)}catch{print("TEXT_UIKIT_FAILED \(error)");exit(1)}}}
 enum Failure:Error{case check(String)}
 func check(_ value:@autoclosure()->Bool,_ name:String)throws{guard value()else{throw Failure.check(name)};print("TEXT_UIKIT_OK \(name)")}
 func all<T:UIView>(_ type:T.Type,_ view:UIView)->[T]{((view as? T).map{[$0]} ?? [])+view.subviews.flatMap{all(type,$0)}}
 func settle(_ ms:Int=200)async{try? await Task.sleep(for:.milliseconds(ms));window?.layoutIfNeeded()}
 func run()async throws{
  let suite="text.uikit."+UUID().uuidString,d=UserDefaults(suiteName:suite)!;defer{d.removePersistentDomain(forName:suite)}
  let w=TextWorkspace(id:"regex",options:RegexWorkspaceOptions(),automatic:true,defaults:d){s,_,o,c,a in TextRegexProcessor.artifact(try TextRegexProcessor.run(s,pattern:o.pattern,options:o.regex,automatic:a,cancellation:c))}
  w.options.pattern="one"
  let host=UIHostingController(rootView:AnyView(TextRegexView(workspace:w)));window?.rootViewController=host;await settle(500)
  guard let input=all(UITextView.self,host.view).first(where:{$0.accessibilityLabel=="Input input"})else{throw Failure.check("input mounted")}
  let clipboard=UIPasteboard.general.items;defer{UIPasteboard.general.items=clipboard}
  UIPasteboard.general.string="one 😀 one";input.becomeFirstResponder();input.paste(nil)
  for _ in 0..<80{if w.artifact?.regex?.matches.count==2{break};await settle(30)}
  print("TEXT_UIKIT_PASTE_STATE sourceUnits=\(w.input.utf16.count) editorUnits=\(input.text.utf16.count) busy=\(w.busy) matches=\(w.artifact?.regex?.matches.count ?? -1)")
  try check(w.artifact?.regex?.matches.count==2,"native-paste-matches")
  let id=ObjectIdentifier(input),text=input.text,selection=input.selectedRange
  host.overrideUserInterfaceStyle = .dark;await settle()
  try check(all(UITextView.self,host.view).contains{ObjectIdentifier($0)==id},"theme-editor-identity")
  try check(input.text==text && input.selectedRange==selection,"theme-preserves-input-selection")
  input.undoManager?.undo();await settle(50);try check(w.input.isEmpty,"native-undo")
  input.undoManager?.redo();await settle(50);try check(w.input==text,"native-redo")
  input.resignFirstResponder();w.collapsed=true;await settle(350);w.collapsed=false;await settle(350)
  try check(all(UITextView.self,host.view).contains{ObjectIdentifier($0)==id},"collapse-editor-identity")
  let views:[AnyView]=[
   AnyView(TextDiffView(workspace:TextWorkspaces.diff())),AnyView(TextListView(workspace:TextWorkspaces.lists())),
   AnyView(TextCaseView(workspace:TextWorkspaces.casing())),AnyView(TextSortView(workspace:TextWorkspaces.sort())),
   AnyView(TextUnicodeView(workspace:TextWorkspaces.unicode())),AnyView(LoremGeneratorView(workspace:TextWorkspaces.lorem())),
   AnyView(MockDataView(workspace:TextWorkspaces.mock())),AnyView(TextStatisticsView(workspace:TextWorkspaces.statistics())),
   AnyView(TextRegexView(workspace:TextWorkspaces.regex(replace:true),replacement:true))]
  for(i,v) in views.enumerated(){host.rootView=v;await settle();try check(host.view.bounds.width>0,"tool-mount-\(i)")}
 }
}

@MainActor final class TextToolsProbeScene:UIResponder,UIWindowSceneDelegate{
 func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions){if let w=scene as? UIWindowScene{(UIApplication.shared.delegate as? TextToolsUIKitProbe)?.connect(w)}}
}
