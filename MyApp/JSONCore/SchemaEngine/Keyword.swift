// Vendored MIT: ajevans99/swift-json-schema @ 8d314b50; see ThirdPartyNotices/SwiftJSONSchema.
import Foundation

public typealias KeywordIdentifier = String

internal protocol Keyword: Sendable {
  /// The name of the keyword, such as `type` or `minLength`.
  static var name: KeywordIdentifier { get }

  /// The vocabulary URI that defines this keyword.
  static var vocabulary: String { get }

  var value: JSONValue { get }
  var context: KeywordContext { get }

  init(value: JSONValue, context: KeywordContext)
}

internal struct KeywordContext {
  let location: JSONPointer
  let context: SchemaEngineContext
  let uri: URL

  internal init(
    location: JSONPointer = .init(),
    context: SchemaEngineContext = .init(dialect: .draft2020_12),
    uri: URL = .init(fileURLWithPath: #file)
  ) {
    self.location = location
    self.context = context
    self.uri = uri
  }
}

extension KeywordContext {
  func absoluteKeywordLocation(for pointer: JSONPointer? = nil) -> URL? {
    let pointer = pointer ?? location
    return pointer.absoluteLocation(relativeTo: uri)
  }
}
