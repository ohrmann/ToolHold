import Foundation

extension JSONModelEmitter {
    func renderJava(root: String) throws {
        try line("import com.fasterxml.jackson.annotation.JsonProperty;")
        try line("import com.fasterxml.jackson.annotation.JsonAnyGetter;")
        try line("import com.fasterxml.jackson.annotation.JsonAnySetter;")
        try line("import com.fasterxml.jackson.core.type.TypeReference;")
        try line("import com.fasterxml.jackson.databind.*;")
        try line("import java.math.BigInteger;")
        try line("import java.math.BigDecimal;")
        try line("import java.util.List;"); try line()
        try line("public final class \(options.rootName) {")
        try line("public static \(root) fromJson(String json) throws java.io.IOException {", 1)
        try line("ObjectMapper mapper = new ObjectMapper();", 2)
        try line("mapper.enable(DeserializationFeature.USE_BIG_INTEGER_FOR_INTS);", 2)
        try line("mapper.enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS);", 2)
        try line("mapper.disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);", 2)
        try line("return mapper.readValue(json, new TypeReference<\(root)>() {});", 2)
        try line("}", 1); try line()
        try renderObjects { id, object in
            let isRoot = object.shape == 0
            let depth = isRoot ? 1 : 2
            if !isRoot { try line("public static final class \(names[id]) {", 1) }
            for (i, field) in object.fields.enumerated() {
                if !field.key.isEmpty { try line("@JsonProperty(\(literal(field.key)))", depth) }
                try line("\(field.key.isEmpty ? "private" : "public") \(type(field.shape)) \(fields[id][i]);", depth)
            }
            // JsonProperty("") means "use the Java field name", not an empty wire name.
            // AnySetter/Getter provide an exact empty-key bridge without a JSON parser.
            if let index = object.fields.firstIndex(where: { $0.key.isEmpty }) {
                let fieldType = type(object.fields[index].shape), fieldName = fields[id][index]
                var helpers = JSONModelNaming.Scope()
                helpers.used.formUnion(object.fields.map(\.key))
                helpers.used.formUnion(fields[id])
                let setter = helpers.allocate("toolboxReadAdditionalProperty")
                let getter = helpers.allocate("toolboxAdditionalProperties")
                try line("public \(fieldType) emptyMemberValue() { return \(fieldName); }", depth)
                try line("@JsonAnySetter", depth)
                try line("public void \(setter)(String key, JsonNode value) {", depth)
                try line("if (key.isEmpty()) {", depth + 1)
                try line("ObjectMapper mapper = new ObjectMapper();", depth + 2)
                try line("mapper.enable(DeserializationFeature.USE_BIG_INTEGER_FOR_INTS);", depth + 2)
                try line("mapper.enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS);", depth + 2)
                try line("mapper.disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);", depth + 2)
                try line("\(fieldName) = mapper.convertValue(value, new TypeReference<\(fieldType)>() {});", depth + 2)
                try line("}", depth + 1); try line("}", depth)
                try line("@JsonAnyGetter", depth)
                try line("public java.util.Map<String, Object> \(getter)() {", depth)
                try line("return java.util.Collections.singletonMap(\"\", \(fieldName));", depth + 1)
                try line("}", depth)
            }
            if !isRoot { try line("}", 1) }
            try line()
        }
        try line("}")
    }
}
