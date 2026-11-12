// Vendored MIT: ajevans99/swift-json-schema @ 8d314b50; see ThirdPartyNotices/SwiftJSONSchema.
import Foundation

protocol ReferenceKeyword: CoreKeyword {
  func validate(
    _ input: JSONValue,
    at instanceLocation: JSONPointer,
    using annotations: inout AnnotationContainer,
    with context: SchemaEngineContext,
    baseURI: URL?
  ) throws(ValidationIssue)
}

extension Keywords {
  internal struct Reference: ReferenceKeyword {
    internal static let name = "$ref"

    internal let value: JSONValue
    internal let context: KeywordContext
    private let referenceURI: String
    private let resolver: ReferenceResolver

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.referenceURI = value.string ?? ""
      self.resolver = ReferenceResolver(
        context: context.context,
        referenceURI: referenceURI,
        location: context.location,
        baseURI: context.uri
      )
    }

    func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer,
      with context: SchemaEngineContext,
      baseURI: URL?
    ) throws(ValidationIssue) {
      let schema: Schema
      do {
        schema = try resolver.resolveSchema(for: referenceURI, isDynamic: false)
      } catch let error as ValidationIssue {
        throw error
      } catch let error as ReferenceResolverError {
        SchemaRuntime.current?.fail(.unresolvedReference)
        throw .invalidReference(error.description)
      } catch {
        throw .invalidReference("Unable to resolve schema -- \(error)")
      }

      var refAnnotations = AnnotationContainer()
      let result = SchemaEvaluation.$referenceKeyword.withValue(Self.name) {
        schema.validate(input, at: instanceLocation, annotations: &refAnnotations)
      }
      if let evaluationErrors = result.evaluationErrors, !evaluationErrors.isEmpty {
        throw .evaluationFailed(
          errors: evaluationErrors.map {
            $0.prefixedKeywordLocation(with: self.context.location, removingBase: schema.location)
          }
        )
      }
      if !result.isValid {
        let prefixedErrors =
          result.errors?
          .map {
            $0.prefixedKeywordLocation(with: self.context.location, removingBase: schema.location)
          } ?? []
        throw ValidationIssue.referenceValidationFailure(
          ref: referenceURI,
          errors: prefixedErrors
        )
      }
      annotations.merge(refAnnotations)
    }
  }

  internal struct DynamicReference: ReferenceKeyword {
    internal static let name = "$dynamicRef"

    internal let value: JSONValue
    internal let context: KeywordContext
    private let referenceURI: String
    private let resolver: ReferenceResolver

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.referenceURI = value.string ?? ""
      self.resolver = ReferenceResolver(
        context: context.context,
        referenceURI: referenceURI,
        location: context.location,
        baseURI: context.uri
      )
    }

    func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer,
      with context: SchemaEngineContext,
      baseURI: URL?
    ) throws(ValidationIssue) {
      let schema: Schema
      do {
        schema = try resolver.resolveSchema(for: referenceURI, isDynamic: true)
      } catch let error as ValidationIssue {
        throw error
      } catch let error as ReferenceResolverError {
        SchemaRuntime.current?.fail(.unresolvedReference)
        throw .invalidReference(error.description)
      } catch {
        throw .invalidReference("Unable to resolve schema -- \(error)")
      }

      var refAnnotations = AnnotationContainer()
      let result = SchemaEvaluation.$referenceKeyword.withValue(Self.name) {
        schema.validate(input, at: instanceLocation, annotations: &refAnnotations)
      }
      if let evaluationErrors = result.evaluationErrors, !evaluationErrors.isEmpty {
        throw .evaluationFailed(
          errors: evaluationErrors.map {
            $0.prefixedKeywordLocation(with: self.context.location, removingBase: schema.location)
          }
        )
      }
      if !result.isValid {
        let prefixedErrors =
          result.errors?
          .map {
            $0.prefixedKeywordLocation(with: self.context.location, removingBase: schema.location)
          } ?? []
        throw ValidationIssue.referenceValidationFailure(
          ref: referenceURI,
          errors: prefixedErrors
        )
      }
      annotations.merge(refAnnotations)
    }
  }
}

extension URL {
  /// Returns the URL without the fragment part (everything before the `#`)
  var withoutFragment: URL? {
    var components = URLComponents(url: self, resolvingAgainstBaseURL: true)
    components?.fragment = nil  // Remove the fragment part
    return components?.url  // Rebuild the URL without the fragment
  }
}

