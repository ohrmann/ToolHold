import SwiftUI
import UIKit

@testable import Developer_Toolbox

@main final class DateNetworkUIKitProbe: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  func application(
    _ app: UIApplication,
    didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    setbuf(stdout, nil)
    return true
  }
  func application(
    _ app: UIApplication, configurationForConnecting session: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let c = UISceneConfiguration(name: "Default", sessionRole: session.role)
    c.delegateClass = DateNetworkProbeScene.self
    return c
  }
  func connect(_ scene: UIWindowScene) {
    window = UIWindow(windowScene: scene)
    window?.makeKeyAndVisible()
    Task { @MainActor in
      do {
        try await run()
        print("DATE_UIKIT_PASSED")
      } catch {
        print("DATE_UIKIT_FAILED \(error)")
        exit(1)
      }
      exit(0)
    }
  }
  enum Failure: Error { case check(String) }
  func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
    guard value() else { throw Failure.check(name) }
    print("DATE_UIKIT_OK \(name)")
  }
  func all<T: UIView>(_ type: T.Type, _ view: UIView) -> [T] {
    ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, $0) }
  }
  func settle(_ ms: Int = 180) async {
    try? await Task.sleep(for: .milliseconds(ms))
    window?.layoutIfNeeded()
  }
  func done<R>(_ w: CalculationWorkspace<R>) async throws {
    for _ in 0..<200 {
      if !w.busy { return }
      await settle(15)
    }
    throw Failure.check("timeout")
  }
  func run() async throws {
    let w = DateNetworkWorkspaces.date(.unix)
    let host = UIHostingController(rootView: AnyView(EmptyView()))
    w.request.unit = .seconds
    window?.rootViewController = host
    host.rootView = AnyView(DateToolsView(workspace: w))
    await settle(400)
    guard
      let field = all(UITextField.self, host.view).first(where: {
        $0.placeholder == "e.g. 0 or -0.000001"
      })
    else { throw Failure.check("native field") }
    field.becomeFirstResponder()
    field.insertText("1.5")
    await settle(400)
    try await done(w)
    try check(
      w.report?.rows.contains { $0.id == "unit3" && $0.value == "1500" } == true,
      "native-input-auto-convert")
    let id = ObjectIdentifier(field)
    let selection = field.selectedTextRange
    host.overrideUserInterfaceStyle = .dark
    await settle()
    try check(
      all(UITextField.self, host.view).contains { ObjectIdentifier($0) == id }
        && field.text == "1.5", "dark-field-identity-value")
    host.overrideUserInterfaceStyle = .light
    await settle()
    try check(field.selectedTextRange == selection, "light-caret-preserved")
    field.undoManager?.undo()
    await settle(300)
    try check(w.request.input.isEmpty, "native-undo")
    field.undoManager?.redo()
    await settle(300)
    try check(w.request.input == "1.5", "native-redo")
    let rev = w.revision
    field.setMarkedText("2", selectedRange: .init(location: 1, length: 0))
    await settle(300)
    try check(w.revision == rev, "ime-no-work-during-composition")
    field.unmarkText()
    field.sendActions(for: .editingChanged)
    await settle(300)
    field.resignFirstResponder()
    for tool in DateTool.allCases {
      let s = DateNetworkWorkspaces.date(tool)
      s.automatic = false
      s.request.input =
        tool == .unix ? "-0.000001" : tool == .cron ? "30 2 * * *" : "2026-10-25T00:30:00Z"
      if tool == .cron {
        s.request.zone = "Europe/Prague"
        s.request.secondInput = "2026-10-24T23:00:00Z"
        s.request.findOccurrences = true
      }
      s.run()
      try await done(s)
      try check(s.report != nil, "date-\(tool.rawValue)-result")
      host.rootView = AnyView(DateToolsView(workspace: s))
      await settle()
    }
    for tool in [NetworkTool.cidr, .http, .mime, .chmod] {
      let s = DateNetworkWorkspaces.network(tool)
      s.automatic = false
      s.request.input =
        tool == .cidr ? "::/0" : tool == .http ? "404" : tool == .mime ? "file.json" : "4755"
      s.run()
      try await done(s)
      if let issue = s.issue {
        print("DATE_UIKIT_ISSUE \(tool.rawValue) \(issue.kind) \(issue.message)")
      }
      try check(s.report?.rows.isEmpty == false, "network-\(tool.rawValue)-result")
      host.rootView = AnyView(NetworkToolsView(workspace: s))
      await settle()
    }
    let n = DateNetworkWorkspaces.number()
    n.request.input = "18446744073709551616"
    n.run()
    try await done(n)
    host.rootView = AnyView(NumberConverterView(workspace: n))
    await settle()
    try check(
      n.report?.rows.contains { $0.id == "base16" && $0.value == "10000000000000000" } == true,
      "number-above-UInt64")
    let p = try ToolTimeZone("Europe/Prague").resolve(
      DateTextParser.parse("2026-10-25T02:30:00", profile: .local).time!)
    try check(p.count == 2 && p[1].seconds - p[0].seconds == 3600, "prague-fold")
    let apia = try ToolTimeZone("Pacific/Apia").resolve(
      DateTextParser.parse("2011-12-30T12:00:00", profile: .local).time!)
    try check(apia.isEmpty, "apia-skipped-day")
    let lord = try ToolTimeZone("Australia/Lord_Howe").resolve(
      DateTextParser.parse("2026-04-05T01:45:00", profile: .local).time!)
    try check(lord.count == 2 && lord[1].seconds - lord[0].seconds == 1800, "lord-howe-half-hour")
    print(
      "DATE_UIKIT_DEVICE \(UIDevice.current.model) width=\(host.view.bounds.width) tzdb=\(ToolTimeZone.dataVersion)"
    )
  }
}
@MainActor final class DateNetworkProbeScene: UIResponder, UIWindowSceneDelegate {
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions
  ) {
    if let w = scene as? UIWindowScene {
      (UIApplication.shared.delegate as? DateNetworkUIKitProbe)?.connect(w)
    }
  }
}
