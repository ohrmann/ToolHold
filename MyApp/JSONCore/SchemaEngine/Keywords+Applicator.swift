// Vendored MIT: ajevans99/swift-json-schema @ 8d314b50; see ThirdPartyNotices/SwiftJSONSchema.

internal protocol ApplicatorKeyword: AnnotationProducingKeyword {
  func validate(
    _ input: JSONValue,
    at instanceLocation: JSONPointer,
    using annotations: inout AnnotationContainer
  ) throws(ValidationIssue)
}

extension ApplicatorKeyword {
  internal static var vocabulary: String {
    "https://json-schema.org/draft/2020-12/vocab/applicator"
  }
}

protocol UnevaluatedKeyword: ApplicatorKeyword {}

extension UnevaluatedKeyword {
  internal static var vocabulary: String {
    "https://json-schema.org/draft/2020-12/vocab/unevaluated"
  }
}

// MARK: - Arrays

extension Keywords {
  /// https://json-schema.org/draft/2020-12/json-schema-core#name-prefixitems
  internal struct PrefixItems: ApplicatorKeyword {
    internal static let name = "prefixItems"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschemas: [Schema]

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschemas = value.array?.extractSubschemas(using: context) ?? []
    }

    internal typealias AnnotationValue = PrefixItemsAnnoationValue

    internal enum PrefixItemsAnnoationValue: AnnotationValueConvertible {
      /// The largest index to which this keyword applied a subschema
      case largestIndex(Int)
      /// Applied when subschema applies to every index of the instance
      case everyIndex

      internal var value: JSONValue {
        switch self {
        case .largestIndex(let int):
          return .integer(int)
        case .everyIndex:
          return true
        }
      }

      internal func merged(with other: PrefixItemsAnnoationValue) -> PrefixItemsAnnoationValue {
        switch (self, other) {
        case (.everyIndex, _):
          .everyIndex
        case (_, .everyIndex):
          .everyIndex
        case (.largestIndex(let lhs), .largestIndex(let rhs)):
          .largestIndex(lhs > rhs ? lhs : rhs)
        }
      }
    }

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      guard let instances = input.array else { return }

      var largestIndex: Int = instances.startIndex
      var builder = ValidationResultBuilder(keyword: self, instanceLocation: instanceLocation)

      for (offset, (instance, schema)) in zip(instances, subschemas).enumerated() {
        if !SchemaRuntime.check() { break }
        let prefixLocation = instanceLocation.appending(.index(offset))
        let result = try schema.validateSubschema(instance, at: prefixLocation).requiringComplete()
        builder.merging(result)
        largestIndex = offset
      }

      try builder.throwIfErrors()

      annotations.insert(
        keyword: self,
        at: instanceLocation,
        value: largestIndex == instances.indices.last ? .everyIndex : .largestIndex(largestIndex)
      )
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#name-items
  internal struct Items: ApplicatorKeyword {
    internal static let name = "items"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschema: Schema

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschema = value.extractSubschema(using: context)
    }

    internal typealias AnnotationValue = Bool

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      guard let instances = input.array else { return }

      let prefixItemsAnnotation = annotations.annotation(
        for: PrefixItems.self,
        at: instanceLocation
      )
      let relevantInstanceItems: ArraySlice<JSONValue> =
        switch prefixItemsAnnotation?.value {
        case .everyIndex: .init()
        case .largestIndex(let index): instances.dropFirst(index + 1)
        case .none: instances[...]
        }

      var builder = ValidationResultBuilder(keyword: self, instanceLocation: instanceLocation)

      // With array slice, original array indicies are used which is important here.
      for (index, instance) in zip(relevantInstanceItems.indices, relevantInstanceItems) {
        if !SchemaRuntime.check() { break }
        let itemLocation = instanceLocation.appending(.index(index))
        let result = try subschema.validateSubschema(instance, at: itemLocation).requiringComplete()
        builder.merging(result)
      }

      try builder.throwIfErrors()

      annotations.insert(keyword: self, at: instanceLocation, value: true)
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#name-contains
  internal struct Contains: ApplicatorKeyword {
    internal static let name = "contains"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschema: Schema

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschema = value.extractSubschema(using: context)
    }

