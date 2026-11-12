import SwiftUI

struct ToolSidebar: View {
  @Environment(SidebarModel.self) private var model
  @Binding var selection: ToolID?
  let openHome: () -> Void
  let openTool: (ToolID) -> Void
  @State private var query = ""
  @State private var reordering = false
  @State private var dragging: SidebarDrag?
  @State private var reorderDraft: NavigationReorderDraft?
  @State private var verifiedDrop = false
  @State private var dragEndedWithMove = false
  @State private var sidebarWidth: CGFloat = 320
  @FocusState private var focusedRow: String?
  @FocusState private var searchFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.colorScheme) private var colorScheme

  private var reduceMotion: Bool {
    // The system environment is read-only. The isolated UI harness can exercise this branch.
    let arguments = ProcessInfo.processInfo.arguments
    return systemReduceMotion
      || (arguments.contains("--navigation-ui-tests") && arguments.contains("--reduce-motion"))
  }

  private var displayed: NavigationPreferences {
    reorderDraft?.applying(to: model.preferences) ?? model.preferences
  }

  private var searching: Bool { ToolCatalog.isSearching(query) }
  private var canReorder: Bool { reordering && !searching }
  private var categories: [ToolCategory] { displayed.visibleCategories(query: query) }
  private var favorites: [ToolID] { displayed.visibleFavorites(query: query) }
  private var selectionColor: Color {
    colorScheme == .dark
      ? Color(red: 0.18, green: 0.23, blue: 0.24) : Color(red: 0.85, green: 0.94, blue: 0.86)
  }

  var body: some View {
    VStack(spacing: 0) {
      searchField
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 4) {
            homeRow
            VStack(alignment: .leading, spacing: 4) {
              favoritesHeader
              if displayed.isFavoritesExpanded(query: query) {
                if favorites.isEmpty {
                  Text(searching ? "No matching favorites" : "Star a tool to keep it here.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .transition(.opacity)
                }
                VStack(alignment: .leading, spacing: 4) {
                  ForEach(favorites) { toolRow($0, scope: .favorites).transition(.opacity) }
                  endTarget(.favorites)
                }
                .background { dropArea(.favorites) }
              }
            }
            Divider().padding(.horizontal, 12).padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 4) {
              ForEach(categories) { category in
                VStack(alignment: .leading, spacing: 4) {
                  categoryHeader(category)
                  if displayed.isExpanded(category, query: query) {
                    VStack(alignment: .leading, spacing: 4) {
                      ForEach(displayed.visibleTools(in: category, query: query)) { id in
                        toolRow(id, scope: .tools(category)).transition(.opacity)
                      }
                      endTarget(.tools(category))
                    }
                    .background { dropArea(.tools(category)) }
                  }
                }
                .opacity(
                  dragging?.scope == .categories && dragging?.id == category.rawValue ? 0.5 : 1)
              }
            }
            .background { dropArea(.categories) }
            if categories.isEmpty {
              ContentUnavailableView.search(text: query)
            }
            endTarget(.categories)
          }
          .padding(.bottom, 12)
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: displayed)
        }
        .onChange(of: focusedRow) { _, token in
          if let token { proxy.scrollTo(token) }
        }
      }
      .onKeyPress(.upArrow) { navigate(-1) }
      .onKeyPress(.downArrow) { navigate(1) }
      Divider()
      HStack {
        Text(
          searching
            ? "\(matchCount) matches"
            : "\(ToolCatalog.tools.count) tools"
        )
        .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Menu {
          Button("Reset to Default Order", systemImage: "arrow.counterclockwise") {
            cancelDrag()
            model.preferences.resetOrder()
          }.disabled(searching)
          if !searching {
            Button("Expand All") {
              model.preferences.expandedCategories = ToolCategory.allCases.map(\.rawValue)
            }
            Button("Collapse All") { model.preferences.expandedCategories = [] }
          }
        } label: {
          Image(systemName: "ellipsis.circle").padding(4)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel("Catalog options").accessibilityIdentifier("catalog-options")
      }.padding(.horizontal, 14).padding(.vertical, 8)
    }
    .navigationTitle("ToolHold")
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      sidebarWidth = $0
    }
    .onDisappear { cancelDrag() }
    .toolbar {
      ToolbarItem {
        Button(
          reordering ? "Done" : "Reorder",
          systemImage: reordering ? "checkmark" : "arrow.up.arrow.down"
        ) {
          reordering.toggle()
          cancelDrag()
        }
        .disabled(searching)
        .help("Reorder categories, tools and favorites")
        .accessibilityIdentifier("catalog-reorder")
        .accessibilityLabel(
          dragging != nil ? "Dragging to reorder" : (reordering ? "Done reordering" : "Reorder"))
      }
    }
    .onChange(of: query) { _, _ in cancelDrag() }
    .onChange(of: reordering) { _, _ in cancelDrag() }
  }

  private var homeRow: some View {
    Button {
      cancelDrag()
      searchFocused = false
      openHome()
    } label: {
      Label("Home", systemImage: "house")
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(selection == nil ? selectionColor : .clear, in: RoundedRectangle(cornerRadius: 8))
    .padding(.horizontal, 10)
    .accessibilityIdentifier("sidebar-home")
    .accessibilityAddTraits(selection == nil ? [.isSelected] : [])
  }

  private var favoritesHeader: some View {
    Button {
      guard !searching else { return }
      cancelDrag()
      model.preferences.favoritesExpanded.toggle()
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "chevron.right")
          .rotationEffect(.degrees(displayed.isFavoritesExpanded(query: query) ? 90 : 0))
          .font(.caption.weight(.semibold)).frame(width: 10)
        Image(systemName: "star").frame(width: 20)
        Text("Favorites").font(.body.weight(.semibold))
        Spacer()
        Text("\(favorites.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
      }
      .padding(.vertical, 10).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 14)
    .accessibilityLabel("Favorites")
    .accessibilityIdentifier("favorites-section")
    .accessibilityValue(
      displayed.isFavoritesExpanded(query: query) ? "Expanded" : "Collapsed"
    )
    .accessibilityHint(
      searching ? "Matches are expanded during search" : "Expand or collapse Favorites")
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
      TextField("Search tools", text: $query)
        .textFieldStyle(.plain)
        .autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
        .focused($searchFocused)
        .accessibilityLabel("Search tools").accessibilityIdentifier("tool-search")
        .onKeyPress(.escape) {
          query = ""
          return .handled
        }
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless).accessibilityLabel("Clear search")
      }
    }
    .padding(10)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
    .padding(.horizontal, 12).padding(.vertical, 8)
  }

  private func categoryHeader(_ category: ToolCategory) -> some View {
    HStack(spacing: 6) {
      Button {
        guard !searching else { return }
        let expanded = displayed.isExpanded(category, query: "")
        model.preferences.setExpanded(category, !expanded)
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "chevron.right")
            .rotationEffect(.degrees(displayed.isExpanded(category, query: query) ? 90 : 0))
            .font(.caption.weight(.semibold)).frame(width: 10)
          Image(systemName: category.symbol).frame(width: 20)
          Text(category.title).font(.body.weight(.semibold))
          Spacer(minLength: 2)
          Text("\(displayed.visibleTools(in: category, query: query).count)")
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(category.title).accessibilityIdentifier("category-" + category.rawValue)
      .accessibilityValue(
        displayed.isExpanded(category, query: query) ? "Expanded" : "Collapsed"
      )
      .accessibilityHint(
        searching ? "Matching tools are expanded during search" : "Expand or collapse category")
      if canReorder { handle(category.title, id: category.rawValue, scope: .categories) }
    }
    .padding(.horizontal, 14)
    .modifier(dropTarget(.categories, before: category.rawValue))
    .accessibilityAction(named: "Move category up") {
      moveBy(-1, id: category.rawValue, scope: .categories)
    }
    .accessibilityAction(named: "Move category down") {
      moveBy(1, id: category.rawValue, scope: .categories)
    }
  }

  private func toolRow(_ id: ToolID, scope: NavigationPreferences.Scope) -> some View {
    let tool = ToolCatalog.tool(id)
    let favorite = displayed.favoriteIDs.contains(id)
    let token = rowToken(id, scope: scope)
    return HStack(spacing: 4) {
      Button {
        searchFocused = false
        focusedRow = token
        openTool(id)
      } label: {
        HStack(alignment: .center, spacing: 10) {
          Image(systemName: tool.symbol).frame(width: 22).foregroundStyle(.secondary)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(tool.displayName).font(.body).lineLimit(2).multilineTextAlignment(.leading)
            Text(tool.shortDescription).font(.caption2).foregroundStyle(.secondary)
              .lineLimit(1).truncationMode(.tail)
          }
          Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focused($focusedRow, equals: token)
      .accessibilityLabel(tool.displayName).accessibilityIdentifier(token)
      .accessibilityValue(tool.shortDescription)
      .help(tool.title)
      .accessibilityHint(tool.isImplemented ? "Open tool" : "Not implemented. Opens a preview page")
      .accessibilityAddTraits(selection == id ? [.isSelected] : [])
      .contextMenu {
        Button(
          favorite ? "Remove from Favorites" : "Add to Favorites",
          systemImage: favorite ? "star.slash" : "star"
        ) {
          model.preferences.toggleFavorite(id)
        }
        if !searching {
          Divider()
          Button("Move up", systemImage: "arrow.up") { moveBy(-1, id: id.rawValue, scope: scope) }
            .disabled(displayed.order(in: scope).first == id.rawValue)
          Button("Move down", systemImage: "arrow.down") {
            moveBy(1, id: id.rawValue, scope: scope)
          }
          .disabled(displayed.order(in: scope).last == id.rawValue)
        }
      }
      Button {
        cancelDrag()
        model.preferences.toggleFavorite(id)
      } label: {
        Image(systemName: favorite ? "star.fill" : "star")
          .foregroundStyle(favorite ? Color.orange : Color.secondary)
          .frame(minWidth: 36, minHeight: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("\(favorite ? "Remove from" : "Add to") Favorites: \(tool.displayName)")
      .help(favorite ? "Remove from Favorites" : "Add to Favorites")
      .accessibilityIdentifier("star-" + token)
      if canReorder { handle(tool.displayName, id: id.rawValue, scope: scope) }
    }
    .padding(.leading, scope == .favorites ? 0 : 12)
    .padding(.horizontal, 6)
    .background(selection == id ? selectionColor : .clear, in: RoundedRectangle(cornerRadius: 8))
    .modifier(dropTarget(scope, before: id.rawValue))
    .opacity(dragging?.scope == scope && dragging?.id == id.rawValue ? 0.5 : 1)
    .accessibilityElement(children: .contain)
    .accessibilityAction(named: "Move up") { moveBy(-1, id: id.rawValue, scope: scope) }
    .accessibilityAction(named: "Move down") { moveBy(1, id: id.rawValue, scope: scope) }
    .padding(.horizontal, 10)
    .id(token)
  }

  @ViewBuilder private func endTarget(_ scope: NavigationPreferences.Scope) -> some View {
    if canReorder && dragging?.scope == scope {
      Text("Drop at end").font(.caption).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .modifier(dropTarget(scope, before: nil))
        .accessibilityHidden(true)
    }
  }
  private func handle(_ title: String, id: String, scope: NavigationPreferences.Scope) -> some View
  {
    let tool = ToolID(rawValue: id).map(ToolCatalog.tool)
    let category = ToolCategory(rawValue: id)
    return SidebarReorderHandle(
      title: title, id: id, order: displayed.order(in: scope),
      preview: SidebarDragPreview(
        title: title, symbol: tool?.symbol ?? category?.symbol ?? "folder",
        subtitle: tool?.shortDescription
          ?? category.map {
            "\(displayed.tools(in: $0).count) tools"
          },
        favorite: tool.map { displayed.favoriteIDs.contains($0.id) } ?? false,
        selected: tool?.id == selection && tool != nil, width: sidebarWidth - 24),
      begin: { beginDrag(id: id, scope: scope) }, ended: dragEnded
    ) {
      moveBy($0, id: id, scope: scope)
    }
  }
  /// Stable scope-sized fallback: accepts the provisional position in inter-row gaps.
  /// Row targets still choose the position; another category never accepts a tool drag.
  private func dropArea(_ scope: NavigationPreferences.Scope) -> some View {
    Color.clear.contentShape(Rectangle())
      .modifier(dropTarget(scope, before: dragging?.id, previewOnEntry: false))
      .accessibilityHidden(true)
  }
  private func dropTarget(
    _ scope: NavigationPreferences.Scope, before: String?, previewOnEntry: Bool = true
  )
    -> SidebarDropTarget
  {
    SidebarDropTarget(
      scope: scope, before: before, enabled: canReorder, dragging: dragging,
      hover: { target in
        guard canReorder, dragging?.scope == scope else { return }
        reorderDraft?.preview(over: target)
      },
      resolve: { item, valid in
        guard canReorder, dragging == item else { return }
        guard valid else {
          cancelDrag()
          return
        }
        verifiedDrop = true
        finishDragIfReady()
      }, previewOnEntry: previewOnEntry, indicatesSlot: previewOnEntry)
  }
  private func beginDrag(id: String, scope: NavigationPreferences.Scope) -> SidebarDrag {
    if let active = dragging, active.scope == scope, active.id == id { return active }
    cancelDrag()
    let item = SidebarDrag(scope: scope, id: id, nonce: UUID())
    reorderDraft = NavigationReorderDraft(scope: scope, id: id, preferences: model.preferences)
    dragging = item
    return item
  }
  private func dragEnded(_ moved: Bool) {
    if moved {
      dragEndedWithMove = true
      finishDragIfReady()
    } else {
      cancelDrag()
    }
  }
  private func finishDragIfReady() {
    guard verifiedDrop, dragEndedWithMove else { return }
    if let updated = reorderDraft?.applying(to: model.preferences), canReorder {
      model.preferences = updated
    }
    cancelDrag()
  }
  private func cancelDrag() {
    dragging = nil
    reorderDraft = nil
    verifiedDrop = false
    dragEndedWithMove = false
  }
  private func moveBy(_ step: Int, id: String, scope: NavigationPreferences.Scope) {
    cancelDrag()
    model.preferences.moveBy(step, id: id, in: scope, query: query)
  }
  private var matchCount: Int {
    categories.reduce(0) { $0 + displayed.visibleTools(in: $1, query: query).count }
  }
  private func rowToken(_ id: ToolID, scope: NavigationPreferences.Scope) -> String {
    switch scope {
    case .favorites: return "favorite-" + id.rawValue
    case .tools(let category): return category.rawValue + "-" + id.rawValue
    case .categories: return id.rawValue
    }
  }
  private func navigate(_ step: Int) -> KeyPress.Result {
    guard !searchFocused, let focusedRow else { return .ignored }
    var rows = (displayed.isFavoritesExpanded(query: query) ? favorites : []).map {
      ($0, rowToken($0, scope: .favorites))
    }
    for category in categories where displayed.isExpanded(category, query: query) {
      rows += displayed.visibleTools(in: category, query: query).map {
        ($0, rowToken($0, scope: .tools(category)))
      }
    }
    guard let index = rows.firstIndex(where: { $0.1 == focusedRow }),
      rows.indices.contains(index + step)
    else { return .ignored }
    let next = rows[index + step]
    self.focusedRow = next.1
    selection = next.0
    return .handled
  }
}
