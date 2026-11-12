import Foundation
import Testing

@testable import NavigationCore

#if canImport(AppKit)
  import AppKit
#endif

struct NavigationCoreTests {
  @Test func compactTitlesPreserveFullCatalogSearchAndIdentity() {
    for id in [ToolID.t020, .t069, .t070, .t071, .t072, .t073, .t074, .t075, .t076] {
      let tool = ToolCatalog.tool(id)
      #expect(!tool.compactNavigationTitle.isEmpty)
      #expect(tool.compactNavigationTitle.count < tool.title.count)
      #expect(ToolCatalog.matches(id, query: tool.title))
      #expect(ToolCatalog.matches(id, query: id.rawValue))
      #expect(tool.displayName == tool.title)
    }
    #expect(ToolCatalog.tool(.t020).compactNavigationTitle == "JWT Inspector")
    #expect(ToolCatalog.tool(.t069).compactNavigationTitle == "Certificate Generator")
  }
  @Test func canonicalCatalogMatchesDocumentation() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let text = try String(
      contentsOf: root.appendingPathComponent("docs/TOOL_CATALOG.md"), encoding: .utf8)
    var categoryIndex = -1
    var documented: [(String, String, ToolCategory, String)] = []
    for line in text.components(separatedBy: .newlines) {
      if line.hasPrefix("### "), line.range(of: #"\(\d+\)$"#, options: .regularExpression) != nil {
        categoryIndex += 1
        let title = String(line.dropFirst(4)).replacingOccurrences(
          of: #" \(\d+\)$"#, with: "", options: .regularExpression)
        #expect(title == ToolCategory.allCases[categoryIndex].title)
      }
      if line.hasPrefix("| T-") {
        let fields = line.components(separatedBy: "|").map {
          $0.trimmingCharacters(in: .whitespaces)
        }
        documented.append(
          (fields[1], fields[2], ToolCategory.allCases[categoryIndex], fields[5]))
      }
    }
    #expect(documented.count == 78)
    #expect(ToolCatalog.tools.count == documented.count)
    #expect(Set(ToolCatalog.tools.map(\.id)).count == 78)
    #expect(ToolID.allCases.count == 78)
    #expect(Set(ToolCatalog.tools.map(\.id)) == Set(ToolID.allCases))
    #expect(ToolCategory.allCases.count == 8)
    for (tool, entry) in zip(ToolCatalog.tools, documented) {
      #expect(tool.id.rawValue == entry.0)
      #expect(tool.title == entry.1)
      #expect(tool.category == entry.2)
      #expect(tool.shortDescription == entry.3)
      #expect(!tool.symbol.isEmpty)
    }
    #expect(ToolCatalog.tools.filter(\.isImplemented).map(\.id) == [.t001, .t002, .t003, .t004, .t005, .t006, .t007, .t008, .t009, .t010, .t011, .t012, .t013, .t014, .t015, .t016, .t017, .t018, .t019, .t020, .t078, .t021, .t022, .t023, .t024, .t025, .t026, .t027, .t028, .t029, .t030, .t031, .t032, .t033, .t034, .t035, .t036, .t037, .t038, .t039, .t040, .t041, .t042, .t043, .t044, .t045, .t046, .t047, .t048, .t049, .t050, .t051, .t052, .t053, .t054, .t055, .t056, .t077, .t057, .t058, .t059, .t060, .t061, .t062, .t063, .t064, .t065, .t066, .t067, .t068, .t069, .t070, .t071, .t072, .t073, .t074, .t075, .t076])
    #expect(ToolCatalog.tools.filter { $0.release == .ga }.count == 47)
    #expect(ToolCatalog.tools.filter { $0.release == .gated }.count == 2)
    #expect(ToolCatalog.tools.filter { $0.release == .later }.count == 29)
  }