    internal typealias AnnotationValue = ContainsAnnotationValue

    internal enum ContainsAnnotationValue: AnnotationValueConvertible {
      /// Array of indicies to which the keyword validates
      case indicies([Int])
      /// Applied when subschema validates successfully when applied to every index of the instance
      case everyIndex

      internal var value: JSONValue {
        switch self {
        case .indicies(let array):
          .array(array.map { .integer($0) })
        case .everyIndex:
          true
        }
      }

      internal func merged(with other: ContainsAnnotationValue) -> ContainsAnnotationValue {
        switch (self, other) {
        case (.indicies(let lhs), .indicies(let rhs)):
          .indicies(lhs + rhs)
        case (.everyIndex, _), (_, .everyIndex):
          .everyIndex
        }
      }
    }

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      try validate(input, at: instanceLocation, using: &annotations, minContainsIsZero: false)
    }

    func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer,
      minContainsIsZero: Bool
    ) throws(ValidationIssue) {
      guard let instances = input.array else { return }

      var validIndices = [Int]()
      for (index, instance) in instances.enumerated() {
        if !SchemaRuntime.check() { break }
        let pointer = instanceLocation.appending(.index(index))
        let result = try subschema.validateSubschema(instance, at: pointer).requiringComplete()
        if result.isValid {
          validIndices.append(index)
        }
      }

      if validIndices.isEmpty && !minContainsIsZero {
        throw ValidationIssue.containsInsufficientMatches(
          count: instances.count,
          required: 1
        )
      }

      let annotationValue =
        validIndices.count == instances.count
        ? ContainsAnnotationValue.everyIndex : .indicies(validIndices)
      annotations.insert(keyword: self, at: instanceLocation, value: annotationValue)
    }
  }
}

// MARK: - Objects

extension Keywords {
  /// https://json-schema.org/draft/2020-12/json-schema-core#name-properties
  internal struct Properties: ApplicatorKeyword {
    internal static let name = "properties"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let schemaMap: OrderedDictionary<String, Schema>

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context

      self.schemaMap =
        value.object?
        .reduce(into: [:]) { result, keyValue in
          let (key, rawSchema) = keyValue
          let updatedLocation = context.location.appending(.key(key))
          if let schema = try? Schema(
            rawSchema: rawSchema,
            location: updatedLocation,
            context: context.context,
            baseURI: context.uri
          ) {
            result[key] = schema
          }
        } ?? [:]
    }

    internal typealias AnnotationValue = OrderedSet<String>

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      guard let instanceObject = input.object else {
        return
      }

      var instancePropertyNames: OrderedSet<String> = []
      var builder = ValidationResultBuilder(keyword: self, instanceLocation: instanceLocation)

      for (key, value) in instanceObject {
        if !SchemaRuntime.check() { break }
        guard let schema = schemaMap[key] else { continue }
        let propertyLocation = instanceLocation.appending(.key(key))
        var subAnnotations = AnnotationContainer()
        let result =
          try schema.validate(
            value,
            at: propertyLocation,
            annotations: &subAnnotations
          )
          .requiringComplete()
        builder.merging(result)
        annotations.merge(subAnnotations)
        instancePropertyNames.append(key)
      }

      // The `properties` annotation MUST record every property name this
      // keyword applied to, regardless of whether the sub-validation passed.
      // Insert before `throwIfErrors()` so that a failing sub-property does
      // not suppress the annotation — otherwise sibling
      // `unevaluatedProperties: false` reads every applicable property as
      // "unevaluated" and cascades a spurious error to every ancestor.
      // See JSON Schema 2020-12 core §10.3.2.1: the annotation is "the set
      // of instance property names matched by this keyword."
      annotations.insert(keyword: self, at: instanceLocation, value: instancePropertyNames)

      try builder.throwIfErrors()
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#name-patternproperties
  internal struct PatternProperties: ApplicatorKeyword {
    internal static let name = "patternProperties"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let patterns: [(SchemaPattern, Schema)]
    private let uncompilablePattern: String?

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context

