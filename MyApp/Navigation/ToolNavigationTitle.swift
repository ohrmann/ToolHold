import SwiftUI

/// Only presentation changes: catalog names, search terms and persisted IDs stay intact.
private struct ToolNavigationTitle: ViewModifier {
    let tool: ToolDescriptor
    @State private var compact = true
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Bool.self) { $0.size.width < 760 } action: { compact = $0 }
            .navigationTitle(compact ? tool.compactNavigationTitle : tool.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(compact ? tool.compactNavigationTitle : tool.title)
                        .font(.headline).lineLimit(1)
                        .accessibilityLabel(tool.title).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("tool-navigation-title")
                        .help(tool.title)
                }
            }
    }
}

extension View {
    func toolNavigationTitle(_ id: ToolID) -> some View { modifier(ToolNavigationTitle(tool: ToolCatalog.tool(id))) }
}
