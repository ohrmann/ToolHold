// Vendored MIT: ajevans99/swift-json-schema @ 8d314b50; see ThirdPartyNotices/SwiftJSONSchema.
protocol ReservedKeyword: Keyword {}

extension ReservedKeyword {
  internal static var vocabulary: String {
    // These are not part of any specific vocabulary in 2020-12
    // They are legacy keywords that may not have vocabulary restrictions
    ""
  }
}

extension Keywords {
  internal struct Definitions: IdentifierKeyword {
    internal static let name = "definitions"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
    func processIdentifier() { Keywords.Defs(value: value, context: context).processIdentifier() }
  }

  internal struct Dependencies: ReservedKeyword {
    internal static let name = "dependencies"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }

  internal struct RecursiveAnchor: ReservedKeyword {
    internal static let name = "$recursiveAnchor"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }

  internal struct RecursiveReference: ReservedKeyword {
    internal static let name = "$recursiveRef"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }
}