      var uncompilable: String?
      self.patterns =
        value.object?
        .compactMap { key, rawSchema in
          guard let regex = SchemaPattern(key) else {
            uncompilable = uncompilable ?? key
            return nil
          }
          guard
            let subschema = try? Schema(
              rawSchema: rawSchema,
              location: context.location.appending(.key(key)),
              context: context.context,
              baseURI: context.uri
            )
          else { return nil }
          return (regex, subschema)
        } ?? []
      self.uncompilablePattern = uncompilable
    }

    internal typealias AnnotationValue = OrderedSet<String>

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      guard let instanceObject = input.object else { return }
      // Fail closed: with an uncompilable pattern we can't tell which properties it applies to.
      if let uncompilablePattern, !instanceObject.isEmpty {
        throw ValidationIssue.invalidPattern(pattern: uncompilablePattern)
      }

      var matchedPropertyNames: OrderedSet<String> = []
      var builder = ValidationResultBuilder(keyword: self, instanceLocation: instanceLocation)

      for (key, value) in instanceObject {
        if !SchemaRuntime.check() { break }
        for (regex, schema) in patterns where regex.matches(key) {
        if !SchemaRuntime.check() { break }
          let propertyLocation = instanceLocation.appending(.key(key))
          let result = try schema.validateSubschema(value, at: propertyLocation).requiringComplete()
          builder.merging(result)
          matchedPropertyNames.append(key)
        }
      }

      // See `Properties.validate` for the rationale: the annotation must be
      // recorded before throwing so that `unevaluatedProperties` sees the
      // property names this keyword applied to, even when one or more
      // sub-validations failed.
      annotations.insert(keyword: self, at: instanceLocation, value: matchedPropertyNames)

      try builder.throwIfErrors()
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#name-additionalproperties
  internal struct AdditionalProperties: ApplicatorKeyword {
    internal static let name = "additionalProperties"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschema: Schema

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschema = value.extractSubschema(using: context)
    }

    internal typealias AnnotationValue = OrderedSet<String>

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      guard let instanceObject = input.object else { return }

      let previouslyValidatedKeys =
        (annotations.annotation(for: Properties.self, at: instanceLocation)?.value ?? [])
        .union(
          annotations.annotation(for: PatternProperties.self, at: instanceLocation)?.value ?? []
        )

      var validatedKeys: OrderedSet<String> = []
      var builder = ValidationResultBuilder(keyword: self, instanceLocation: instanceLocation)

      for (key, value) in instanceObject where !previouslyValidatedKeys.contains(key) {
        if !SchemaRuntime.check() { break }
        let propertyLocation = instanceLocation.appending(.key(key))
        let result = try subschema.validateSubschema(value, at: propertyLocation)
          .requiringComplete()
        builder.merging(result)
        validatedKeys.append(key)
      }

      // See `Properties.validate` for the rationale: the annotation must be
      // recorded before throwing so that `unevaluatedProperties` sees every
      // property name this keyword applied to, even when one or more
      // sub-validations failed.
      annotations.insert(keyword: self, at: instanceLocation, value: validatedKeys)

      try builder.throwIfErrors()
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#name-propertynames
  internal struct PropertyNames: ApplicatorKeyword {
    internal static let name = "propertyNames"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschema: Schema

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschema = value.extractSubschema(using: context)
    }

    internal typealias AnnotationValue = Never

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      guard let instanceObject = input.object else { return }

      var builder = ValidationResultBuilder(keyword: self, instanceLocation: instanceLocation)

      for key in instanceObject.keys {
        if !SchemaRuntime.check() { break }
        let keyValue = JSONValue.string(key)
        let result =
          try subschema.validateSubschema(
            keyValue,
            at: instanceLocation.appending(.key(key))
          )
          .requiringComplete()
        builder.merging(result)
      }

      try builder.throwIfErrors()
    }
  }
}

// MARK: - In Place (Logic)

extension Keywords {
  /// https://json-schema.org/draft/2020-12/json-schema-core#name-allof
  internal struct AllOf: ApplicatorKeyword {
    internal static let name = "allOf"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschemas: [Schema]

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschemas = value.array?.extractSubschemas(using: context) ?? []
    }

