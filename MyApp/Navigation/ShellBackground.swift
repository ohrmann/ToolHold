import SwiftUI

/// The neutral, opaque surface of an open tool, including its controls and panel gaps.
struct ShellWorkspaceBackground: View {
  var body: some View { Self.color }

  static var color: Color {
    #if os(macOS)
      Color(nsColor: .windowBackgroundColor)
    #else
      Color(uiColor: .systemBackground)
    #endif
  }
}

/// Decorative tint for sidebar, Home and window chrome only.
struct ShellBackground: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    ZStack {
      ShellWorkspaceBackground()
      if colorScheme == .dark && contrast != .increased {
        GeometryReader { geometry in
          Self.tint(in: geometry.size)
            .mask(alignment: .top) {
              VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                  .frame(height: 40)
                Color.white
              }
            }
        }
      }
    }
    .ignoresSafeArea(.container, edges: .bottom)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  static func tint(in size: CGSize) -> LinearGradient {
    let violet = Color(red: 0.08, green: 0.23, blue: 0.43)
    let width = max(1, size.width), height = max(1, size.height)
    // Equal x/y distances keep a true 45° angle even in a tall, narrow sidebar.
    // Corner UnitPoints alone would stretch the angle with the view's aspect ratio.
    let halfSpan = (width + height) / 4
    return LinearGradient(
      stops: [
        .init(color: .clear, location: 0),
        .init(color: violet.opacity(0.06), location: 0.25),
        .init(color: violet.opacity(0.12), location: 0.5),
        .init(color: violet.opacity(0.06), location: 0.75),
        .init(color: .clear, location: 1),
      ],
      startPoint: UnitPoint(x: 0.5 - halfSpan / width, y: 0.5 - halfSpan / height),
      endPoint: UnitPoint(x: 0.5 + halfSpan / width, y: 0.5 + halfSpan / height)
    )
  }

  /// Fade to the exact workspace color at the toolbar's lower edge, so an open
  /// tool stays neutral without a hard horizontal boundary below the titlebar.
  static var toolbarTint: MeshGradient {
    let base = ShellWorkspaceBackground.color
    return MeshGradient(
      width: 3, height: 3,
      points: [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.5, 0.5], [1, 0.5],
        [0, 1], [0.5, 1], [1, 1],
      ],
      colors: [
        base, Color(red: 0.125, green: 0.12, blue: 0.16), base,
        base, Color(red: 0.12, green: 0.118, blue: 0.14), base,
        base, base, base,
      ]
    )
  }
}

/// A native toolbar background keeps the fade inside chrome, above the neutral tool.
struct ShellWindowChrome: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var contrast

  private var tinted: Bool { colorScheme == .dark && contrast != .increased }

  func body(content: Content) -> some View {
    #if os(macOS)
      content
        .containerBackground(for: .window) { ShellWorkspaceBackground() }
        .toolbarBackground(
          tinted ? AnyShapeStyle(ShellBackground.toolbarTint) : AnyShapeStyle(.bar),
          for: .windowToolbar
        )
        .toolbarBackground(tinted ? .visible : .automatic, for: .windowToolbar)
    #else
      content
        .toolbarBackground(
          tinted ? AnyShapeStyle(ShellBackground.toolbarTint) : AnyShapeStyle(.bar),
          for: .navigationBar
        )
        .toolbarBackground(tinted ? .visible : .automatic, for: .navigationBar)
    #endif
  }
}
