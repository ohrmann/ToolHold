// Vendored MIT: ajevans99/swift-json-schema @ 8d314b50; see ThirdPartyNotices/SwiftJSONSchema.
import Foundation

public enum ValidationIssue: Error, Codable, Equatable {
  case typeMismatch(expected: [JSONType], actual: JSONType)
  case notEnumCase(value: JSONValue, allowedValues: [JSONValue])
  case constantMismatch(expected: JSONValue, actual: JSONValue)

  // Number
  case notMultipleOf(number: JSONNumberLiteral, multiple: JSONNumberLiteral)
  case exceedsMaximum(number: JSONNumberLiteral, maximum: JSONNumberLiteral)
  case exceedsExclusiveMaximum(number: JSONNumberLiteral, maximum: JSONNumberLiteral)
  case belowMinimum(number: JSONNumberLiteral, minimum: JSONNumberLiteral)
  case belowExclusiveMinimum(number: JSONNumberLiteral, minimum: JSONNumberLiteral)
  case numericValidationFailure(reason: String)
  case evaluationFailed(errors: [ValidationError])

  // String
  case exceedsMaxLength(string: String, maxLength: Int)
  case belowMinLength(string: String, minLength: Int)
  case patternMismatch(string: String, pattern: String)
  case invalidPattern(pattern: String)
  case invalidFormat(name: String, value: String)

  // Arrays
  case exceedsMaxItems(count: Int, maxItems: Int)
  case belowMinItems(count: Int, minItems: Int)
  case itemsNotUnique
  case containsInsufficientMatches(count: Int, required: Int)
  case containsExcessiveMatches(count: Int, maxAllowed: Int)
  case invalidItem(index: Int, error: ValidationError)

  // Objects
  case exceedsMaxProperties(count: Int, maxProperties: Int)
  case belowMinProperties(count: Int, minProperties: Int)
  case missingRequiredProperty(key: String)
  case missingDependentProperty(key: String, dependentOn: String)
  case invalidProperty(key: String, error: ValidationError)
  case invalidPatternProperty(key: String, pattern: String)
  case invalidAdditionalProperty(key: String)

  // Logical
  case allOfFailed(errors: [ValidationError])
  case anyOfFailed(errors: [ValidationError])
  case oneOfFailed(errors: [ValidationError])
  case notFailed

  // Conditional
  case conditionalFailed(condition: String, errors: [ValidationError])
  case invalidDependentSchema(key: String, errors: [ValidationError])
  case unevaluatedItemsFailed(errors: [ValidationError])
  case unevaluatedPropertyFailed(errors: [ValidationError])

  // Reference
  case invalidReference(String)
  case referenceValidationFailure(ref: String, errors: [ValidationError])

  case keywordFailure(keyword: KeywordIdentifier, errors: [ValidationError])
}

extension ValidationIssue {
  var isEvaluationFailure: Bool {
    switch self {
    case .numericValidationFailure, .evaluationFailed: true
    default: false
    }
  }

  func makeValidationError(
    keyword: String,
    keywordLocation: JSONPointer,
    absoluteKeywordLocation: URL?,
    instanceLocation: JSONPointer
  ) -> ValidationError {
    var result: ValidationError = switch self {
    case .keywordFailure(let keyword, let errors):
      .init(
        keyword: keyword,
        message: "Validation failed for keyword '\(keyword)'",
        keywordLocation: keywordLocation,
        absoluteKeywordLocation: absoluteKeywordLocation,
        instanceLocation: instanceLocation,
        errors: errors
      )
    case .referenceValidationFailure(let ref, let errors):
      .init(
        keyword: keyword,
        message: "Validation failed during reference validation '\(ref)'",
        keywordLocation: keywordLocation,
        absoluteKeywordLocation: absoluteKeywordLocation,
        instanceLocation: instanceLocation,
        errors: errors
      )
    case .evaluationFailed(let errors),
      .allOfFailed(let errors),
      .anyOfFailed(let errors),
      .oneOfFailed(let errors),
      .conditionalFailed(_, let errors),
      .invalidDependentSchema(_, let errors),
      .unevaluatedItemsFailed(let errors),
      .unevaluatedPropertyFailed(let errors):
      .init(
        keyword: keyword,
        message: description,
        keywordLocation: keywordLocation,
        absoluteKeywordLocation: absoluteKeywordLocation,
        instanceLocation: instanceLocation,
        errors: errors
      )
    default:
      .init(
        keyword: keyword,
        message: description,
        keywordLocation: keywordLocation,
        absoluteKeywordLocation: absoluteKeywordLocation,
        instanceLocation: instanceLocation
      )
    }
    switch self {
    case .invalidAdditionalProperty(let key): result.relatedProperty = key
    default: break
    }
    return result
  }
}