    internal typealias AnnotationValue = Never

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      var builder = ValidationResultBuilder(keyword: self, instanceLocation: instanceLocation)

      for subschema in subschemas {
        if !SchemaRuntime.check() { break }
        var subAnnotations = AnnotationContainer()
        let result =
          try subschema.validate(input, at: instanceLocation, annotations: &subAnnotations)
          .requiringComplete()
        // Per spec §10.2.1.1, allOf produces no annotations of its own, but the
        // annotations of each successful subschema propagate to the surrounding
        // schema. A failing subschema's annotations MUST NOT leak through, or
        // sibling `unevaluatedProperties`/`unevaluatedItems` will treat
        // properties/indices "matched" by a failed branch as evaluated.
        if result.isValid {
          annotations.merge(subAnnotations)
        }
        builder.merging(result)
      }

      try builder.throwIfErrors()
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#name-anyof
  internal struct AnyOf: ApplicatorKeyword {
    internal static let name = "anyOf"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschemas: [Schema]

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschemas = value.array?.extractSubschemas(using: context) ?? []
    }

    internal typealias AnnotationValue = Never

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      var isValid = false
      var builder = ValidationResultBuilder(keyword: self, instanceLocation: instanceLocation)

      for subschema in subschemas {
        if !SchemaRuntime.check() { break }
        var subAnnotations = AnnotationContainer()
        let result =
          try subschema.validate(input, at: instanceLocation, annotations: &subAnnotations)
          .requiringComplete()
        // Per spec §10.2.1.2, anyOf collects annotations only from MATCHING
        // (passing) subschemas. Merging from failing branches would cause
        // sibling `unevaluatedProperties`/`unevaluatedItems` to treat
        // properties/indices "matched" by a non-applicable branch as evaluated.
        if result.isValid {
          isValid = true
          annotations.merge(subAnnotations)
        }
        builder.merging(result)
      }

      if !isValid {
        try builder.throwIfErrors()
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#name-oneof
  internal struct OneOf: ApplicatorKeyword {
    internal static let name = "oneOf"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschemas: [Schema]

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschemas = value.array?.extractSubschemas(using: context) ?? []
    }

    internal typealias AnnotationValue = Never

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      var validCount = 0
      var builder = ValidationResultBuilder(keyword: self, instanceLocation: instanceLocation)

      for subschema in subschemas {
        if !SchemaRuntime.check() { break }
        var subAnnotations = AnnotationContainer()
        let result =
          try subschema.validate(input, at: instanceLocation, annotations: &subAnnotations)
          .requiringComplete()
        if result.isValid {
          validCount += 1
          annotations.merge(subAnnotations)
        }
        builder.merging(result)
      }

      if validCount != 1 {
        // Surface the per-subschema failures so consumers walking the
        // `errors:` tree (UIs, error renderers, debuggers) can see *why*
        // each branch failed instead of getting an opaque "did not match
        // exactly one schema" with no children.
        //
        // Note this naturally produces an empty `errors:` array in the
        // multi-match case (validCount > 1, all matching subschemas
        // contribute zero errors), which matches the prior behavior for
        // that branch — the failure is the keyword-level "exactly one"
        // rule, not any individual subschema's verdict.
        throw ValidationIssue.oneOfFailed(errors: builder.collectedErrors)
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#section-10.2.1.4
  internal struct Not: ApplicatorKeyword {
    internal static let name = "not"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschema: Schema

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschema = value.extractSubschema(using: context)
    }

    internal typealias AnnotationValue = Never

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      var subAnnotations = AnnotationContainer()
      let result = try subschema.validate(input, at: instanceLocation, annotations: &subAnnotations)
        .requiringComplete()
      if result.isValid {
        annotations.merge(subAnnotations)
        throw ValidationIssue.notFailed
      }
    }
  }
}

// MARK: - In Place (Conditionally)

extension Keywords {
  /// https://json-schema.org/draft/2020-12/json-schema-core#name-if
  internal struct If: ApplicatorKeyword {
    internal static let name = "if"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschema: Schema

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschema = value.extractSubschema(using: context)
    }

