// Vendored MIT: ajevans99/swift-json-schema @ 8d314b50; see ThirdPartyNotices/SwiftJSONSchema.
import Foundation

protocol CoreKeyword: Keyword {}

extension CoreKeyword {
  internal static var vocabulary: String {
    "https://json-schema.org/draft/2020-12/vocab/core"
  }
}

protocol IdentifierKeyword: CoreKeyword {
  func processIdentifier()
}

extension Keywords {
  /// https://json-schema.org/draft/2020-12/json-schema-core#name-the-id-keyword
  internal struct Identifier: IdentifierKeyword {
    internal static let name = "$id"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    func processIdentifier() {}

    func processSubschema(baseURI: URL) -> URL {
      guard let string = value.string, let newURL = URL(string: string, relativeTo: baseURI) else {
        return baseURI
      }

      if context.context.dialect == .draft7, let fragment = newURL.absoluteURL.fragment, !fragment.isEmpty {
        context.context.registerAnchor(newURL.absoluteURL, at: context.location.dropLast())
        context.context.registerIdentifier(newURL.absoluteURL, location: .init(document: context.uri.withoutFragment ?? context.uri, pointer: context.location.dropLast()))
        return newURL.absoluteURL
      }
      let documentURL = context.uri.withoutFragment ?? context.uri
      context.context.registerIdentifier(
        newURL.absoluteURL,
        location: .init(
          document: documentURL,
          pointer: context.location.dropLast()
        )
      )

      return newURL.absoluteURL
    }
  }

  internal struct Defs: IdentifierKeyword {
    internal static let name = "$defs"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    func processIdentifier() {
      guard case .object(let object) = value else { return }
      for (key, value) in object {
        // It is important to process defs to update context
        let subschemaLocation = context.location.appending(.key(key))
        _ = try? Schema(
          rawSchema: value,
          location: subschemaLocation,
          context: context.context,
          baseURI: context.uri
        )
      }
    }
  }

  internal struct Anchor: IdentifierKeyword {
    internal static let name = "$anchor"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    func processIdentifier() {
      guard let anchorName = value.string else { return }
      var components = URLComponents(url: context.uri, resolvingAgainstBaseURL: true)
      components?.fragment = anchorName
      guard let newURL = components?.url else { return }
      let location = context.location.dropLast()
      context.context.registerAnchor(newURL, at: location)
    }
  }

  internal struct DynamicAnchor: IdentifierKeyword {
    internal static let name = "$dynamicAnchor"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    func processIdentifier() {
      guard let anchorName = value.string else { return }
      var components = URLComponents(url: context.uri, resolvingAgainstBaseURL: true)
      components?.fragment = anchorName
      guard let newURL = components?.url else { return }
      let location = context.location.dropLast()
      context.context.registerAnchor(newURL, at: location)
      context.context.registerDynamicAnchor(anchorName, at: location, baseURI: context.uri)
    }
  }
}