  @Test func treeRouteRestoresWithoutChangingCatalogOrPlaceholder() {
    var preferences = NavigationPreferences.defaults
    for id in [ToolID.t002, .t003, .t004, .t005, .t006, .t007, .t008, .t009, .t010, .t011, .t012, .t013, .t014, .t015, .t016, .t017, .t018, .t019, .t020, .t078, .t021, .t022, .t023, .t024, .t025, .t026, .t027, .t028, .t029] {
      preferences.selectedTool = id
      #expect(preferences.reconciled().selectedTool == id)
      #expect(ToolCatalog.tool(id).isImplemented)
    }
    #expect(ToolCatalog.tool(.t077).isImplemented)
    #expect(ToolCatalog.tool(.t078).isImplemented)
    #expect(ToolCatalog.tools.count == 78)
  }

  @Test func everyToolHasAConcisePurposeDescription() {
    for tool in ToolCatalog.tools {
      let description = tool.shortDescription
      #expect(description == description.trimmingCharacters(in: .whitespacesAndNewlines))
      #expect((2...4).contains(description.split(separator: " ").count))
      #expect(!description.contains(where: { $0.isNewline || $0 == "\t" }))
      #expect(description.lowercased() != tool.displayName.lowercased())
      #expect(!description.lowercased().contains("not implemented"))
    }
    #expect(ToolCatalog.tool(.t001).shortDescription == "Format and validate")
    #expect(ToolCatalog.tool(.t020).shortDescription == "Inspect token claims")
    // Purpose metadata doesn't silently broaden the existing search contract.
    #expect(!ToolCatalog.matches(.t003, query: "structures"))
  }

  @Test func modelGeneratorRenamePreservesExistingNavigationIdentity() throws {
    let suite = "models-navigation-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let repository = NavigationPreferencesRepository(defaults: defaults)
    var legacy = NavigationPreferences.defaults
    legacy.categoryOrder.reverse()
    legacy.toolOrder["dataJSON"]?.reverse()
    legacy.favorites = ["T-011", "T-001"]
    legacy.selectedTool = .t011
    legacy.expandedCategories = ["dataJSON"]
    repository.save(legacy)
    let restored = repository.load()
    #expect(restored.categoryOrder == legacy.categoryOrder)
    #expect(restored.toolOrder == legacy.toolOrder && restored.favorites == legacy.favorites)
    #expect(restored.selectedTool == .t011 && restored.expandedCategories == legacy.expandedCategories)
    #expect(ToolCatalog.tool(.t011).title == "JSON → Models")
    for query in ["Swift", "TypeScript", "C#", ".NET", "Java", "Kotlin"] {
      #expect(ToolCatalog.matches(.t011, query: query))
    }
  }

  @Test func jwtEncoderCatalogAndLegacyOrderRemainCompatible() throws {
    let tool = ToolCatalog.tool(.t078)
    #expect(tool.title == "JWT Encoder")
    #expect(tool.shortDescription == "Encode token claims")
    #expect(tool.category == .encoders && tool.release == .later && tool.isImplemented)
    let defaultOrder = ToolCatalog.tools(in: .encoders)
    let decoderIndex = try #require(defaultOrder.firstIndex(of: .t020))
    #expect(defaultOrder[decoderIndex + 1] == .t078)
    for query in ["JWT Encoder", "T-078", "jwt encode", "генерация токен"] {
      #expect(ToolCatalog.matches(.t078, query: query))
    }

    let suite = "developer-toolbox-jwt-catalog-test-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let repository = NavigationPreferencesRepository(defaults: defaults)
    var legacy = NavigationPreferences.defaults
    legacy.toolOrder["encoders"]?.removeAll { $0 == "T-078" }
    legacy.toolOrder["encoders"]?.reverse()
    legacy.categoryOrder.reverse()
    legacy.favorites = ["T-020", "T-002"]
    legacy.expandedCategories = ["encoders", "dataJSON"]
    legacy.favoritesExpanded = true
    legacy.selectedTool = .t002
    legacy.appearance = .dark
    for version in [1, 2, 3] {
      legacy.version = version
      defaults.set(try JSONEncoder().encode(legacy), forKey: "developerToolbox.navigation.v1")
      var restored = repository.load()
      var previousOrder = restored.toolOrder
      previousOrder["encoders"]?.removeAll { $0 == "T-078" }
      #expect(previousOrder == legacy.toolOrder)
      #expect(restored.toolOrder["encoders"] == legacy.toolOrder["encoders"]! + ["T-078"])
      #expect(restored.categoryOrder == legacy.categoryOrder)
      #expect(restored.favorites == legacy.favorites)
      #expect(restored.expandedCategories == legacy.expandedCategories)
      #expect(restored.favoritesExpanded && restored.appearance == .dark && restored.selectedTool == .t002)
      restored.selectedTool = .t078
      #expect(restored.selectedTool == .t078) // Working encoder keeps the same stable catalog ID.
      restored.toggleFavorite(.t078)
      #expect(restored.visibleFavorites(query: "JWT Encoder") == [.t078])
      let moved = restored.move("T-078", in: .tools(.encoders), before: "T-020")
      let foreignMove = restored.move("T-078", in: .tools(.dataJSON), before: "T-001")
      #expect(moved)
      #expect(!foreignMove)
      restored.selectedTool = .t002
      repository.save(restored)
      #expect(repository.load() == restored)
      restored.resetOrder()
      #expect(restored.tools(in: .encoders) == defaultOrder)
    }
  }