    internal typealias AnnotationValue = Never

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      _ = try evaluate(input, at: instanceLocation, using: &annotations)
    }

    func evaluate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) -> Bool {
      var subAnnotations = AnnotationContainer()
      let result = try subschema.validate(input, at: instanceLocation, annotations: &subAnnotations)
        .requiringComplete()
      // Per JSON Schema 2020-12 core §10.2.2.1, `if` only contributes to
      // annotation collection when its subschema validates successfully —
      // otherwise sibling `unevaluatedProperties`/`unevaluatedItems` would
      // treat properties/indices "matched" by a failed `if` branch as
      // evaluated. Mirrors the filter already in `allOf`/`anyOf`/`oneOf`.
      if result.isValid {
        annotations.merge(subAnnotations)
      }
      return result.isValid
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#name-then
  internal struct Then: ApplicatorKeyword {
    internal static let name = "then"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschema: Schema

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschema = value.extractSubschema(using: context)
    }

    internal typealias AnnotationValue = Never

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      try validate(input, at: instanceLocation, using: &annotations, condition: nil)
    }

    func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer,
      condition: Bool?
    ) throws(ValidationIssue) {
      guard condition == true else {
        return
      }

      var subAnnotations = AnnotationContainer()
      let result = try subschema.validate(input, at: instanceLocation, annotations: &subAnnotations)
        .requiringComplete()
      if !result.isValid {
        throw ValidationIssue.conditionalFailed(condition: "then", errors: result.errors ?? [])
      }
      annotations.merge(subAnnotations)
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#name-else
  internal struct Else: ApplicatorKeyword {
    internal static let name = "else"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschema: Schema

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschema = value.extractSubschema(using: context)
    }

    internal typealias AnnotationValue = Never

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      try validate(input, at: instanceLocation, using: &annotations, condition: nil)
    }

    func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer,
      condition: Bool?
    ) throws(ValidationIssue) {
      guard condition == false else {
        return
      }
      var subAnnotations = AnnotationContainer()
      let result = try subschema.validate(input, at: instanceLocation, annotations: &subAnnotations)
        .requiringComplete()
      if !result.isValid {
        throw ValidationIssue.conditionalFailed(condition: "else", errors: result.errors ?? [])
      }
      annotations.merge(subAnnotations)
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#name-dependentschemas
  internal struct DependentSchemas: ApplicatorKeyword {
    internal static let name = "dependentSchemas"

    internal let value: JSONValue
    internal let context: KeywordContext

    // OrderedDictionary so iteration in `validate(...)` happens in declared
    // schema order — the order the user wrote properties in `dependentSchemas`
    // — rather than randomized Dictionary order. Required for #149.
    private let schemaMap: OrderedDictionary<String, Schema>

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context

      self.schemaMap = OrderedDictionary(
        uniqueKeysWithValues: value.object?
          .compactMap { (key, rawSchema) -> (String, Schema)? in
            // Each per-property sub-schema lives at `<keyword>/<key>` and
            // must inherit the enclosing schema's `$id`-resolved URI so that
            // relative `$ref`s inside it (e.g. `#/$defs/...`) resolve
            // against the parent document, not the in-memory placeholder
            // base URL. Mirrors the Properties / PatternProperties pattern.
            guard
              let schema = try? Schema(
                rawSchema: rawSchema,
                location: context.location.appending(.key(key)),
                context: context.context,
                baseURI: context.uri
              )
            else { return nil }
            return (key, schema)
          } ?? []
      )
    }

    internal typealias AnnotationValue = Never

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      guard let instanceObject = input.object else { return }

      var builder = ValidationResultBuilder(keyword: self, instanceLocation: instanceLocation)

      // Walk schemaMap (in declared order) and consult the instance via O(1)
      // subscript. `instanceObject.keys.contains(_:)` is also O(1) on
      // OrderedDictionary, but `instanceObject[key] != nil` is more idiomatic.
      for (key, schema) in schemaMap where instanceObject[key] != nil {
        if !SchemaRuntime.check() { break }
        var subAnnotations = AnnotationContainer()
        let result = try schema.validate(input, at: instanceLocation, annotations: &subAnnotations)
          .requiringComplete()
        builder.merging(result)
        // Per spec §10.2.2.4, dependentSchemas collects annotations only from
        // matching (passing) subschemas — the same rule as in-place applicators
        // like allOf/anyOf.
        if result.isValid {
          annotations.merge(subAnnotations)
        }
      }

      try builder.throwIfErrors()
    }
  }
}

