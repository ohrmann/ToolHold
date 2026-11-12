// Vendored MIT: ajevans99/swift-json-schema @ 8d314b50; see ThirdPartyNotices/SwiftJSONSchema.
/// Namespace for `Keyword` definitions.
internal enum Keywords {
  /// https://json-schema.org/draft/2020-12/json-schema-core#name-the-schema-keyword
  internal struct SchemaKeyword: CoreKeyword {
    internal static let name = "$schema"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    func processIdentifier(into context: inout SchemaEngineContext) { context.dialect = .draft2020_12 }

    func resolvedVocabularies() -> Set<String>? {
      guard let schemaURI = value.string else { return nil }
      if let rawSchema = context.context.remoteSchemaStorage[schemaURI],
        let vocabObject = rawSchema.object?[Vocabulary.name]?.object
      {
        return Set(vocabObject.keys)
      }
      return nil
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#name-the-vocabulary-keyword
  internal struct Vocabulary: CoreKeyword {
    internal static let name = "$vocabulary"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    /// Validates that all required vocabularies are supported
    func validateVocabularies() throws(SchemaIssue) {
      guard let vocabObject = value.object else {
        throw .invalidVocabularyFormat
      }

      let supportedVocabularies = context.context.dialect.supportedVocabularies

      for (vocabularyURI, required) in vocabObject {
        guard let isRequired = required.boolean else {
          throw .invalidVocabularyFormat
        }

        if isRequired && !supportedVocabularies.contains(vocabularyURI) {
          throw .unsupportedRequiredVocabulary(vocabularyURI)
        }
      }
    }

    /// Returns the set of active vocabularies (those listed with any value, true or false)
    func getActiveVocabularies() -> Set<String>? {
      guard let vocabObject = value.object else {
        return nil
      }

      var activeVocabularies = Set<String>()
      for (vocabularyURI, _) in vocabObject {
        activeVocabularies.insert(vocabularyURI)
      }

      return activeVocabularies
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#name-comments-with-comment
  internal struct Comment: CoreKeyword {
    internal static let name = "$comment"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }
}
