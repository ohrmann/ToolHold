import Foundation

enum AppAppearance: String, Codable, CaseIterable, Sendable {
  case system, light, dark
}

/// Only UI settings and navigation IDs are persisted. Never add tool inputs or outputs here.
struct NavigationPreferences: Codable, Equatable, Sendable {
  var version = 3
  var categoryOrder: [String]
  var toolOrder: [String: [String]]
  var favorites: [String]
  var expandedCategories: [String]
  var favoritesExpanded = false
  var appearance: AppAppearance = .system
  var selectedToolID: String? = nil

  enum CodingKeys: String, CodingKey {
    case version, categoryOrder, toolOrder, favorites, expandedCategories, favoritesExpanded,
      selectedToolID, appearance
  }

  init(
    categoryOrder: [String], toolOrder: [String: [String]], favorites: [String],
    expandedCategories: [String]
  ) {
    self.categoryOrder = categoryOrder
    self.toolOrder = toolOrder
    self.favorites = favorites
    self.expandedCategories = expandedCategories
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
    categoryOrder = try values.decode([String].self, forKey: .categoryOrder)
    toolOrder = try values.decode([String: [String]].self, forKey: .toolOrder)
    favorites = try values.decode([String].self, forKey: .favorites)
    expandedCategories = try values.decode([String].self, forKey: .expandedCategories)
    favoritesExpanded = try values.decodeIfPresent(Bool.self, forKey: .favoritesExpanded) ?? false
    selectedToolID = try values.decodeIfPresent(String.self, forKey: .selectedToolID)
    appearance =
      (try values.decodeIfPresent(String.self, forKey: .appearance))
      .flatMap(AppAppearance.init(rawValue:)) ?? .system
  }

  /// nil is Home. Candidate previews may be selected live, but aren't restored as working tools.
  var selectedTool: ToolID? {
    get { selectedToolID.flatMap(ToolID.init(rawValue:)) }
    set { selectedToolID = newValue?.rawValue }
  }

  func isFavoritesExpanded(query: String) -> Bool {
    ToolCatalog.isSearching(query) || favoritesExpanded
  }

  static var defaults: Self {
    Self(
      categoryOrder: ToolCategory.allCases.map(\.rawValue),
      toolOrder: Dictionary(
        uniqueKeysWithValues: ToolCategory.allCases.map {
          ($0.rawValue, ToolCatalog.tools(in: $0).map(\.rawValue))
        }), favorites: [], expandedCategories: [])
  }

  /// Keep known relative order, remove duplicate/deleted IDs, append new catalog entries.
  func reconciled() -> Self {
    guard (1...3).contains(version) else { return .defaults }
    var result = Self.defaults
    result.categoryOrder = Self.merge(categoryOrder, allowed: result.categoryOrder)
    for category in ToolCategory.allCases {
      result.toolOrder[category.rawValue] = Self.merge(
        toolOrder[category.rawValue] ?? [],
        allowed: ToolCatalog.tools(in: category).map(\.rawValue))
    }
    result.favorites = Self.unique(favorites.filter { ToolID(rawValue: $0) != nil })
    result.expandedCategories = Self.unique(
      expandedCategories.filter { ToolCategory(rawValue: $0) != nil })
    result.favoritesExpanded = favoritesExpanded
    result.appearance = appearance
    if let selectedTool, ToolCatalog.tool(selectedTool).isImplemented {
      result.selectedTool = selectedTool
    }
    return result
  }

  var categories: [ToolCategory] { categoryOrder.compactMap(ToolCategory.init(rawValue:)) }
  var favoriteIDs: [ToolID] { favorites.compactMap(ToolID.init(rawValue:)) }
  func tools(in category: ToolCategory) -> [ToolID] {
    (toolOrder[category.rawValue] ?? []).compactMap(ToolID.init(rawValue:))
  }
  func visibleTools(in category: ToolCategory, query: String) -> [ToolID] {
    tools(in: category).filter { ToolCatalog.matches($0, query: query) }
  }
  func visibleCategories(query: String) -> [ToolCategory] {
    categories.filter { !visibleTools(in: $0, query: query).isEmpty }
  }
  func visibleFavorites(query: String) -> [ToolID] {
    favoriteIDs.filter { ToolCatalog.matches($0, query: query) }
  }
  func isExpanded(_ category: ToolCategory, query: String) -> Bool {
    ToolCatalog.isSearching(query) || expandedCategories.contains(category.rawValue)
  }
  mutating func setExpanded(_ category: ToolCategory, _ expanded: Bool) {
    expandedCategories.removeAll { $0 == category.rawValue }
    if expanded { expandedCategories.append(category.rawValue) }
  }
  mutating func toggleFavorite(_ tool: ToolID) {
    if favorites.contains(tool.rawValue) {
      favorites.removeAll { $0 == tool.rawValue }
    } else {
      favorites.append(tool.rawValue)
    }
  }
  /// Reset order only: preserve membership of Favorites and expanded/collapsed state.
  mutating func resetOrder() {
    categoryOrder = Self.defaults.categoryOrder
    toolOrder = Self.defaults.toolOrder
    favorites = ToolID.allCases.map(\.rawValue).filter { favorites.contains($0) }
  }

  enum Scope: Hashable, Codable, Sendable {
    case categories
    case tools(ToolCategory)
    case favorites
  }
  func order(in scope: Scope) -> [String] {
    switch scope {
    case .categories: return categoryOrder
    case .tools(let category): return toolOrder[category.rawValue] ?? []
    case .favorites: return favorites
    }
  }
  /// Both source and target must already belong to the same scope. nil means end.
  @discardableResult
  mutating func move(_ id: String, in scope: Scope, before target: String?, query: String = "")
    -> Bool
  {
    guard !ToolCatalog.isSearching(query) else { return false }
    var ids = order(in: scope)
    guard ids.contains(id), target != id, target == nil || ids.contains(target!) else {
      return false
    }
    ids.removeAll { $0 == id }
    let index = target.flatMap { ids.firstIndex(of: $0) } ?? ids.endIndex
    ids.insert(id, at: index)
    switch scope {
    case .categories: categoryOrder = ids
    case .tools(let category): toolOrder[category.rawValue] = ids
    case .favorites: favorites = ids
    }
    return true
  }
  @discardableResult
  mutating func moveBy(_ step: Int, id: String, in scope: Scope, query: String = "") -> Bool {
    let ids = order(in: scope)
    guard let index = ids.firstIndex(of: id), ids.indices.contains(index + step),
      step == -1 || step == 1
    else { return false }
    let targetIndex = step < 0 ? index - 1 : index + 2
    return move(
      id, in: scope, before: targetIndex < ids.count ? ids[targetIndex] : nil, query: query)
  }
  private static func unique(_ ids: [String]) -> [String] {
    var seen = Set<String>()
    return ids.filter { seen.insert($0).inserted }
  }
  private static func merge(_ saved: [String], allowed: [String]) -> [String] {
    unique(saved.filter { allowed.contains($0) } + allowed)
  }
}

struct NavigationPreferencesRepository {
  static let key = "developerToolbox.navigation.v1"
  let defaults: UserDefaults
  init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  func load() -> NavigationPreferences {
    guard let data = defaults.data(forKey: Self.key),
      let saved = try? JSONDecoder().decode(NavigationPreferences.self, from: data)
    else { return .defaults }
    return saved.reconciled()
  }
  func save(_ preferences: NavigationPreferences) {
    guard let data = try? JSONEncoder().encode(preferences.reconciled()) else { return }
    defaults.set(data, forKey: Self.key)
  }
}
