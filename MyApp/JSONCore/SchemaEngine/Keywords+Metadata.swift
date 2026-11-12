// Vendored MIT: ajevans99/swift-json-schema @ 8d314b50; see ThirdPartyNotices/SwiftJSONSchema.
/// https://json-schema.org/draft/2020-12/meta/meta-data
protocol MetadataKeyword: Keyword, AnnotationProducingKeyword where AnnotationValue == JSONValue {}

extension MetadataKeyword {
  internal static var vocabulary: String {
    "https://json-schema.org/draft/2020-12/vocab/meta-data"
  }

  internal func recordAnnotation(
    at instanceLocation: JSONPointer,
    using annotations: inout AnnotationContainer
  ) {
    annotations.insert(keyword: self, at: instanceLocation, value: value)
  }
}

protocol ContentKeyword: Keyword {}

extension ContentKeyword {
  internal static var vocabulary: String {
    "https://json-schema.org/draft/2020-12/vocab/content"
  }
}

extension Keywords {
  internal struct Title: MetadataKeyword {
    internal static let name = "title"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }

  internal struct Description: MetadataKeyword {
    internal static let name = "description"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }

  internal struct Default: MetadataKeyword {
    internal static let name = "default"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }

  internal struct Deprecated: MetadataKeyword {
    internal static let name = "deprecated"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }

  internal struct ReadOnly: MetadataKeyword {
    internal static let name = "readOnly"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }

  internal struct WriteOnly: MetadataKeyword {
    internal static let name = "writeOnly"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }

  internal struct Examples: MetadataKeyword {
    internal static let name = "examples"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }
}

extension Keywords {
  internal struct ContentEncoding: ContentKeyword {
    internal static let name = "contentEncoding"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }

  internal struct ContentMediaType: ContentKeyword {
    internal static let name = "contentMediaType"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }

  internal struct ContentSchema: ContentKeyword {
    internal static let name = "contentSchema"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }
  }
}
