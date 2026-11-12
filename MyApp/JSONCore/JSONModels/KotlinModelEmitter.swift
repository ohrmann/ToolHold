import Foundation

extension JSONModelEmitter {
    func renderKotlin(root: String) throws {
        try line("import kotlinx.serialization.*")
        try line("import kotlinx.serialization.json.*")
        try line("import kotlinx.serialization.descriptors.SerialDescriptor")
        try line("import kotlinx.serialization.encoding.Decoder")
        try line("import kotlinx.serialization.encoding.Encoder"); try line()
        if graph.shapes[0].object == nil { try line("typealias \(options.rootName) = \(root)"); try line() }
        try renderObjects { id, object in
            if object.fields.isEmpty { try line("@Serializable class \(names[id])"); try line(); return }
            try line("@Serializable")
            try line("data class \(names[id])(")
            for (i, field) in object.fields.enumerated() {
                let missing = field.presentCount < object.sampleCount
                let valueType = type(field.shape, missing: missing)
                try line("@SerialName(\(literal(field.key)))", 1)
                try line("val \(fields[id][i]): \(valueType)\(missing ? " = null" : "")\(i + 1 < object.fields.count ? "," : "")", 1)
            }
            try line(")"); try line()
        }
        if needsDynamic {
            for codeLine in Self.kotlinDynamicHelper.components(separatedBy: "\n") {
                let count = codeLine.prefix(while: { $0 == " " }).count
                try line(String(codeLine.dropFirst(count)), count / 4)
            }
        }
    }
    private static let kotlinDynamicHelper = """
    @Serializable(with = ToolboxJSONValueSerializer::class)
    data class ToolboxJSONValue(val value: JsonElement)

    @OptIn(ExperimentalSerializationApi::class)
    object ToolboxJSONValueSerializer : KSerializer<ToolboxJSONValue> {
        override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor
        override fun deserialize(decoder: Decoder): ToolboxJSONValue =
            ToolboxJSONValue((decoder as JsonDecoder).decodeJsonElement())
        override fun serialize(encoder: Encoder, value: ToolboxJSONValue) {
            (encoder as JsonEncoder).encodeJsonElement(rawNumbers(value.value))
        }
        private fun rawNumbers(value: JsonElement): JsonElement = when (value) {
            is JsonObject -> JsonObject(value.mapValues { rawNumbers(it.value) })
            is JsonArray -> JsonArray(value.map { rawNumbers(it) })
            is JsonPrimitive -> if (value.isString || value === JsonNull) value
                else JsonUnquotedLiteral(value.content)
        }
    }
    """
}