// MARK: - Unevaluated Locations

extension Keywords {
  /// https://json-schema.org/draft/2020-12/json-schema-core#name-unevaluateditems
  internal struct UnevaluatedItems: UnevaluatedKeyword {
    internal static let name = "unevaluatedItems"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschema: Schema

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschema = value.extractSubschema(using: context)
    }

    internal typealias AnnotationValue = Bool

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      guard let instances = input.array else { return }

      // Nested unevaluatedItems take precedence.
      // See "unevaluatedItems with nested unevaluatedItems" from JSON schema test suite.
      guard annotations.annotation(for: Self.self, at: instanceLocation) == nil else { return }

      var evaluatedIndices = Set<Int>()

      if let prefixItemsAnnotation = annotations.annotation(
        for: PrefixItems.self,
        at: instanceLocation
      )?
      .value {
        switch prefixItemsAnnotation {
        case .everyIndex:
          return
        case .largestIndex(let largestIndex):
          evaluatedIndices.formUnion(0 ... largestIndex)
        }
      }

      if let itemsAnnotation = annotations.annotation(for: Items.self, at: instanceLocation)?.value,
        itemsAnnotation == true
      {
        evaluatedIndices.formUnion(0 ..< instances.count)
      }

      if context.context.dialect != .draft2019_09, let containsAnnotation = annotations.annotation(for: Contains.self, at: instanceLocation)?
        .value
      {
        switch containsAnnotation {
        case .everyIndex:
          evaluatedIndices.formUnion(0 ..< instances.count)
        case .indicies(let indicies):
          evaluatedIndices.formUnion(indicies)
        }
      }

      let unevaluatedIndices = Set(instances.indices).subtracting(evaluatedIndices)
      var builder = ValidationResultBuilder(keyword: self, instanceLocation: instanceLocation)

      for index in unevaluatedIndices {
        if !SchemaRuntime.check() { break }
        let instance = instances[index]
        let itemLocation = instanceLocation.appending(.index(index))
        var subAnnotations = AnnotationContainer()
        let result =
          try subschema.validate(instance, at: itemLocation, annotations: &subAnnotations)
          .requiringComplete()
        builder.merging(result)
        annotations.merge(subAnnotations)
      }

      try builder.throwIfErrors()

      if !unevaluatedIndices.isEmpty {
        annotations.insert(keyword: self, at: instanceLocation, value: true)
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-core#name-unevaluatedproperties
  internal struct UnevaluatedProperties: UnevaluatedKeyword {
    internal static let name = "unevaluatedProperties"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let subschema: Schema

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.subschema = value.extractSubschema(using: context)
    }

    internal typealias AnnotationValue = OrderedSet<String>

    internal func validate(
      _ input: JSONValue,
      at instanceLocation: JSONPointer,
      using annotations: inout AnnotationContainer
    ) throws(ValidationIssue) {
      guard let instanceObject = input.object else { return }

      // Nested unevaluatedProperties take precedence.
      // See "unevaluatedProperties with nested unevaluatedProperties" from JSON schema test suite.
      guard annotations.annotation(for: Self.self, at: instanceLocation) == nil else { return }

      var evaluatedPropertyNames = OrderedSet<String>()

      if let propertiesAnnotation = annotations.annotation(
        for: Properties.self,
        at: instanceLocation
      )?
      .value {
        evaluatedPropertyNames.formUnion(propertiesAnnotation)
      }

      if let patternPropertiesAnnotation = annotations.annotation(
        for: PatternProperties.self,
        at: instanceLocation
      )?
      .value {
        evaluatedPropertyNames.formUnion(patternPropertiesAnnotation)
      }

      if let additionalPropertiesAnnotation = annotations.annotation(
        for: AdditionalProperties.self,
        at: instanceLocation
      )?
      .value {
        evaluatedPropertyNames.formUnion(additionalPropertiesAnnotation)
      }

      // Iterate the instance object's keys in declared order (preserved by
      // JSONValue.object's OrderedDictionary), filtering out previously
      // evaluated names. Avoids losing order through Set.subtracting.
      let unevaluatedPropertyNames = instanceObject.keys.filter {
        !evaluatedPropertyNames.contains($0)
      }
      var builder = ValidationResultBuilder(keyword: self, instanceLocation: instanceLocation)
      var validatedPropertyNames = OrderedSet<String>()

      for propertyName in unevaluatedPropertyNames {
        if !SchemaRuntime.check() { break }
        guard let propertyValue = instanceObject[propertyName] else { continue }
        var subAnnotations = AnnotationContainer()
        let propertyLocation = instanceLocation.appending(.key(propertyName))
        let result =
          try subschema.validate(
            propertyValue,
            at: propertyLocation,
            annotations: &subAnnotations
          )
          .requiringComplete()
        builder.merging(result)
        annotations.merge(subAnnotations)
        validatedPropertyNames.append(propertyName)
      }

      try builder.throwIfErrors()

      annotations.insert(keyword: self, at: instanceLocation, value: validatedPropertyNames)
    }
  }
}

