// Vendored MIT: ajevans99/swift-json-schema @ 8d314b50; see ThirdPartyNotices/SwiftJSONSchema.
/// A private-to-the-internal validation tree used by the builder to select branches
/// without revalidating detached schemas in a different reference or format context.
internal struct SchemaEvaluation: Sendable {
  internal let schema: JSONValue
  internal let instance: JSONValue
  internal let result: ValidationResult
  internal let children: [SchemaEvaluation]
  internal let reference: String?

  @TaskLocal internal static var referenceKeyword: String?
  @TaskLocal private static var recorder: Recorder?

  static func withoutRecording<Result>(_ operation: () -> Result) -> Result {
    $recorder.withValue(nil) {
      $referenceKeyword.withValue(nil, operation: operation)
    }
  }

  private final class Recorder: Sendable {
    let evaluations = LockIsolated<[SchemaEvaluation]>([])
  }

  internal func child(
    schemaTokens: [String],
    instanceTokens: [String] = [],
    instance: JSONValue,
    schema: JSONValue? = nil
  ) -> SchemaEvaluation? {
    let schemaLocation = result.keywordLocation.appending(pointer: .init(tokens: schemaTokens))
    let instanceLocation = result.instanceLocation.appending(pointer: .init(tokens: instanceTokens))
    return children.first {
      $0.reference == nil
        && $0.result.keywordLocation == schemaLocation
        && $0.result.instanceLocation == instanceLocation
        && $0.instance == instance
        && (schema == nil || $0.schema == schema)
    }
  }

  static func record(
    _ schema: Schema,
    instance: JSONValue,
    validate: () -> ValidationResult
  ) -> ValidationResult {
    guard let recorder else { return validate() }
    let children = Recorder()
    let reference = referenceKeyword
    let result = $recorder.withValue(children) {
      $referenceKeyword.withValue(nil, operation: validate)
    }
    let evaluation = SchemaEvaluation(
      schema: schema.rawSchema,
      instance: instance,
      result: result,
      children: children.evaluations.withLock { $0 },
      reference: reference
    )
    recorder.evaluations.withLock { $0.append(evaluation) }
    return result
  }

  static func capture(_ schema: Schema, instance: JSONValue) -> SchemaEvaluation {
    let recorder = Recorder()
    let result = $recorder.withValue(recorder) {
      $referenceKeyword.withValue(nil) {
        SchemaEngineContext.withFreshEvaluation { schema.schema.validate(instance, at: .init()) }
      }
    }
    return SchemaEvaluation(
      schema: schema.rawSchema,
      instance: instance,
      result: result,
      children: recorder.evaluations.withLock { $0 },
      reference: nil
    )
  }
}

extension Schema {
  internal func evaluate(_ instance: JSONValue) -> SchemaEvaluation {
    SchemaEvaluation.capture(self, instance: instance)
  }
}
