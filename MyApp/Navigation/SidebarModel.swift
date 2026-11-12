import Observation
import SwiftUI

@MainActor @Observable
final class SidebarModel {
  private let repository: NavigationPreferencesRepository
  var preferences: NavigationPreferences {
    didSet { repository.save(preferences) }
  }
  init(repository: NavigationPreferencesRepository = .init()) {
    self.repository = repository
    preferences = repository.load()
  }
}