  @Test func mjmlUsesExistingNavigationAndReorderScopes() throws {
    let tool = ToolCatalog.tool(.t077)
    #expect(tool.id.rawValue == "T-077")
    #expect(tool.title == "MJML Editor & Preview")
    #expect(tool.shortDescription == "Build responsive emails")
    #expect(tool.category == .formatters)
    #expect(tool.release == .later)
    #expect(tool.isImplemented)
    var p = NavigationPreferences.defaults
    #expect(p.tools(in: .formatters)[4] == .t077)
    for query in ["MJML", "responsive email", "T-077", "рассылка"] {
      #expect(p.visibleTools(in: .formatters, query: query) == [.t077])
      #expect(p.visibleCategories(query: query) == [.formatters])
    }
    p.selectedTool = .t077
    #expect(p.selectedTool == .t077)  // Live selection opens the MJML workspace.
    p.toggleFavorite(.t001)
    p.toggleFavorite(.t077)
    #expect(p.visibleFavorites(query: "mjml") == [.t077])
    #expect(p.tools(in: .formatters).contains(.t077))
    var categoryDrag = try #require(
      NavigationReorderDraft(scope: .tools(.formatters), id: "T-077", preferences: p))
    categoryDrag.preview(over: "T-053")
    let reordered = try #require(categoryDrag.applying(to: p))
    #expect(reordered.tools(in: .formatters).first == .t077)
    #expect(p.tools(in: .formatters)[4] == .t077)  // Preview never mutates saved order.
    var favoriteDrag = try #require(
      NavigationReorderDraft(scope: .favorites, id: "T-077", preferences: p))
    favoriteDrag.preview(over: "T-001")
    #expect(favoriteDrag.applying(to: p)?.favoriteIDs == [.t077, .t001])
    let foreignSource = p.move("T-077", in: .tools(.dataJSON), before: "T-001")
    let foreignTarget = p.move("T-077", in: .tools(.formatters), before: "T-001")
    let filteredMove = p.move("T-077", in: .tools(.formatters), before: "T-053", query: "mjml")
    #expect(!foreignSource)
    #expect(!foreignTarget)
    #expect(!filteredMove)
    p.toggleFavorite(.t077)
    #expect(p.favoriteIDs == [.t001])
    // Implemented MJML restores its route, without restoring working source.
    #expect(p.reconciled().selectedTool == .t077)
  }

  @Test func oldSettingsAppendMJMLWithoutResettingExistingOrders() throws {
    let suite = "developer-toolbox-mjml-migration-test-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let repository = NavigationPreferencesRepository(defaults: defaults)
    var legacy = NavigationPreferences.defaults
    legacy.toolOrder["formatters"] = [
      "T-053", "T-054", "T-055", "T-056", "T-057", "T-058", "T-059", "T-060",
    ]
    legacy.categoryOrder.reverse()
    legacy.toolOrder["dataJSON"]?.reverse()
    legacy.favorites = ["T-060", "T-001"]
    legacy.expandedCategories = ["text", "formatters"]
    legacy.favoritesExpanded = true
    legacy.selectedTool = .t001
    legacy.appearance = .dark
    for version in [1, 2, 3] {
      legacy.version = version
      defaults.set(try JSONEncoder().encode(legacy), forKey: "developerToolbox.navigation.v1")
      let restored = repository.load()
      #expect(restored.categoryOrder == legacy.categoryOrder)
      var previousToolOrder = restored.toolOrder
      previousToolOrder["formatters"]?.removeAll { $0 == "T-077" }
      #expect(previousToolOrder == legacy.toolOrder)
      #expect(restored.toolOrder["formatters"] == legacy.toolOrder["formatters"]! + ["T-077"])
      #expect(restored.favorites == legacy.favorites)
      #expect(restored.expandedCategories == legacy.expandedCategories)
      #expect(restored.favoritesExpanded == legacy.favoritesExpanded)
      #expect(restored.selectedTool == .t001)
      #expect(restored.appearance == .dark)
      #expect(restored.version == 3)
      repository.save(restored)
      #expect(repository.load() == restored)  // No duplicate insertion on another launch.
      var personalized = restored
      let moved = personalized.move("T-077", in: .tools(.formatters), before: "T-053")
      #expect(moved)
      personalized.toggleFavorite(.t077)
      repository.save(personalized)
      #expect(repository.load() == personalized)
      personalized.resetOrder()
      #expect(personalized.tools(in: .formatters) == [
        .t053, .t054, .t055, .t056, .t077, .t057, .t058, .t059, .t060,
      ])
      #expect(personalized.favoriteIDs.contains(.t077))
    }
  }

  @Test func categoryRenamePreservesLegacySettingsAndCatalogIdentity() throws {
    #expect(ToolCategory.formatters.rawValue == "formatters")
    #expect(ToolCategory.formatters.title == "Code & Markup")
    #expect(NavigationPreferences.defaults.categoryOrder == [
      "dataJSON", "encoders", "generators", "text", "dateNetwork", "formatters",
      "colorFiles", "certificates",
    ])
    #expect(ToolCatalog.tools.filter { $0.id != .t077 && $0.id != .t078 }.map(\.id.rawValue)
      == (1...76).map { String(format: "T-%03d", $0) })
    #expect(ToolCatalog.tools(in: .formatters) == [
      .t053, .t054, .t055, .t056, .t077, .t057, .t058, .t059, .t060,
    ])
    for id in [ToolID.t001, .t002, .t003] {
      #expect(ToolCatalog.tool(id).category == .dataJSON)
    }

    let suite = "developer-toolbox-category-rename-test-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    // Stored under the existing key, using only IDs from before the display-name change.
    let legacy = Data("""
      {
        "version": 3,
        "categoryOrder": ["formatters", "text", "dataJSON", "encoders", "generators",
                          "dateNetwork", "colorFiles", "certificates"],
        "toolOrder": {
          "formatters": ["T-060", "T-053", "T-059", "T-054", "T-055", "T-056", "T-057", "T-058"],
          "dataJSON": ["T-003", "T-001", "T-002"],
          "text": ["T-042", "T-033"]
        },
        "favorites": ["T-059", "T-003", "T-001"],
        "expandedCategories": ["formatters", "dataJSON"],
        "favoritesExpanded": true,
        "selectedToolID": "T-001",
        "appearance": "dark"
      }
      """.utf8)
    defaults.set(legacy, forKey: "developerToolbox.navigation.v1")
    let repository = NavigationPreferencesRepository(defaults: defaults)
    let restored = repository.load()
    #expect(restored.categoryOrder == [
      "formatters", "text", "dataJSON", "encoders", "generators", "dateNetwork",
      "colorFiles", "certificates",
    ])
    #expect(restored.tools(in: .formatters) == [
      .t060, .t053, .t059, .t054, .t055, .t056, .t057, .t058, .t077,
    ])
    #expect(restored.tools(in: .dataJSON).prefix(3) == [.t003, .t001, .t002])
    #expect(restored.tools(in: .text).prefix(2) == [.t042, .t033])
    #expect(restored.favoriteIDs == [.t059, .t003, .t001])
    #expect(restored.expandedCategories == ["formatters", "dataJSON"])
    #expect(restored.favoritesExpanded)
    #expect(restored.selectedTool == .t001)
    #expect(restored.appearance == .dark)
    #expect(restored.version == 3)
    repository.save(restored)
    #expect(NavigationPreferencesRepository(defaults: defaults).load() == restored)
    let encoded = try #require(defaults.data(forKey: "developerToolbox.navigation.v1"))
    let serialized = String(decoding: encoded, as: UTF8.self)
    #expect(!serialized.contains("Code & Markup"))
    #expect(!serialized.contains("Formatters & Preview"))
  }

  #if canImport(AppKit)
    @Test @MainActor func systemSymbolsExist() {
      for symbol in Set(ToolCatalog.tools.map(\.symbol) + ToolCategory.allCases.map(\.symbol)) {
        #expect(
          NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
          "Missing SF Symbol: \(symbol)")
      }
    }
  #endif

  @Test func independentExpansionAndSearchDoesNotMutateIt() {
    var preferences = NavigationPreferences.defaults
    preferences.setExpanded(.text, true)
    preferences.setExpanded(.certificates, true)
    preferences.setExpanded(.dataJSON, false)
    #expect(preferences.isExpanded(.text, query: ""))
    #expect(preferences.isExpanded(.certificates, query: ""))
    #expect(!preferences.isExpanded(.dataJSON, query: ""))
    let snapshot = preferences
    #expect(preferences.isExpanded(.dataJSON, query: "json"))
    #expect(preferences.visibleCategories(query: "json") == [.dataJSON, .encoders])
    #expect(preferences == snapshot)
    #expect(!preferences.isExpanded(.dataJSON, query: ""))
  }

  @Test func favoritesAreReferencesWithIndependentOrder() {
    var p = NavigationPreferences.defaults
    let data = p.tools(in: .dataJSON)
    p.toggleFavorite(.t003)
    p.toggleFavorite(.t001)
    #expect(p.favoriteIDs == [.t003, .t001])
    #expect(p.tools(in: .dataJSON) == data)
    let moveResult1 = p.move(ToolID.t001.rawValue, in: .favorites, before: ToolID.t003.rawValue)
    #expect(moveResult1)
    #expect(p.favoriteIDs == [.t001, .t003])
    p.toggleFavorite(.t003)
    #expect(p.favoriteIDs == [.t001])
    #expect(p.tools(in: .dataJSON).contains(.t003))
  }

  @Test func reordersAllScopesAndHandlesBoundaries() {
    var p = NavigationPreferences.defaults
    let moveResult2 = p.move(
      ToolCategory.text.rawValue, in: .categories, before: ToolCategory.dataJSON.rawValue)
    #expect(moveResult2)
    #expect(p.categories.first == .text)
    let moveResult3 = p.moveBy(1, id: ToolCategory.text.rawValue, in: .categories)
    #expect(moveResult3)
    #expect(p.categories.prefix(2) == [.dataJSON, .text])
    let moveResult4 = p.move("T-003", in: .tools(.dataJSON), before: "T-001")
    #expect(moveResult4)
    #expect(p.tools(in: .dataJSON).prefix(3) == [.t003, .t001, .t002])
    let moveResult5 = p.move("T-003", in: .tools(.dataJSON), before: nil)
    #expect(moveResult5)
    #expect(p.tools(in: .dataJSON).last == .t003)
    let moveResult6 = !p.moveBy(1, id: "T-003", in: .tools(.dataJSON))
    #expect(moveResult6)
    let moveResult7 = !p.moveBy(-1, id: "T-001", in: .tools(.dataJSON))
    #expect(moveResult7)
    let moveResult8 = !p.move("T-001", in: .tools(.dataJSON), before: "T-001")
    #expect(moveResult8)
  }

  @Test func cannotMoveBetweenCategoriesOrDuringSearch() {
    var p = NavigationPreferences.defaults
    p.toggleFavorite(.t012)
    let before = p
    let moveResult9 = !p.move("T-012", in: .tools(.dataJSON), before: "T-001")
    #expect(moveResult9)
    let moveResult10 = !p.move("T-001", in: .tools(.dataJSON), before: "T-012")
    #expect(moveResult10)
    let moveResult11 = !p.move("T-001", in: .favorites, before: nil)
    #expect(moveResult11)
    let moveResult12 = !p.move("T-002", in: .tools(.dataJSON), before: "T-001", query: "json")
    #expect(moveResult12)
    let moveResult13 = !p.moveBy(1, id: "T-001", in: .tools(.dataJSON), query: "JSON")
    #expect(moveResult13)
    let moveResult14 = !p.move(
      ToolCategory.text.rawValue, in: .categories, before: nil, query: "text")
    #expect(moveResult14)
    #expect(p == before)
  }

  @Test func filteringPreservesCustomOrderAndMatchesSynonyms() {
    var p = NavigationPreferences.defaults
    p.move("T-003", in: .tools(.dataJSON), before: "T-001")
    p.move(ToolCategory.encoders.rawValue, in: .categories, before: ToolCategory.dataJSON.rawValue)
    p.toggleFavorite(.t003)
    p.toggleFavorite(.t001)
    #expect(p.visibleTools(in: .dataJSON, query: "json").prefix(2) == [.t003, .t001])
    #expect(p.visibleCategories(query: "JSON").prefix(2) == [.encoders, .dataJSON])
    #expect(p.visibleFavorites(query: "json") == [.t003, .t001])
    #expect(p.visibleTools(in: .dataJSON, query: "beautify") == [.t001])
    #expect(p.visibleTools(in: .generators, query: "ПАРОЛЬ").contains(.t023))
    #expect(ToolCatalog.matches(.t022, query: "GUID"))
    #expect(ToolCatalog.matches(.t001, query: "json minify"))
    #expect(!ToolCatalog.matches(.t001, query: "json password"))
    #expect(p.visibleCategories(query: "no-such-tool-123").isEmpty)
    #expect(p.visibleCategories(query: " \n\t ") == p.categories)
  }

  @Test func reconcileFutureAndRemovedIDsWithoutLosingKnownOrder() {
    var p = NavigationPreferences.defaults
    p.categoryOrder = ["future-category", "text", "text", "dataJSON"]
    p.toolOrder["dataJSON"] = ["T-003", "T-999", "T-001", "T-001", "T-012"]
    p.toolOrder["future-category"] = ["T-999"]
    p.favorites = ["T-999", "T-023", "T-023", "T-003"]
    p.expandedCategories = ["text", "future-category", "text"]
    let clean = p.reconciled()
    #expect(clean.categories.prefix(2) == [.text, .dataJSON])
    #expect(clean.categories.count == 8)
    #expect(clean.tools(in: .dataJSON).prefix(3) == [.t003, .t001, .t002])
    #expect(clean.tools(in: .dataJSON).count == 11)
    #expect(!clean.tools(in: .dataJSON).contains(.t012))
    #expect(clean.favoriteIDs == [.t023, .t003])
    #expect(clean.expandedCategories == ["text"])
    #expect(clean.toolOrder["future-category"] == nil)
    #expect(clean.reconciled() == clean)
  }

  @Test func resetRestoresOrderButPreservesFavoritesAndExpansion() {
    var p = NavigationPreferences.defaults
    p.setExpanded(.certificates, true)
    p.toggleFavorite(.t023)
    p.toggleFavorite(.t001)
    p.move("T-003", in: .tools(.dataJSON), before: "T-001")
    p.move("text", in: .categories, before: "dataJSON")
    let expansion = p.expandedCategories
    p.resetOrder()
    #expect(p.categoryOrder == NavigationPreferences.defaults.categoryOrder)
    #expect(p.toolOrder == NavigationPreferences.defaults.toolOrder)
    #expect(p.favoriteIDs == [.t001, .t023])
    #expect(p.expandedCategories == expansion)
  }

  @Test func firstLaunchIsHomeWithAllSectionsCollapsed() {
    let p = NavigationPreferences.defaults
    #expect(p.selectedTool == nil)
    #expect(p.expandedCategories.isEmpty)
    #expect(!p.favoritesExpanded)
    #expect(p.favorites.isEmpty)
  }

  @Test func favoritesExpansionAndSearchAreIndependent() {
    var p = NavigationPreferences.defaults
    p.setExpanded(.text, true)
    let snapshot = p
    #expect(p.isFavoritesExpanded(query: "json"))
    #expect(p.isExpanded(.dataJSON, query: "json"))
    #expect(p == snapshot)
    #expect(!p.isFavoritesExpanded(query: ""))
    p.favoritesExpanded = true
    p.setExpanded(.text, false)
    #expect(p.isFavoritesExpanded(query: ""))
    #expect(!p.isExpanded(.text, query: ""))
  }

  @Test func previousSchemaMigratesAndRestorationRejectsUnavailableTools() throws {
    let old: [String: Any] = [
      "version": 1, "categoryOrder": ["text", "dataJSON"],
      "toolOrder": ["dataJSON": ["T-003", "T-001"]],
      "favorites": ["T-001"], "expandedCategories": ["text"],
    ]
    let restored = try JSONDecoder().decode(
      NavigationPreferences.self, from: JSONSerialization.data(withJSONObject: old)
    ).reconciled()
    #expect(restored.version == 3)
    #expect(restored.categories.first == .text)
    #expect(restored.favoriteIDs == [.t001])
    #expect(restored.expandedCategories == ["text"])
    #expect(!restored.favoritesExpanded)
    #expect(restored.selectedTool == nil)
    var p = restored
    p.selectedTool = .t001
    #expect(p.reconciled().selectedTool == .t001)
    p.selectedToolID = "T-999"
    #expect(p.reconciled().selectedTool == nil)
    p.selectedTool = .t022
    #expect(p.reconciled().selectedTool == .t022)
    p.selectedTool = .t023
    #expect(p.reconciled().selectedTool == .t023)
    p.selectedTool = .t024
    #expect(p.reconciled().selectedTool == .t024)
    for id in [ToolID.t025, .t026, .t027, .t028, .t029, .t030, .t031, .t032] {
      p.selectedTool = id; #expect(p.reconciled().selectedTool == id)
    }
    for id in [ToolID.t043, .t044, .t045, .t046, .t047, .t048, .t049, .t050, .t051, .t052] {
      p.selectedTool = id; #expect(p.reconciled().selectedTool == id)
    }
    for id in [ToolID.t053,.t054,.t055,.t056,.t077,.t057,.t058,.t059,.t060] {
      p.selectedTool=id;#expect(p.reconciled().selectedTool==id)
    }
    for id in [ToolID.t061,.t062,.t063,.t064,.t065,.t066,.t067,.t068] {
      p.selectedTool=id; #expect(p.reconciled().selectedTool==id)
    }
    for id in [ToolID.t069,.t070,.t071,.t072,.t073,.t074,.t075,.t076] {
      p.selectedTool = id; #expect(p.reconciled().selectedTool == id)
    }
    p.selectedTool = nil
    #expect(p.reconciled().selectedTool == nil)
  }

  @Test func persistedRoundTripAndCorruptDataRecovery() throws {
    let suite = "developer-toolbox-nav-test-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let repository = NavigationPreferencesRepository(defaults: defaults)
    #expect(repository.load() == .defaults)
    var p = NavigationPreferences.defaults
    p.toggleFavorite(.t001)
    p.toggleFavorite(.t030)
    p.moveBy(1, id: "T-001", in: .favorites)
    p.move("text", in: .categories, before: "dataJSON")
    p.move("T-003", in: .tools(.dataJSON), before: "T-001")
    p.setExpanded(.text, true)
    p.selectedTool = .t001
    p.favoritesExpanded = true
    repository.save(p)
    #expect(NavigationPreferencesRepository(defaults: defaults).load() == p)
    let data = try #require(defaults.data(forKey: NavigationPreferencesRepository.key))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(
      Set(object.keys) == [
        "version", "categoryOrder", "toolOrder", "favorites", "expandedCategories",
        "favoritesExpanded", "selectedToolID", "appearance",
      ])
    p.selectedTool = nil
    repository.save(p)
    #expect(repository.load().selectedTool == nil)
    #expect(repository.load().favoritesExpanded)
    defaults.set(Data("not-json".utf8), forKey: NavigationPreferencesRepository.key)
    #expect(repository.load() == .defaults)
    p.version = 99
    defaults.set(try JSONEncoder().encode(p), forKey: NavigationPreferencesRepository.key)
    #expect(repository.load() == .defaults)
  }
  @Test func dragDraftIsProvisionalUntilExplicitCommit() throws {
    let suite = "developer-toolbox-drag-test-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let repository = NavigationPreferencesRepository(defaults: defaults)
    var saved = NavigationPreferences.defaults
    saved.toggleFavorite(.t001)
    saved.toggleFavorite(.t003)
    repository.save(saved)
    for scope in [NavigationPreferences.Scope.categories, .tools(.dataJSON), .favorites] {
      let order = saved.order(in: scope)
      var draft = try #require(
        NavigationReorderDraft(scope: scope, id: order.last!, preferences: saved))
      draft.preview(over: order.first!)
      let proposed = try #require(draft.applying(to: saved))
      #expect(proposed.order(in: scope).first == order.last)
      #expect(repository.load() == saved)
      draft.preview(over: order.first!)
      #expect(draft.applying(to: saved) == proposed)
      // Dropping the draft cancels it; only committing its result changes persistence.
      var concurrentlyUpdated = saved
      concurrentlyUpdated.appearance = .dark
      concurrentlyUpdated.selectedTool = .t001
      let commit = try #require(draft.applying(to: concurrentlyUpdated))
      #expect(commit.appearance == .dark)
      #expect(commit.selectedTool == .t001)
      repository.save(commit)
      #expect(repository.load() == commit)
      repository.save(saved)
    }
  }

  @Test func dragDraftRejectsForeignIDsAndConcurrentChanges() throws {
    let saved = NavigationPreferences.defaults
    #expect(
      NavigationReorderDraft(scope: .tools(.dataJSON), id: "T-012", preferences: saved) == nil)
    var draft = try #require(
      NavigationReorderDraft(scope: .tools(.dataJSON), id: "T-003", preferences: saved))
    draft.preview(over: "T-012")
    #expect(draft.applying(to: saved) == saved)
    draft.preview(over: "T-001")
    #expect(draft.previewOrder.prefix(2) == ["T-003", "T-001"])
    draft.preview(over: nil)
    #expect(draft.previewOrder.last == "T-003")
    var changed = saved
    changed.moveBy(1, id: "T-001", in: .tools(.dataJSON))
    #expect(draft.applying(to: changed) == nil)
    #expect(saved == NavigationPreferences.defaults)
  }

  @Test func appearanceMigratesAndRoundTripsWithoutChangingNavigation() throws {
    let saved = NavigationPreferences.defaults
    #expect(saved.appearance == .system)
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
    for version in [1, 2] {
      object["version"] = version
      object.removeValue(forKey: "appearance")
      let migrated = try JSONDecoder().decode(
        NavigationPreferences.self, from: JSONSerialization.data(withJSONObject: object)
      ).reconciled()
      #expect(migrated.appearance == .system)
      #expect(migrated.version == 3)
    }
    for appearance in AppAppearance.allCases {
      var p = saved
      p.appearance = appearance
      p.selectedTool = .t001
      p.toggleFavorite(.t003)
      p.move("text", in: .categories, before: "dataJSON")
      let decoded = try JSONDecoder().decode(
        NavigationPreferences.self, from: JSONEncoder().encode(p)
      ).reconciled()
      #expect(decoded == p)
    }
    object["version"] = 3
    object["appearance"] = "future-theme"
    #expect(
      try JSONDecoder().decode(
        NavigationPreferences.self, from: JSONSerialization.data(withJSONObject: object)
      ).appearance == .system)
  }

}