// MARK: - Helpers

extension Never: AnnotationValueConvertible {
  internal var value: JSONValue { .null }

  internal func merged(with other: Never) -> Never {}
}

extension OrderedSet: AnnotationValueConvertible where Element == String {
  internal var value: JSONValue {
    .array(self.map { .string($0) })
  }

  internal func merged(with other: OrderedSet<String>) -> OrderedSet<String> {
    self.union(other)
  }
}

extension Bool: AnnotationValueConvertible {
  internal var value: JSONValue { .boolean(self) }

  internal func merged(with other: Bool) -> Bool {
    self || other
  }
}

extension Array where Element == JSONValue {
  func extractSubschemas(using context: KeywordContext) -> [Schema] {
    var subschemas = [Schema]()
    subschemas.reserveCapacity(self.count)
    for (index, rawSchema) in self.enumerated() {
        if !SchemaRuntime.check() { break }
      let pointer = context.location.appending(.index(index))
      if let subschema = try? Schema(
        rawSchema: rawSchema,
        location: pointer,
        context: context.context,
        baseURI: context.uri
      ) {
        subschemas.append(subschema)
      }
    }
    return subschemas
  }
}

extension JSONValue {
  func extractSubschema(using context: KeywordContext) -> Schema {
    (try? Schema(
      rawSchema: self,
      location: context.location,
      context: context.context,
      baseURI: context.uri
    ))
      ?? BooleanSchema(
        schemaValue: true,
        location: context.location,
        context: context.context,
        documentURL: context.uri
      )
      .asSchema()
  }
}

struct ValidationResultBuilder {
  let keyword: any Keyword
  let instanceLocation: JSONPointer

  init(keyword: any Keyword, instanceLocation: JSONPointer) {
    self.keyword = keyword
    self.instanceLocation = instanceLocation
  }

  private var errors: [ValidationError] = []

  /// Errors collected so far from `merging(_:)`. Exposed so keywords like
  /// `oneOf` — which need to decide whether/how to throw based on a count
  /// of *passing* subschemas (not just whether errors accumulated) — can
  /// surface the per-subschema failures inside their own
  /// `ValidationIssue` case rather than relying on `throwIfErrors`.
  var collectedErrors: [ValidationError] { errors }

  mutating func merging(_ result: ValidationResult) {
    if result.isValid {

    } else {
      if let resultErrors = result.errors {
        errors.append(contentsOf: resultErrors)
      } else {
        errors.append(
          .init(
            keyword: type(of: keyword).name,
            message: "Validation failed",
            keywordLocation: keyword.context.location,
            absoluteKeywordLocation: keyword.context.absoluteKeywordLocation(),
            instanceLocation: result.instanceLocation
          )
        )
      }
    }
  }

  func throwIfErrors() throws(ValidationIssue) {
    if !errors.isEmpty {
      throw .keywordFailure(keyword: type(of: keyword).name, errors: errors)
    }
  }
}
