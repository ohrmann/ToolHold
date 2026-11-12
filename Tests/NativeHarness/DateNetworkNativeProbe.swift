import AppKit
import SwiftUI

@testable import Developer_Toolbox

@main struct DateNetworkNativeProbe {
  enum Failure: Error { case check(String) }
  @MainActor static func main() {
    setbuf(stdout, nil)
    NSApplication.shared.setActivationPolicy(.regular)
    Task { @MainActor in
      do {
        if CommandLine.arguments.contains("--benchmark-only") {
          try await benchmark()
        } else {
          try await run()
        }
        print("DATE_NATIVE_PASSED")
      } catch {
        print("DATE_NATIVE_FAILED \(error)")
        exit(1)
      }
      exit(0)
    }
    NSApplication.shared.run()
  }
  @MainActor static func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
    guard value() else { throw Failure.check(name) }
    print("DATE_NATIVE_OK \(name)")
  }
  @MainActor static func all<T: NSView>(_ type: T.Type, _ view: NSView) -> [T] {
    ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, $0) }
  }
  @MainActor static func settle(_ host: NSView, _ ms: Int = 180) async {
    try? await Task.sleep(for: .milliseconds(ms))
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
  }
  @MainActor static func done<R>(_ w: CalculationWorkspace<R>) async throws {
    for _ in 0..<200 {
      if !w.busy { return }
      try await Task.sleep(for: .milliseconds(15))
    }
    throw Failure.check("timeout")
  }
  @MainActor static func benchmark() async throws {
    var running = true
    var ticks = 0
    let heartbeat = Task { @MainActor in
      while running {
        ticks += 1
        try? await Task.sleep(for: .milliseconds(10))
      }
    }
    let lines = try await Task.detached(priority: .userInitiated) {
      var lines: [String] = []
      func measure(_ label: String, _ action: () throws -> String) rethrows {
        let begin = ContinuousClock.now
        let result = try action()
        lines.append("DATE_STRESS \(label) \(begin.duration(to:.now)) \(result)")
      }
      try measure("4096_base36_digits") {
        var r = NumberCalculationRequest()
        r.input = String(repeating: "Z", count: 4096)
        r.radix = 36
        let result = try NumberCalculation.process(r)
        return "binary_chars=\(result.rows.first{$0.id == "base2"}!.value.count)"
      }
      try measure("IPv6_zero_prefix") {
        let result = try IPNetwork("::/0").report()
        return "rows=\(result.rows.count)"
      }
      let reference = try DateTextParser.parse("2026-01-01T00:00:00Z").instant()!
      let zone = try ToolTimeZone("Europe/Prague")
      try measure("cron_dense_100") {
        let r = try CronEngine.next(
          CronExpression("* * * * * *", dialect: .seconds), after: reference, zone: zone, count: 100
        )
        return "count=\(r.instants.count) complete=\(r.complete)"
      }
      try measure("cron_impossible_8_years") {
        let r = try CronEngine.next(CronExpression("0 0 31 FEB *"), after: reference, zone: zone)
        return "count=\(r.instants.count) complete=\(r.complete)"
      }
      try measure("full_mime") { "rows=\(try NetworkReferences.mimeSearch("").rows.count)" }
      try measure("mime_filtered") { "rows=\(try NetworkReferences.mimeSearch("json").rows.count)" }
      return lines
    }.value
    running = false
    heartbeat.cancel()
    for line in lines { print(line) }
    print("DATE_STRESS main_heartbeat_ticks=\(ticks)")
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    print("DATE_STRESS peak_bytes=\(usage.ru_maxrss)")
  }
  @MainActor static func run() async throws {
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    let window = NSWindow(
      contentRect: .init(x: 30, y: 30, width: 1200, height: 850),
      styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    let w = DateNetworkWorkspaces.date(.unix)
    w.request.unit = .seconds
    host.rootView = AnyView(DateToolsView(workspace: w))
    await settle(host, 350)
    guard
      let field = all(NSTextField.self, host).first(where: {
        $0.placeholderString == "e.g. 0 or -0.000001"
      })
    else { throw Failure.check("epoch field") }
    window.makeFirstResponder(field)
    guard let editor = field.currentEditor() as? NSTextView else {
      throw Failure.check("field editor")
    }
    editor.insertText("1.5", replacementRange: .init(location: 0, length: 0))
    await settle(host, 400)
    try await done(w)
    try check(
      w.report?.rows.contains { $0.id == "unit3" && $0.value == "1500" } == true,
      "native-input-auto-calculation")
    let id = ObjectIdentifier(field)
    let selection = editor.selectedRange()
    for width in [390.0, 1200.0] {
      window.setContentSize(.init(width: width, height: 850))
      window.appearance = NSAppearance(named: width < 500 ? .darkAqua : .aqua)
      await settle(host)
      try check(
        all(NSTextField.self, host).contains { ObjectIdentifier($0) == id },
        "field-identity-resize-theme")
      try check(
        field.stringValue == "1.5" && editor.selectedRange() == selection, "caret-input-preserved")
    }
    editor.undoManager?.undo()
    await settle(host, 300)
    try check(w.request.input.isEmpty, "native-undo")
    editor.undoManager?.redo()
    await settle(host, 300)
    try check(w.request.input == "1.5", "native-redo")
    let revision = w.revision
    editor.setMarkedText(
      "2", selectedRange: .init(location: 1, length: 0),
      replacementRange: .init(location: 0, length: editor.string.utf16.count))
    await settle(host, 350)
    try check(w.revision == revision, "ime-does-not-calculate-marked-text")
    editor.insertText("2", replacementRange: editor.markedRange())
    await settle(host, 350)
    try check(w.request.input == "2", "ime-commit")
    window.makeFirstResponder(nil)
    for tool in DateTool.allCases {
      let s = DateNetworkWorkspaces.date(tool)
      s.automatic = false
      if tool == .unix {
        s.request.input = "-1"
        s.request.unit = .microseconds
      } else if tool == .cron {
        s.request.input = "30 2 * * *"
        s.request.zone = "Europe/Prague"
        s.request.secondInput = "2026-10-24T23:00:00Z"
        s.request.findOccurrences = true
      } else {
        s.request.input = "2026-10-25T00:30:00Z"
      }
      s.run()
      try await done(s)
      try check(s.report != nil, "date-\(tool.rawValue)-calculation")
      host.rootView = AnyView(DateToolsView(workspace: s))
      await settle(host)
    }
    for tool in [NetworkTool.cidr, .http, .mime, .chmod] {
      let s = DateNetworkWorkspaces.network(tool)
      s.automatic = false
      s.request.input =
        tool == .cidr ? "::/0" : tool == .http ? "404" : tool == .mime ? "file.json" : "4755"
      s.run()
      try await done(s)
      try check(s.report?.rows.isEmpty == false, "network-\(tool.rawValue)-calculation")
      host.rootView = AnyView(NetworkToolsView(workspace: s))
      for width in [390.0, 1200.0] {
        window.setContentSize(.init(width: width, height: 850))
        await settle(host)
      }
    }
    let number = DateNetworkWorkspaces.number()
    number.automatic = false
    number.request.input = String(repeating: "Z", count: 4096)
    number.request.radix = 36
    let start = ContinuousClock.now
    number.run()
    try await done(number)
    print("DATE_BENCH base36_4096_to_bases \(start.duration(to:.now))")
    try check(
      number.report?.rows.first { $0.id == "base2" }?.value.count == 21177, "exact-large-number")
    host.rootView = AnyView(NumberConverterView(workspace: number))
    await settle(host)
    let mime = DateNetworkWorkspaces.network(.mime)
    mime.automatic = false
    let begin = ContinuousClock.now
    mime.run()
    try await done(mime)
    host.rootView = AnyView(NetworkToolsView(workspace: mime))
    await settle(host, 500)
    print(
      "DATE_BENCH full_mime_rows=\(mime.report?.rows.count ?? 0) mount=\(begin.duration(to:.now))")
    if let table = all(NSTableView.self, host).first {
      table.scrollRowToVisible(table.numberOfRows - 1)
      await settle(host, 200)
      print(
        "DATE_NATIVE_REFERENCE total=\(table.numberOfRows) visible=\(table.rows(in:table.visibleRect))"
      )
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    print("DATE_BENCH peak_bytes=\(usage.ru_maxrss) tzdb=\(ToolTimeZone.dataVersion)")
    try check(
      DateNetworkWorkspaces.date(.unix).request.input.isEmpty
        && DateNetworkWorkspaces.number().request.input.isEmpty, "fresh-session-empty")
  }
}
