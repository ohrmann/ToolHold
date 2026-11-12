// Vendored MIT: ajevans99/swift-json-schema @ 8d314b50; see ThirdPartyNotices/SwiftJSONSchema.
import Foundation

// swift-format-ignore: AlwaysUseLowerCamelCase
public enum Dialect: String, Hashable, Sendable {
  case draft2020_12 = "https://json-schema.org/draft/2020-12/schema"
  case draft2019_09 = "https://json-schema.org/draft/2019-09/schema"
  case draft7 = "http://json-schema.org/draft-07/schema"
  //  case draft6
  //  case draft5

  init?(uri: String) {
    self.init(rawValue: uri.hasSuffix("#") ? String(uri.dropLast()) : uri)
  }

  var title: String { switch self { case .draft2020_12: "Draft 2020-12"; case .draft2019_09: "Draft 2019-09"; case .draft7: "Draft-07" } }
  var family: String { self == .draft2019_09 ? "2019-09" : "2020-12" }
  /// The vocabularies supported by this dialect.
  internal var supportedVocabularies: Set<String> {
    switch self {
    case .draft7: []
    case .draft2019_09: Set(["core", "applicator", "validation", "meta-data", "format", "content"].map { "https://json-schema.org/draft/2019-09/vocab/" + $0 })
    case .draft2020_12:
      [
        "https://json-schema.org/draft/2020-12/vocab/core",
        "https://json-schema.org/draft/2020-12/vocab/applicator",
        "https://json-schema.org/draft/2020-12/vocab/unevaluated",
        "https://json-schema.org/draft/2020-12/vocab/validation",
        "https://json-schema.org/draft/2020-12/vocab/meta-data",
        "https://json-schema.org/draft/2020-12/vocab/format-annotation",
        "https://json-schema.org/draft/2020-12/vocab/content",
      ]
    }
  }

  /// Returns keywords filtered by active vocabularies. If no active vocabularies are specified, returns all keywords.
  func keywords(activeVocabularies: Set<String>? = nil) -> [any Keyword.Type] {
    let allKeywords = keywords
    if self == .draft7 { return allKeywords }

    guard let activeVocabs = activeVocabularies, !activeVocabs.isEmpty else {
      return allKeywords
    }

    return allKeywords.filter { keywordType in
      var vocabularyURI = keywordType.vocabulary
      if self == .draft2019_09 {
        vocabularyURI = vocabularyURI.replacingOccurrences(of: "/2020-12/", with: "/2019-09/")
        if vocabularyURI.hasSuffix("/unevaluated") { vocabularyURI = "https://json-schema.org/draft/2019-09/vocab/applicator" }
        if vocabularyURI.hasSuffix("/format-annotation") { vocabularyURI = "https://json-schema.org/draft/2019-09/vocab/format" }
      }
      // Include keywords that have no vocabulary (empty string) or whose vocabulary is active
      return vocabularyURI.isEmpty || activeVocabs.contains(vocabularyURI)
    }
  }

  /// The supported keywords by dialect.
  /// Order matters as some keywords require annoation results of others.
  /// In the future, keywords should define their own dependencies and order should be determined by a dependency graph algorithm.
  var keywords: [any Keyword.Type] {
    switch self {
    case .draft7, .draft2019_09:
      let omitted: Set<String> = self == .draft7
        ? ["$vocabulary", "$anchor", "$dynamicRef", "$dynamicAnchor", "$recursiveRef", "$recursiveAnchor", "$defs", "prefixItems", "items", "dependencies", "dependentRequired", "dependentSchemas", "unevaluatedItems", "unevaluatedProperties", "minContains", "maxContains"]
        : ["$dynamicRef", "$dynamicAnchor", "prefixItems", "items", "dependencies", "$recursiveRef", "$recursiveAnchor"]
      let base = Dialect.draft2020_12.keywords.filter { !omitted.contains($0.name) }
      let end = base.filter { $0.name.hasPrefix("unevaluated") }
      return base.filter { !$0.name.hasPrefix("unevaluated") } + [Keywords.LegacyItems.self, Keywords.AdditionalItems.self, Keywords.LegacyDependencies.self]
        + (self == .draft2019_09 ? [Keywords.LegacyRecursiveAnchor.self, Keywords.LegacyRecursiveReference.self] : []) + end
    case .draft2020_12:
      return [
        Keywords.SchemaKeyword.self,
        Keywords.Vocabulary.self,
        Keywords.Identifier.self,
        Keywords.Reference.self,
        Keywords.Defs.self,
        Keywords.Anchor.self,

        Keywords.DynamicReference.self,
        Keywords.DynamicAnchor.self,
        Keywords.Comment.self,

        Keywords.Title.self,
        Keywords.Description.self,
        Keywords.Default.self,
        Keywords.Deprecated.self,
        Keywords.ReadOnly.self,
        Keywords.WriteOnly.self,
        Keywords.Examples.self,

        Keywords.ContentEncoding.self,
        Keywords.ContentMediaType.self,
        Keywords.ContentSchema.self,

        Keywords.PrefixItems.self,
        Keywords.Items.self,
        Keywords.Contains.self,

        Keywords.Properties.self,
        Keywords.PatternProperties.self,
        Keywords.AdditionalProperties.self,
        Keywords.PropertyNames.self,

        Keywords.AllOf.self,
        Keywords.AnyOf.self,
        Keywords.OneOf.self,
        Keywords.Not.self,

        Keywords.If.self,
        Keywords.Then.self,
        Keywords.Else.self,
        Keywords.DependentSchemas.self,

        Keywords.TypeKeyword.self,
        Keywords.Enum.self,
        Keywords.Constant.self,

        Keywords.MultipleOf.self,
        Keywords.Maximum.self,
        Keywords.ExclusiveMaximum.self,
        Keywords.Minimum.self,
        Keywords.ExclusiveMinimum.self,

        Keywords.MaxLength.self,
        Keywords.MinLength.self,
        Keywords.Pattern.self,
        Keywords.Format.self,

        Keywords.MaxItems.self,
        Keywords.MinItems.self,
        Keywords.UniqueItems.self,
        Keywords.MaxContains.self,
        Keywords.MinContains.self,

        Keywords.MaxProperties.self,
        Keywords.MinProperties.self,
        Keywords.Required.self,
        Keywords.DependentRequired.self,

        Keywords.UnevaluatedItems.self,
        Keywords.UnevaluatedProperties.self,

        Keywords.Definitions.self,
        Keywords.Dependencies.self,
        Keywords.RecursiveAnchor.self,
        Keywords.RecursiveReference.self,
      ]
    }
  }

