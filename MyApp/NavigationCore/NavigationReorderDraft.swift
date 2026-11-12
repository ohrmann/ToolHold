import Foundation

/// A drag's provisional order. It never writes preferences or contains tool content.
struct NavigationReorderDraft: Equatable {
  let scope: NavigationPreferences.Scope
  let id: String
  let originalOrder: [String]
  private(set) var previewOrder: [String]
  private var lastTarget: String?
  private var hasTarget = false

  init?(scope: NavigationPreferences.Scope, id: String, preferences: NavigationPreferences) {
    let order = preferences.order(in: scope)
    guard order.contains(id) else { return nil }
    self.scope = scope
    self.id = id
    originalOrder = order
    previewOrder = order
  }

  /// Move past a hovered neighbour in the direction of travel; repeated entry is idempotent.
  mutating func preview(over target: String?) {
    guard !hasTarget || lastTarget != target else { return }
    hasTarget = true
    lastTarget = target
    guard target != id else { return }
    guard let target else {
      previewOrder.removeAll { $0 == id }
      previewOrder.append(id)
      return
    }
    guard let from = previewOrder.firstIndex(of: id),
      let to = previewOrder.firstIndex(of: target)
    else { return }
    previewOrder.remove(at: from)
    previewOrder.insert(id, at: to)
  }

  /// Apply only this scope, preserving appearance, route and other independently changed settings.
  /// A concurrent edit of this same order invalidates the drag instead of overwriting it.
  func applying(to preferences: NavigationPreferences) -> NavigationPreferences? {
    guard preferences.order(in: scope) == originalOrder else { return nil }
    var result = preferences
    switch scope {
    case .categories: result.categoryOrder = previewOrder
    case .tools(let category): result.toolOrder[category.rawValue] = previewOrder
    case .favorites: result.favorites = previewOrder
    }
    return result
  }
}
