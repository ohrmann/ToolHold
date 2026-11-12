// Vendored MIT: ajevans99/swift-json-schema @ 8d314b50; see ThirdPartyNotices/SwiftJSONSchema.

extension JSONValue {
  /// JSON Schema's integer type is mathematical, independent of JSON number storage.
  internal var isMathematicalInteger: Bool {
    numberLiteral?.isInteger == true
  }

  /// An exactly representable Swift integer, without changing the stored JSON value.
  internal var exactInteger: Int? {
    integer
  }
}