  /// Loads the meta-schema for this dialect.
  ///
  /// The meta-schema is a schema that describes the structure and rules for
  /// schemas in this dialect. It can be used to validate whether a schema
  /// document is well-formed according to the dialect's specification.
  /// Immutable bundled JSON documents are cached; each call creates a fresh schema and context.
  ///
  /// - Returns: A `Schema` representing the meta-schema for this dialect.
  /// - Throws: `MetaSchemaError` if the meta-schema cannot be loaded.
  public func loadMetaSchema() throws -> Schema {
    let resources: MetaSchemaResources
    switch self {
    case .draft2020_12:
      resources = try Self.draft202012Resources.get()
    case .draft7: resources = try Self.draft7Resources.get()
    case .draft2019_09: resources = try Self.draft2019Resources.get()
    }
    return try Schema(
      rawSchema: resources.schema,
      context: .init(dialect: self, remoteSchema: resources.remotes),
      baseURI: resources.baseURI
    )
  }

  private struct MetaSchemaResources: Sendable {
    let schema: JSONValue
    let remotes: [String: JSONValue]
    let baseURI: URL
  }

  private static let draft202012Resources = Result {
    try loadDraft202012Resources()
  }

  private static let draft7Resources = Result { try loadResources(prefix: "draft7", root: "draft7-schema") }
  private static let draft2019Resources = Result { try loadResources(prefix: "draft2019-09", root: "draft2019-09-schema") }
  private static func loadDraft202012Resources() throws -> MetaSchemaResources {
    try loadResources(prefix: "", root: "schema")
  }
  private static func loadResources(prefix: String, root: String) throws -> MetaSchemaResources {
    guard let url = Bundle.jsonSchemaResources.url(forResource: root, withExtension: "json") else { throw MetaSchemaError.missingResource }
    let schema = try JSONValue.parse(Data(contentsOf: url))
    let base = URL(string: schema.object!["$id"]!.string!)!
    var remotes: [String: JSONValue] = [:]
    for url in Bundle.jsonSchemaResources.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [] {
      let u = url as URL, name = u.deletingPathExtension().lastPathComponent
      if prefix.isEmpty ? !name.hasPrefix("draft") : name.hasPrefix(prefix) {
        let value = try JSONValue.parse(Data(contentsOf: u))
        if let id = value.object?["$id"]?.string { remotes[URL(string: id)!.withoutFragment!.absoluteString] = value }
      }
    }
    return .init(schema: schema, remotes: remotes, baseURI: base.withoutFragment!)
  }

  /// Validates a raw schema against this dialect's meta-schema.
  ///
  /// This method loads the meta-schema for the dialect and validates the provided
  /// schema against it to ensure the schema is well-formed according to the
  /// dialect's specification.
  ///
  /// - Parameter schema: The raw schema to validate, represented as a `JSONValue`.
  /// - Returns: A `ValidationResult` indicating whether the schema is valid.
  /// - Throws: An error if the meta-schema cannot be loaded.
  ///
  /// Example:
  /// ```swift
  /// let rawSchema: JSONValue = [
  ///   "type": "object",
  ///   "properties": [
  ///     "name": ["type": "string"]
  ///   ]
  /// ]
  /// let result = try Dialect.draft2020_12.validateSchema(rawSchema)
  /// print(result.isValid) // true
  /// ```
  public func validateSchema(_ schema: JSONValue) throws -> ValidationResult {
    let metaSchema = try loadMetaSchema()
    return metaSchema.validate(schema)
  }
}

public enum MetaSchemaError: Error {
  case invalidBaseURI
  case missingResource
}
