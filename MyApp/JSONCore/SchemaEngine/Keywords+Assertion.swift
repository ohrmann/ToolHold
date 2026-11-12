// Vendored MIT: ajevans99/swift-json-schema @ 8d314b50; see ThirdPartyNotices/SwiftJSONSchema.
internal protocol AssertionKeyword: Keyword {
  func validate(
    _ input: JSONValue,
    at location: JSONPointer,
    using annotations: AnnotationContainer
  ) throws(ValidationIssue)
}

protocol ValidationKeyword: AssertionKeyword {}

extension ValidationKeyword {
  internal static var vocabulary: String {
    "https://json-schema.org/draft/2020-12/vocab/validation"
  }

  func countBound() throws(ValidationIssue) -> JSONNumberLiteral {
    guard let bound = value.numberLiteral, bound.isInteger, bound >= JSONNumberLiteral(0) else {
      throw .numericValidationFailure(reason: "'\(Self.name)' must be a nonnegative integer")
    }
    return bound
  }
}

extension JSONNumberLiteral {
  /// Narrows a validated count or length bound to `Int` so a failure can report it.
  ///
  /// Bound comparisons use the full-precision literal, so narrowing here only affects how an
  /// already-determined failure is described. A bound outside `Int`'s range is reported as a
  /// numeric validation failure rather than clamped to a misleading value.
  func intBound(for keyword: String) throws(ValidationIssue) -> Int {
    guard let bound = try? integerValue() else {
      throw .numericValidationFailure(
        reason: "'\(keyword)' bound \(self) is outside the representable range"
      )
    }
    return bound
  }
}

protocol FormatKeyword: AssertionKeyword {}

extension FormatKeyword {
  internal static var vocabulary: String {
    "https://json-schema.org/draft/2020-12/vocab/format-annotation"
  }
}

extension Keywords {
  internal struct TypeKeyword: ValidationKeyword {
    internal static let name = "type"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let allowedPrimitives: [JSONType]

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context

      self.allowedPrimitives =
        switch value {
        case .array(let allowedTypes):
          allowedTypes
            .compactMap {
              if case .string(let string) = $0 {
                return string
              }
              return nil
            }
            .compactMap { JSONType(rawValue: $0) }
        case .string(let allowedType):
          JSONType(rawValue: allowedType).map { [$0] } ?? []
        default:
          []
        }
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      let instanceType = input.primitive
      let isValid = allowedPrimitives.contains { allowedType in
        allowedType.matches(instanceType: instanceType)
          || (allowedType == .integer && input.isMathematicalInteger)
      }
      if !isValid {
        throw ValidationIssue.typeMismatch(expected: allowedPrimitives, actual: instanceType)
      }
    }
  }

  internal struct Enum: ValidationKeyword {
    internal static let name = "enum"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let enumCases: [JSONValue]

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.enumCases = value.array ?? []
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      if !enumCases.contains(input) {
        throw ValidationIssue.notEnumCase(value: input, allowedValues: enumCases)
      }
    }
  }

  internal struct Constant: ValidationKeyword {
    internal static let name = "const"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      if input != value {
        throw ValidationIssue.constantMismatch(expected: value, actual: input)
      }
    }
  }
}

// MARK: - Numbers

extension Keywords {
  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-multipleof
  internal struct MultipleOf: ValidationKeyword {
    internal static let name = "multipleOf"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let divisor: JSONNumberLiteral?

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context

      divisor = value.numberLiteral
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      guard let divisor, divisor > JSONNumberLiteral(0) else {
        throw .numericValidationFailure(reason: "'multipleOf' must be a positive number")
      }
      guard let number = input.numberLiteral else { return }
      let isMultiple: Bool
      do {
        isMultiple = try number.isMultiple(of: divisor)
      } catch {
        throw .numericValidationFailure(reason: "Cannot evaluate 'multipleOf': \(error)")
      }
      if !isMultiple {
        throw .notMultipleOf(number: number, multiple: divisor)
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-maximum
  internal struct Maximum: ValidationKeyword {
    internal static let name = "maximum"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let maxValue: JSONNumberLiteral?

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.maxValue = value.numberLiteral
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      guard let maxValue else {
        throw .numericValidationFailure(reason: "'maximum' must be a number")
      }
      if let number = input.numberLiteral, number > maxValue {
        throw ValidationIssue.exceedsMaximum(number: number, maximum: maxValue)
      }
    }
  }