extension ValidationIssue: CustomStringConvertible {
  public var description: String {
    func safe(_ text: String) -> String { JSONTreePreview.make(text, budget: 80).text }
    switch self {
    case .typeMismatch(let expected, let actual): return "Expected " + expected.map(\.rawValue).joined(separator: " or ") + "; found " + actual.rawValue
    case .notEnumCase: return "Value is not one of the allowed enum values."
    case .constantMismatch: return "Value does not match the required constant."
    case .notMultipleOf(_, let bound): return "Number must be a multiple of " + safe(bound.rawValue)
    case .exceedsMaximum(_, let bound): return "Number must be at most " + safe(bound.rawValue)
    case .exceedsExclusiveMaximum(_, let bound): return "Number must be less than " + safe(bound.rawValue)
    case .belowMinimum(_, let bound): return "Number must be at least " + safe(bound.rawValue)
    case .belowExclusiveMinimum(_, let bound): return "Number must be greater than " + safe(bound.rawValue)
    case .numericValidationFailure: return "Exact numeric evaluation could not be completed."
    case .evaluationFailed: return "Schema evaluation could not be completed."
    case .exceedsMaxLength(_, let count): return "String exceeds maximum length of \(count) Unicode code points."
    case .belowMinLength(_, let count): return "String is shorter than \(count) Unicode code points."
    case .patternMismatch(_, let pattern): return "String does not match pattern '" + safe(pattern) + "'."
    case .invalidPattern: return "Pattern cannot be evaluated."
    case .invalidFormat(let name, _): return "Value does not satisfy format '" + safe(name) + "'."
    case .exceedsMaxItems(let count, let maximum): return "Array has \(count) items; maximum is \(maximum)."
    case .belowMinItems(let count, let minimum): return "Array has \(count) items; minimum is \(minimum)."
    case .itemsNotUnique: return "Array items must be unique."
    case .containsInsufficientMatches(let count, let minimum): return "Array has \(count) matching items; at least \(minimum) required."
    case .containsExcessiveMatches(let count, let maximum): return "Array has \(count) matching items; maximum is \(maximum)."
    case .invalidItem(let index, _): return "Item at index \(index) does not satisfy the schema."
    case .exceedsMaxProperties(let count, let maximum): return "Object has \(count) properties; maximum is \(maximum)."
    case .belowMinProperties(let count, let minimum): return "Object has \(count) properties; minimum is \(minimum)."
    case .missingRequiredProperty(let key): return "Required property '" + safe(key) + "' is missing."
    case .missingDependentProperty(let key, let parent): return "Property '" + safe(key) + "' is required when '" + safe(parent) + "' is present."
    case .invalidProperty(let key, _): return "Property '" + safe(key) + "' does not satisfy the schema."
    case .invalidPatternProperty(let key, _): return "Property name '" + safe(key) + "' does not satisfy the pattern."
    case .invalidAdditionalProperty(let key): return "Property '" + safe(key) + "' is not allowed."
    case .allOfFailed: return "One or more schema branches did not match."
    case .anyOfFailed: return "No schema branch matched."
    case .oneOfFailed: return "Expected exactly one matching schema branch."
    case .notFailed: return "Value matches the schema forbidden by 'not'."
    case .conditionalFailed(let condition, _): return "Value does not satisfy the '" + safe(condition) + "' branch."
    case .invalidDependentSchema(let key, _): return "Value does not satisfy the schema required by '" + safe(key) + "'."
    case .unevaluatedItemsFailed: return "Unevaluated array items do not satisfy the schema."
    case .unevaluatedPropertyFailed: return "Unevaluated properties do not satisfy the schema."
    case .invalidReference: return "Referenced schema is not available locally."
    case .referenceValidationFailure: return "Value does not satisfy the referenced schema. See branch details."
    case .keywordFailure(let keyword, _): return "Value does not satisfy '" + safe(keyword) + "'. See branch details."
    }
  }
}