enum ReferenceResolverError: Error, CustomStringConvertible {
  case invalidReferenceURI(String)
  case metaSchemaLoadFailed(Error)
  case unresolvedReference(URL)

  var description: String {
    switch self {
    case .invalidReferenceURI(let uri):
      return "Invalid reference URI: \(uri)"
    case .metaSchemaLoadFailed(let error):
      return "Failed to load metaschema: \(error)"
    case .unresolvedReference(let url):
      return "Unable to resolve $ref '\(url.absoluteString)'"
    }
  }
}

struct ReferenceResolver {
  let context: SchemaEngineContext
  let referenceURI: String
  let location: JSONPointer
  let baseURI: URL

  func resolveSchema(for refURI: String, isDynamic: Bool) throws -> Schema {
    // Resolve the reference URI against the base URI
    guard let refURL = URL(string: refURI, relativeTo: baseURI)?.absoluteURL else {
      throw ReferenceResolverError.invalidReferenceURI(refURI)
    }

    let dynamicFragment = refURL.fragment ?? ""
    if isDynamic, !dynamicFragment.isEmpty || context.dialect == .draft2019_09 {
      let fragment = dynamicFragment
      // Per JSON Schema 2020-12 §8.2.3.2, a `$dynamicRef` only triggers
      // dynamic-scope traversal if the reference's INITIAL TARGET resource
      // (the resource that `$dynamicRef` would land in when treated as a
      // regular `$ref`) also defines a matching `$dynamicAnchor`
      // ("bookending"). If not, the reference behaves like a regular `$ref`
      // to a same-named `$anchor`.
      //
      // We detect bookending by checking whether the resource identified by
      // `refURL` (without fragment) registered a `$dynamicAnchor` of this
      // name in `documentDynamicAnchors`.
      let targetResourceURL = refURL.withoutFragment ?? refURL
      let isBookended =
        context.documentDynamicAnchors[targetResourceURL]?[fragment] != nil
      if isBookended {
        for scope in context.dynamicScopes {
          if let entry = scope[fragment] {
            guard let document = context.documentCache[entry.document],
              let raw = document.value(at: entry.pointer)
            else {
              break
            }
            return try Schema(
              rawSchema: raw,
              location: entry.pointer,
              context: context,
              baseURI: entry.baseURI
            )
          }
        }
      }
    }

    // Fallback to regular reference resolution
    // Attempt to retrieve the schema from cache or resolve it
    let schema = try schema(for: refURL)
    return schema
  }

  private func schema(for refURL: URL) throws -> Schema {
    let referenceURL = refURL.withoutFragment ?? refURL
    var fragment = refURL.fragment(percentEncoded: false)

    if refURL.scheme == "urn", let range = referenceURI.range(of: "#") {
      fragment = String(referenceURI.suffix(from: range.upperBound))
    }

    // Draft-07 permits a location-independent $id outside the retrieval document URI.
    if context.dialect == .draft7, fragment?.isEmpty == false,
       let identified = try resolveIdentifier(for: refURL) { return identified }
    // Fetch the base schema
    let baseSchema = try fetchSchema(for: referenceURL)

    if let resolved = try resolveFragmentOrAnchor(
      for: refURL,
      fragment: fragment,
      in: baseSchema
    ) {
      return resolved
    }

    if let fragment, !fragment.isEmpty {
      throw ReferenceResolverError.unresolvedReference(refURL)
    }
    return baseSchema
  }

  private func fetchSchema(for referenceURL: URL) throws -> Schema {
    if let meta = try loadMetaSchemaIfNeeded(referenceURL) { return meta }
    if let cached = cachedSchema(for: referenceURL) { return cached }
    if let identified = try resolveIdentifier(for: referenceURL) { return identified }
    if let remote = try loadRemoteSchema(for: referenceURL) { return remote }
    if let workaround = try resolveURNWorkaround(for: referenceURL) { return workaround }
    SchemaRuntime.current?.fail(.unresolvedReference)
    throw ReferenceResolverError.unresolvedReference(referenceURL)
  }

