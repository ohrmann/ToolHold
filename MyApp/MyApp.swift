import SwiftUI

@main struct MyApp: App {
  #if os(iOS)
    @UIApplicationDelegateAdaptor(SessionRestorationDelegate.self) private var restorationDelegate
  #endif
  @State private var sidebar: SidebarModel

  init() {
    // UI tests have an isolated preferences domain; production navigation is untouched.
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--navigation-ui-tests"),
      let defaults = UserDefaults(suiteName: "developerToolbox.navigation.ui-tests")
    {
      if arguments.contains("--reset-navigation-ui-tests") {
        defaults.removePersistentDomain(forName: "developerToolbox.navigation.ui-tests")
      }
      _sidebar = State(initialValue: SidebarModel(repository: .init(defaults: defaults)))
    } else {
      _sidebar = State(initialValue: SidebarModel())
    }
  }
  var body: some Scene {
    WindowGroup {
      ContentView(initialSelection: sidebar.preferences.selectedTool)
        .environment(sidebar)
        .modifier(ReleaseTestAccessibility())
        #if os(macOS)
          .frame(minWidth: 640, minHeight: 560)
        #endif
    }
    #if os(macOS)
      .defaultSize(width: 1280, height: 780)
      .restorationBehavior(.disabled)
    #endif
  }
}

/// Deterministic accessibility environments for isolated Debug UI tests only.
private struct ReleaseTestAccessibility: ViewModifier {
  @Environment(\.dynamicTypeSize) private var size
  @ViewBuilder func body(content: Content) -> some View {
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--navigation-ui-tests") {
      content
        .environment(\.dynamicTypeSize, arguments.contains("--accessibility5") ? .accessibility5 : size)
    } else { content }
    #else
    content
    #endif
  }
}
