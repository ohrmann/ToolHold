import AppKit
import SwiftUI
@testable import Developer_Toolbox

@main struct TextToolsNativeProbe {
 enum Failure:Error{case check(String)}
 @MainActor static func main(){setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.regular);Task{@MainActor in do{try await run();print("TEXT_NATIVE_PASSED")}catch{print("TEXT_NATIVE_FAILED \(error)");exit(1)};exit(0)};NSApplication.shared.run()}
 @MainActor static func check(_ value:@autoclosure()->Bool,_ name:String)throws{guard value()else{throw Failure.check(name)};print("TEXT_NATIVE_OK \(name)")}
 @MainActor static func all<T:NSView>(_ type:T.Type,_ view:NSView)->[T]{((view as? T).map{[$0]} ?? [])+view.subviews.flatMap{all(type,$0)}}
 @MainActor static func settle(_ host:NSView,_ ms:Int=150)async{try? await Task.sleep(for:.milliseconds(ms));host.layoutSubtreeIfNeeded();host.displayIfNeeded()}
 @MainActor static func done<O>(_ w:TextWorkspace<O>)async throws{for _ in 0..<200{if !w.busy{return};try await Task.sleep(for:.milliseconds(25))};throw Failure.check("worker did not finish")}
 @MainActor static func run()async throws{
  let suite="text.native."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
  let host=NSHostingView(rootView:AnyView(EmptyView()))
  let window=NSWindow(contentRect:.init(x:30,y:30,width:1250,height:850),styleMask:[.titled,.resizable,.closable],backing:.buffered,defer:false)
  window.isReleasedWhenClosed=false;window.contentView=host;window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
  let regex=TextWorkspace(id:"regex",options:RegexWorkspaceOptions(),defaults:defaults){s,_,o,c,a in TextRegexProcessor.artifact(try TextRegexProcessor.run(s,pattern:o.pattern,options:o.regex,automatic:a,cancellation:c))}
  host.rootView=AnyView(TextRegexView(workspace:regex));await settle(host,400)
  let input=try require(all(JSONNativeTextView.self,host).first{$0.accessibilityLabel()=="Input input"},"regex editor")
  window.makeFirstResponder(input);input.insertText(String(repeating:"line\n",count:500)+"one 😀 two one",replacementRange:.init(location:0,length:0));regex.options.pattern="one";regex.run();try await done(regex);await settle(host)
  try check(regex.artifact?.regex?.matches.count==2,"native-input-regex")
  let identity=ObjectIdentifier(input),selection=input.selectedRange(),text=input.string
  for width in [420.0,1100.0]{window.setContentSize(.init(width:width,height:850));window.appearance=NSAppearance(named:width<500 ? .darkAqua:.aqua);await settle(host);try check(all(JSONNativeTextView.self,host).contains{ObjectIdentifier($0)==identity},"editor-identity-resize-theme");try check(input.string==text && input.selectedRange()==selection,"selection-source-preserved")}
  input.enclosingScrollView?.contentView.scroll(to:.zero);await settle(host)
  regex.selection=1;regex.navigate(regex.artifact?.regex?.matches.last?.range)
  var offsets:[CGFloat]=[];for _ in 0..<16{await settle(host,20);offsets.append(input.enclosingScrollView!.contentView.bounds.minY)}
  print("TEXT_NATIVE_SCROLL \(offsets)")
  try check((offsets.last ?? 0)>0 && offsets.contains{$0>0 && $0<(offsets.last ?? 0)},"offscreen-scroll-intermediate-frames")
  try check(input.string==text,"match-navigation-no-edit")
  input.undoManager?.undo();await settle(host);try check(regex.input.isEmpty && regex.artifact==nil,"undo-invalidates");input.undoManager?.redo();await settle(host);try check(regex.input==text,"redo-preserves")
  window.makeFirstResponder(nil);let width=input.enclosingScrollView!.frame.width
  let reduced=CommandLine.arguments.contains("--reduce-motion") || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  var transaction=Transaction();transaction.disablesAnimations=reduced
  withTransaction(transaction){regex.collapsed=true};var frames:[CGFloat]=[];for _ in 0..<14{await settle(host,20);frames.append(input.enclosingScrollView!.frame.width)}
  print("TEXT_NATIVE_COLLAPSE \(frames)");try check(reduced || frames.contains{$0>17 && $0<width-2},"collapse-intermediate-frames")
  regex.collapsed=false;await settle(host,350);try check(input.string==text,"collapse-expand-source")
  let cases:[(String,AnyView)] = [
   ("diff",AnyView(TextDiffView(workspace:TextWorkspaces.diff()))),
   ("lists",AnyView(TextListView(workspace:TextWorkspaces.lists()))),
   ("case",AnyView(TextCaseView(workspace:TextWorkspaces.casing()))),
   ("sort",AnyView(TextSortView(workspace:TextWorkspaces.sort()))),
   ("unicode",AnyView(TextUnicodeView(workspace:TextWorkspaces.unicode()))),
   ("lorem",AnyView(LoremGeneratorView(workspace:TextWorkspaces.lorem()))),
   ("mock",AnyView(MockDataView(workspace:TextWorkspaces.mock()))),
   ("statistics",AnyView(TextStatisticsView(workspace:TextWorkspaces.statistics()))),
   ("replace",AnyView(TextRegexView(workspace:TextWorkspaces.regex(replace:true),replacement:true)))]
  for(name,view) in cases{host.rootView=view;for width in [1250.0,390.0]{window.setContentSize(.init(width:width,height:850));await settle(host,120);try check(host.fittingSize.height.isFinite,"\(name)-layout-\(Int(width))")}}
  let large=TextWorkspace(id:"unicode-stress",options:UnicodeWorkspaceOptions(),defaults:defaults){s,_,o,_,_ in try TextUnicodeInspector.inspect(s,filter:o.filter,normalization:o.normalization)}
  large.input=String(repeating:"a",count:262144);large.run();try await done(large)
  window.setContentSize(.init(width:1250,height:850));let start=ContinuousClock.now
  host.rootView=AnyView(TextUnicodeView(workspace:large));await settle(host,500)
  try check(large.artifact?.rows.count==262144,"unicode-maximum-continuous-rows")
  if let table=all(NSTableView.self,host).first{table.scrollRowToVisible(max(0,table.numberOfRows-1));await settle(host,200);print("TEXT_NATIVE_TABLE total=\(table.numberOfRows) visible=\(table.rows(in:table.visibleRect))")}
  var usage=rusage();getrusage(RUSAGE_SELF,&usage)
  print("TEXT_NATIVE_LARGE_UI rows=262144 mount_and_scroll=\(start.duration(to:.now)) peak_bytes=\(usage.ru_maxrss)")
  let before="a\nunchanged\nlast",after="b\nunchanged\nlast\n"
  let diff=TextWorkspaces.diff();diff.input=before;diff.second=after;diff.run();try await done(diff)
  host.rootView=AnyView(TextDiffView(workspace:diff));window.setContentSize(.init(width:1250,height:850));await settle(host,300)
  try check(all(JSONNativeTextView.self,host).filter{$0.isEditable}.count==2,"diff-two-native-inputs")
  diff.navigate(.init(location:0,length:1),.init(location:0,length:1));await settle(host,300)
  try check(diff.input==before && diff.second==after,"diff-show-both-preserves-source")
  if let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:rep);try rep.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/text-tools-macos.png"))}
  window.contentView=nil
 }
 static func require<T>(_ value:T?,_ message:String)throws->T{guard let value else{throw Failure.check(message)};return value}
}
