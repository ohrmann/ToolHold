import SwiftUI

extension AppAppearance {
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

struct AppearanceMenu: View {
  @Environment(SidebarModel.self) private var model

  var body: some View {
    Menu {
      Picker(
        "Appearance",
        selection: Binding(
          get: { model.preferences.appearance },
          set: { model.preferences.appearance = $0 }
        )
      ) {
        ForEach(AppAppearance.allCases, id: \.self) { mode in
          Text(mode.rawValue.capitalized).tag(mode)
            .accessibilityIdentifier("appearance-" + mode.rawValue)
        }
      }
    } label: {
      Label("Appearance", systemImage: "circle.lefthalf.filled")
    }
    .labelStyle(.iconOnly)
    .accessibilityLabel("Appearance: " + model.preferences.appearance.rawValue.capitalized)
    .accessibilityValue(model.preferences.appearance.rawValue.capitalized)
    .accessibilityIdentifier("appearance-menu")
    .help("Appearance: System, Light or Dark")
  }
}
