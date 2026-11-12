import SwiftUI

struct HomeView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let showsBrowseTools: Bool
  let browseTools: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        Image("th")
          .resizable()
          .scaledToFit()
          .frame(width: 92, height: 92)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 12) {
          Text("ToolHold").font(.largeTitle.bold())
          Text("Your private workspace for everyday technical tasks.")
            .font(.title3).foregroundStyle(.secondary)
            .accessibilityIdentifier("home-tagline")
          Text("Welcome. Find a tool, make it yours, and get back to your work.")
            .foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 22) {
          feature(
            "Find your tool", symbol: "magnifyingglass",
            detail: showsBrowseTools
              ? "Browse tools by category or search by name."
              : "Search by name or browse the categories in the sidebar.")
          feature(
            "Keep favorites close", symbol: "star",
            detail: "Star the tools you reach for most often.")
          feature(
            "Arrange your workspace", symbol: "arrow.up.arrow.down",
            detail: "Reorder categories, tools and favorites to suit your workflow.")
          feature(
            "Work privately", symbol: "lock.shield",
            detail: "Tool data stays on your device and is not saved between launches.")
        }
        Button("Browse tools", systemImage: "sidebar.left", action: browseTools)
          .buttonStyle(.bordered)
          .accessibilityIdentifier("home-browse")
          // Reserve its space so the centered content doesn't jump when the sidebar toggles.
          .opacity(showsBrowseTools ? 1 : 0)
          .disabled(!showsBrowseTools)
          .allowsHitTesting(showsBrowseTools)
          .accessibilityHidden(!showsBrowseTools)
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showsBrowseTools)
      }
      .frame(maxWidth: 560, alignment: .leading)
      .padding(32)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .navigationTitle("Home")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .accessibilityIdentifier("home-screen")
  }

  private func feature(_ title: String, symbol: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: symbol).font(.title3).foregroundStyle(.secondary)
        .frame(width: 26, height: 26).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline)
        Text(detail).font(.subheadline).foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}
