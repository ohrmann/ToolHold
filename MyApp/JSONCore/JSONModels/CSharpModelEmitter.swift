import Foundation

extension JSONModelEmitter {
    func renderCSharp(root: String) throws {
        try line("#nullable enable")
        try line("using System.Collections.Generic;")
        try line("using System.Text.Json;")
        try line("using System.Text.Json.Serialization;"); try line()
        try line("public static class \(options.rootName)Json {")
        try line("public static \(root) Decode(string json) => JsonSerializer.Deserialize<\(root)>(json)!;", 1)
        try line("}"); try line()
        try renderObjects { id, object in
            try line("public sealed class \(names[id]) {")
            for (i, field) in object.fields.enumerated() {
                let missing = field.presentCount < object.sampleCount
                let valueType = type(field.shape, missing: missing)
                try line("[JsonPropertyName(\(literal(field.key)))]", 1)
                try line("public \(missing ? "" : "required ")\(valueType) \(fields[id][i]) { get; set; }", 1)
            }
            try line("}"); try line()
        }
    }
}
