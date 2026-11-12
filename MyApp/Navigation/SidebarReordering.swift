import SwiftUI
import UniformTypeIdentifiers

struct SidebarDrag: Codable, Equatable {
  static let type = UTType(exportedAs: "dev.developertoolbox.navigation-item")
  let scope: NavigationPreferences.Scope
  let id: String
  let nonce: UUID

  func provider() -> NSItemProvider {
    let provider = NSItemProvider()
    let data = try? JSONEncoder().encode(self)
    provider.registerDataRepresentation(
      forTypeIdentifier: Self.type.identifier, visibility: .ownProcess
    ) { completion in
      completion(data, nil)
      return nil
    }
    return provider
  }
}

/// The preview describes the entire row even though the gesture starts only on the handle.
struct SidebarDragPreview: View {
  let title: String
  let symbol: String
  let subtitle: String?
  let favorite: Bool
  let selected: Bool
  let width: CGFloat

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol).frame(width: 22).foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.body).lineLimit(2)
        if let subtitle {
          Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            .lineLimit(1).truncationMode(.tail)
        }
      }
      Spacer(minLength: 8)
      if favorite { Image(systemName: "star.fill").foregroundStyle(.orange) }
      Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
    }
    .padding(12)
    .frame(width: max(220, width), alignment: .leading)
    .background(.background, in: RoundedRectangle(cornerRadius: 9))
    .overlay {
      RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? .green : .secondary.opacity(0.3))
    }
  }
}

struct SidebarReorderHandle: View {
  let title: String
  let id: String
  let order: [String]
  let preview: SidebarDragPreview
  let begin: () -> SidebarDrag
  let ended: (Bool) -> Void
  let move: (Int) -> Void

  var body: some View {
    HStack(spacing: 0) {
      dragSource
      Menu {
        Button("Move up", systemImage: "arrow.up") { move(-1) }
          .disabled(order.first == id)
        Button("Move down", systemImage: "arrow.down") { move(1) }
          .disabled(order.last == id)
      } label: {
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption).foregroundStyle(.secondary)
          .frame(width: 24, height: 36)
          .contentShape(Rectangle())
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .accessibilityLabel("Reorder \(title)")
      .accessibilityIdentifier("move-" + id)
      .help("Move up or down")
    }
  }

  private var handleImage: some View {
    Image(systemName: "line.3.horizontal")
      .foregroundStyle(.secondary)
      .frame(width: 24, height: 36)
      .contentShape(Rectangle())
      .accessibilityLabel("Drag to reorder \(title)")
      .accessibilityIdentifier("drag-" + id)
      .help("Drag to reorder")
  }

  private var dragSource: some View {
    handleImage.overlay {
      SidebarNativeDragSource(preview: preview, begin: begin, ended: ended)
        .accessibilityHidden(true)
    }
  }
}

struct SidebarDropTarget: ViewModifier {
  let scope: NavigationPreferences.Scope
  let before: String?
  let enabled: Bool
  let dragging: SidebarDrag?
  let hover: (String?) -> Void
  let resolve: (SidebarDrag, Bool) -> Void
  var previewOnEntry = true
  var indicatesSlot = true
  @State private var targeted = false

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .top) {
        // The provisional source row now occupies the insertion slot.
        if indicatesSlot && enabled && dragging?.scope == scope && dragging?.id == before {
          Rectangle().fill(.green).frame(height: 3).allowsHitTesting(false)
        } else if indicatesSlot && targeted && before == nil {
          Rectangle().fill(.green).frame(height: 3).allowsHitTesting(false)
        }
      }
      .onDrop(
        of: [SidebarDrag.type],
        delegate: Delegate(
          scope: scope, before: before, enabled: enabled,
          dragging: dragging, targeted: $targeted, hover: hover, resolve: resolve,
          previewOnEntry: previewOnEntry))
  }

  private struct Delegate: DropDelegate {
    let scope: NavigationPreferences.Scope
    let before: String?
    let enabled: Bool
    let dragging: SidebarDrag?
    @Binding var targeted: Bool
    let hover: (String?) -> Void
    let resolve: (SidebarDrag, Bool) -> Void
    let previewOnEntry: Bool

    func validateDrop(info: DropInfo) -> Bool {
      enabled && dragging?.scope == scope && info.hasItemsConforming(to: [SidebarDrag.type])
    }
    func dropEntered(info: DropInfo) {
      targeted = validateDrop(info: info)
      if targeted && previewOnEntry { hover(before) }
    }
    func dropExited(info: DropInfo) { targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? {
      DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
      targeted = false
      guard validateDrop(info: info), let expected = dragging,
        let provider = info.itemProviders(for: [SidebarDrag.type]).first
      else { return false }
      provider.loadDataRepresentation(forTypeIdentifier: SidebarDrag.type.identifier) { data, _ in
        let received = data.flatMap { try? JSONDecoder().decode(SidebarDrag.self, from: $0) }
        DispatchQueue.main.async { resolve(expected, received == expected) }
      }
      return true
    }
  }
}