  internal struct ExclusiveMaximum: ValidationKeyword {
    internal static let name = "exclusiveMaximum"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let exclusiveMaxValue: JSONNumberLiteral?

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.exclusiveMaxValue = value.numberLiteral
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      guard let exclusiveMaxValue else {
        throw .numericValidationFailure(reason: "'exclusiveMaximum' must be a number")
      }
      if let number = input.numberLiteral, number >= exclusiveMaxValue {
        throw ValidationIssue.exceedsExclusiveMaximum(number: number, maximum: exclusiveMaxValue)
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-minimum
  internal struct Minimum: ValidationKeyword {
    internal static let name = "minimum"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let minValue: JSONNumberLiteral?

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.minValue = value.numberLiteral
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      guard let minValue else {
        throw .numericValidationFailure(reason: "'minimum' must be a number")
      }
      if let number = input.numberLiteral, number < minValue {
        throw ValidationIssue.belowMinimum(number: number, minimum: minValue)
      }
    }
  }

  internal struct ExclusiveMinimum: ValidationKeyword {
    internal static let name = "exclusiveMinimum"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let exclusiveMinValue: JSONNumberLiteral?

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.exclusiveMinValue = value.numberLiteral
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      guard let exclusiveMinValue else {
        throw .numericValidationFailure(reason: "'exclusiveMinimum' must be a number")
      }
      if let number = input.numberLiteral, number <= exclusiveMinValue {
        throw ValidationIssue.belowExclusiveMinimum(number: number, minimum: exclusiveMinValue)
      }
    }
  }
}

// MARK: - Strings

extension Keywords {
  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-maxlength
  internal struct MaxLength: ValidationKeyword {
    internal static let name = "maxLength"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      let maxLength = try countBound()
      if let string = input.string, JSONNumberLiteral(string.unicodeScalars.count) > maxLength {
        throw ValidationIssue.exceedsMaxLength(
          string: string,
          maxLength: try maxLength.intBound(for: Self.name)
        )
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-minlength
  internal struct MinLength: ValidationKeyword {
    internal static let name = "minLength"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      let minLength = try countBound()
      if let string = input.string, JSONNumberLiteral(string.unicodeScalars.count) < minLength {
        throw ValidationIssue.belowMinLength(
          string: string,
          minLength: try minLength.intBound(for: Self.name)
        )
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-pattern
  internal struct Pattern: ValidationKeyword {
    internal static let name = "pattern"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let regex: SchemaPattern?
    private let isUncompilable: Bool

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context

      if let patternString = value.string {
        self.regex = SchemaPattern(patternString)
        self.isUncompilable = regex == nil
      } else {
        self.regex = nil
        self.isUncompilable = false
      }
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      guard let string = input.string else { return }
      // Fail closed: a pattern that can't be compiled can't be satisfied.
      if isUncompilable {
        throw ValidationIssue.invalidPattern(pattern: value.string ?? "")
      }
      if let regex = regex {
        if !regex.matches(string) {
          throw ValidationIssue.patternMismatch(string: string, pattern: value.string ?? "")
        }
      }
    }
  }

  internal struct Format: FormatKeyword {
    internal static let name = "format"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      guard
        let formatName = value.string,
        let string = input.string,
        let validator = context.context.formatValidators[formatName]
      else { return }

      if !validator.validate(string) {
        throw ValidationIssue.invalidFormat(name: formatName, value: string)
      }
    }
  }
}

// MARK: - Arrays

extension Keywords {
  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-maxitems
  internal struct MaxItems: ValidationKeyword {
    internal static let name = "maxItems"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      let maxItems = try countBound()
      if let array = input.array, JSONNumberLiteral(array.count) > maxItems {
        throw ValidationIssue.exceedsMaxItems(
          count: array.count,
          maxItems: try maxItems.intBound(for: Self.name)
        )
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-minitems
  internal struct MinItems: ValidationKeyword {
    internal static let name = "minItems"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      let minItems = try countBound()
      if let array = input.array, JSONNumberLiteral(array.count) < minItems {
        throw ValidationIssue.belowMinItems(
          count: array.count,
          minItems: try minItems.intBound(for: Self.name)
        )
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-uniqueitems
  internal struct UniqueItems: ValidationKeyword {
    internal static let name = "uniqueItems"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let uniqueItemsRequired: Bool

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.uniqueItemsRequired = value.boolean ?? false
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      if uniqueItemsRequired, let array = input.array {
        var set = Set<JSONValue>()
        for value in array {
        if !SchemaRuntime.check() { break }
          guard SchemaRuntime.check() else { throw .evaluationFailed(errors: []) }
          set.insert(value)
        }
        if set.count != array.count {
          throw ValidationIssue.itemsNotUnique
        }
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-maxcontains
  internal struct MaxContains: ValidationKeyword {
    internal static let name = "maxContains"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      guard let array = input.array else { return }

      guard let containsAnnotation = annotations.annotation(for: Contains.self, at: location) else {
        return
      }

      let maxContains = try countBound()
      switch containsAnnotation.value {
      case .everyIndex:
        if JSONNumberLiteral(array.count) > maxContains {
          throw ValidationIssue.containsExcessiveMatches(
            count: array.count,
            maxAllowed: try maxContains.intBound(for: Self.name)
          )
        }
      case .indicies(let indicies):
        if JSONNumberLiteral(indicies.count) > maxContains {
          throw ValidationIssue.containsExcessiveMatches(
            count: indicies.count,
            maxAllowed: try maxContains.intBound(for: Self.name)
          )
        }
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-mincontains
  internal struct MinContains: ValidationKeyword {
    internal static let name = "minContains"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      guard let array = input.array else { return }

      guard let containsAnnotation = annotations.annotation(for: Contains.self, at: location) else {
        return
      }

      let minContains = try countBound()
      switch containsAnnotation.value {
      case .everyIndex:
        if JSONNumberLiteral(array.count) < minContains {
          throw ValidationIssue.containsInsufficientMatches(
            count: array.count,
            required: try minContains.intBound(for: Self.name)
          )
        }
      case .indicies(let indicies):
        if JSONNumberLiteral(indicies.count) < minContains {
          throw ValidationIssue.containsInsufficientMatches(
            count: indicies.count,
            required: try minContains.intBound(for: Self.name)
          )
        }
      }
    }
  }
}

// MARK: - Objects

extension Keywords {
  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-maxproperties
  internal struct MaxProperties: ValidationKeyword {
    internal static let name = "maxProperties"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      guard let object = input.object else { return }

      let maxProperties = try countBound()
      if JSONNumberLiteral(object.count) > maxProperties {
        throw ValidationIssue.exceedsMaxProperties(
          count: object.count,
          maxProperties: try maxProperties.intBound(for: Self.name)
        )
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-minproperties
  internal struct MinProperties: ValidationKeyword {
    internal static let name = "minProperties"

    internal let value: JSONValue
    internal let context: KeywordContext

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      guard let object = input.object else { return }

      let minProperties = try countBound()
      if JSONNumberLiteral(object.count) < minProperties {
        throw ValidationIssue.belowMinProperties(
          count: object.count,
          minProperties: try minProperties.intBound(for: Self.name)
        )
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-required
  internal struct Required: ValidationKeyword {
    internal static let name = "required"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let requiredKeys: [String]

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.requiredKeys = value.array?.compactMap { $0.string } ?? []
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      guard let object = input.object else { return }

      for key in requiredKeys where !object.keys.contains(key) {
        if !SchemaRuntime.check() { break }
        throw ValidationIssue.missingRequiredProperty(key: key)
      }
    }
  }

  /// https://json-schema.org/draft/2020-12/json-schema-validation#name-dependentrequired
  internal struct DependentRequired: ValidationKeyword {
    internal static let name = "dependentRequired"

    internal let value: JSONValue
    internal let context: KeywordContext

    private let dependencies: OrderedDictionary<String, [String]>

    internal init(value: JSONValue, context: KeywordContext) {
      self.value = value
      self.context = context
      self.dependencies = OrderedDictionary(
        uniqueKeysWithValues: value.object?
          .compactMap { (key, value) -> (String, [String])? in
            guard let array = value.array?.compactMap({ $0.string }) else { return nil }
            return (key, array)
          } ?? []
      )
    }

    internal func validate(
      _ input: JSONValue,
      at location: JSONPointer,
      using annotations: AnnotationContainer
    ) throws(ValidationIssue) {
      guard let object = input.object else { return }

      for (key, dependentKeys) in dependencies where object.keys.contains(key) {
        if !SchemaRuntime.check() { break }
        for requiredKey in dependentKeys where !object.keys.contains(requiredKey) {
        if !SchemaRuntime.check() { break }
          throw ValidationIssue.missingDependentProperty(key: requiredKey, dependentOn: key)
        }
      }
    }
  }
}
