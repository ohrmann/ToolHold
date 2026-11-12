// Vendored MIT: ajevans99/swift-json-schema @ 8d314b50; see ThirdPartyNotices/SwiftJSONSchema.
public enum SchemaIssue: Error, Equatable {
  case schemaShouldBeBooleanOrObject
  case unsupportedRequiredVocabulary(String)
  case invalidVocabularyFormat
  case runtimeLimit
  case missingRootRawSchema
}
