// Dialect-specific extensions to the pinned MIT evaluator. No source rewriting.
import Foundation

extension Keywords {
    struct LegacyItems: ApplicatorKeyword {
        static let name = "items"
        let value: JSONValue
        let context: KeywordContext
        let tuple: PrefixItems?
        let single: Items?
        init(value: JSONValue, context: KeywordContext) {
            self.value = value; self.context = context
            tuple = value.array == nil ? nil : PrefixItems(value: value, context: context)
            single = value.array == nil ? Items(value: value, context: context) : nil
        }
        typealias AnnotationValue = Never
        func validate(_ input: JSONValue, at location: JSONPointer, using annotations: inout AnnotationContainer) throws(ValidationIssue) {
            if let tuple { try tuple.validate(input, at: location, using: &annotations) }
            if let single { try single.validate(input, at: location, using: &annotations) }
        }
    }
    struct AdditionalItems: ApplicatorKeyword {
        static let name = "additionalItems"
        let value: JSONValue
        let context: KeywordContext
        let items: Items
        let tupleCount: Int?
        let target: Schema
        init(value: JSONValue, context: KeywordContext) {
            self.value = value; self.context = context; items = Items(value: value, context: context)
            tupleCount = context.context.documentCache[context.uri.withoutFragment ?? context.uri]?.value(at: context.location.dropLast().appending(.key("items")))?.array?.count
            target = value.extractSubschema(using: context)
        }
        typealias AnnotationValue = Never
        func validate(_ input: JSONValue, at location: JSONPointer, using annotations: inout AnnotationContainer) throws(ValidationIssue) {
            // Only applies when the sibling items keyword contains a tuple.
            guard let tupleCount, let array = input.array else { return }
            var builder = ValidationResultBuilder(keyword: self, instanceLocation: location)
            for index in array.indices.dropFirst(tupleCount) {
                guard SchemaRuntime.check() else { throw .evaluationFailed(errors: []) }
                builder.merging(try target.validateSubschema(array[index], at: location.appending(.index(index))).requiringComplete())
            }
            try builder.throwIfErrors()
            annotations.insert(keyword: items, at: location, value: true)
        }
    }
    struct LegacyDependencies: ApplicatorKeyword {
        static let name = "dependencies"
        let value: JSONValue
        let context: KeywordContext
        let schemas: OrderedDictionary<String, Schema>
        init(value: JSONValue, context: KeywordContext) {
            self.value = value; self.context = context
            schemas = OrderedDictionary(uniqueKeysWithValues: value.object?.compactMap { key, value in
                guard value.array == nil, let schema = try? Schema(rawSchema: value, location: context.location.appending(.key(key)), context: context.context, baseURI: context.uri) else { return nil }
                return (key, schema)
            } ?? [])
        }
        typealias AnnotationValue = Never
        func validate(_ input: JSONValue, at location: JSONPointer, using annotations: inout AnnotationContainer) throws(ValidationIssue) {
            guard let object = input.object else { return }
            var builder = ValidationResultBuilder(keyword: self, instanceLocation: location)
            for (key, raw) in value.object ?? [:] where object[key] != nil {
                guard SchemaRuntime.check() else { throw .evaluationFailed(errors: []) }
                if let names = raw.array {
                    for name in names.compactMap(\.string) where object[name] == nil { throw .missingRequiredProperty(key: name) }
                } else if let schema = schemas[key] {
                    var child = AnnotationContainer()
                    let result = try schema.validate(input, at: location, annotations: &child).requiringComplete()
                    builder.merging(result)
                    if result.isValid { annotations.merge(child) }
                }
            }
            try builder.throwIfErrors()
        }
    }
    struct LegacyRecursiveAnchor: IdentifierKeyword {
        static let name = "$recursiveAnchor"
        let value: JSONValue
        let context: KeywordContext
        init(value: JSONValue, context: KeywordContext) { self.value = value; self.context = context }
        func processIdentifier() {
            if value.boolean == true { context.context.registerDynamicAnchor("", at: context.location.dropLast(), baseURI: context.uri) }
        }
    }
    struct LegacyRecursiveReference: ReferenceKeyword {
        static let name = "$recursiveRef"
        let value: JSONValue
        let context: KeywordContext
        init(value: JSONValue, context: KeywordContext) { self.value = value; self.context = context }
        func validate(_ input: JSONValue, at location: JSONPointer, using annotations: inout AnnotationContainer, with engine: SchemaEngineContext, baseURI: URL?) throws(ValidationIssue) {
            let target: Schema
            do { target = try ReferenceResolver(context: engine, referenceURI: value.string ?? "", location: context.location, baseURI: context.uri).resolveSchema(for: value.string ?? "", isDynamic: true) }
            catch { SchemaRuntime.current?.fail(.unresolvedReference); throw .invalidReference("Recursive reference could not be resolved locally.") }
            var child = AnnotationContainer()
            let result = try target.validate(input, at: location, annotations: &child).requiringComplete()
            if !result.isValid { throw .referenceValidationFailure(ref: value.string ?? "", errors: result.errors ?? []) }
            annotations.merge(child)
        }
    }
}