  private func loadMetaSchemaIfNeeded(_ referenceURL: URL) throws -> Schema? {
    guard context.dialect.rawValue == referenceURL.absoluteString else { return nil }
    do {
      return try context.dialect.loadMetaSchema()
    } catch {
      throw ReferenceResolverError.metaSchemaLoadFailed(error)
    }
  }

  private func cachedSchema(for referenceURL: URL) -> Schema? {
    context.schemaCache[referenceURL.absoluteString]
  }

  private func resolveIdentifier(for referenceURL: URL) throws -> Schema? {
    guard let identifierLocation = context.identifierRegistry[referenceURL] else { return nil }
    guard let document = context.documentCache[identifierLocation.document],
      let value = document.value(at: identifierLocation.pointer)
    else {
      SchemaRuntime.current?.fail(.unresolvedReference)
    throw ReferenceResolverError.unresolvedReference(referenceURL)
    }
    let schema = try Schema(
      rawSchema: value,
      location: identifierLocation.pointer,
      context: context,
      baseURI: identifierLocation.document
    )
    context.cacheSchema(schema, at: referenceURL.absoluteString)
    return schema
  }

  private func loadRemoteSchema(for referenceURL: URL) throws -> Schema? {
    guard let rawSchema = context.remoteSchemaStorage[referenceURL.absoluteString] else {
      return nil
    }
    let schema = try Schema(
      rawSchema: rawSchema,
      location: .init(),
      context: context,
      baseURI: referenceURL
    )
    let uri = (schema.schema as? ObjectSchema)?.uri?.absoluteString ?? referenceURL.absoluteString
    context.cacheSchema(schema, at: uri)
    return schema
  }

  private func resolveURNWorkaround(for referenceURL: URL) throws -> Schema? {
    guard referenceURL.scheme == "urn",
      referenceURI.hasPrefix("#") || referenceURI.hasPrefix(baseURI.absoluteString)
    else { return nil }
    guard let identifierLocation = context.identifierRegistry[baseURI],
      let document = context.documentCache[identifierLocation.document],
      let value = document.value(at: identifierLocation.pointer)
    else {
      SchemaRuntime.current?.fail(.unresolvedReference)
    throw ReferenceResolverError.unresolvedReference(referenceURL)
    }
    let schema = try Schema(
      rawSchema: value,
      location: identifierLocation.pointer,
      context: context,
      baseURI: identifierLocation.document
    )
    context.cacheSchema(schema, at: referenceURL.absoluteString)
    return schema
  }

  private func resolveFragmentOrAnchor(
    for referenceURL: URL,
    fragment: String?,
    in baseSchema: Schema
  ) throws -> Schema? {
    if let anchorLocation = context.anchors[referenceURL] {
      return try resolveSchemaFragment(for: referenceURL, pointer: anchorLocation, in: baseSchema)
    }
    if let fragment, !fragment.isEmpty {
      guard fragment.hasPrefix("/") else {
        SchemaRuntime.current?.fail(.unresolvedReference)
    throw ReferenceResolverError.unresolvedReference(referenceURL)
      }
      let pointer = JSONPointer(from: fragment)
      return try resolveSchemaFragment(for: referenceURL, pointer: pointer, in: baseSchema)
    }
    return nil
  }

  private func resolveSchemaFragment(
    for referenceURL: URL,
    pointer: JSONPointer,
    in schema: Schema
  ) throws -> Schema? {
    let adjustedPointer = pointer.relative(toBase: schema.location)

    guard let objectSchema = schema.schema as? ObjectSchema else { return nil }
    guard
      let subRawSchema =
        JSONValue.object(
          OrderedDictionary(
            uniqueKeysWithValues: objectSchema.schemaValue.map { ($0.key, $0.value) }
          )
        )
        .value(at: adjustedPointer)
    else {
      return nil
    }
    var inheritedURI = objectSchema.uri ?? schema.documentURL
    var ancestor = schema.rawSchema
    for component in adjustedPointer.path.dropLast() {
      guard let next = ancestor.value(at: JSONPointer(path: [component])) else { break }
      ancestor = next
      if let id = ancestor.object?["$id"]?.string,
         !(context.dialect == .draft7 && ancestor.object?["$ref"] != nil),
         let url = URL(string: id, relativeTo: inheritedURI)?.absoluteURL { inheritedURI = url }
    }
    return try Schema(rawSchema: subRawSchema, location: pointer, context: context, baseURI: inheritedURI)
  }
}
