import Foundation

extension JSONModelEmitter {
    func renderSwift(root: String) throws {
        try line("import Foundation"); try line()
        if graph.shapes[0].object == nil { try line("typealias \(options.rootName) = \(root)"); try line() }
        try renderObjects { id, object in
            try line("struct \(names[id]): Codable {")
            for (i, field) in object.fields.enumerated() {
                try line("let \(fields[id][i]): \(type(field.shape, missing: field.presentCount < object.sampleCount))", 1)
            }
            if !object.fields.isEmpty {
                try line(); try line("enum CodingKeys: String, CodingKey {", 1)
                for (i, field) in object.fields.enumerated() { try line("case \(fields[id][i]) = \(literal(field.key))", 2) }
                try line("}", 1)
            }
            try line("}"); try line()
        }
        if needsDynamic {
            // Fixed helper; no sample values or keys are embedded here.
            for codeLine in Self.swiftDynamicHelper.components(separatedBy: "\n") {
                let count = codeLine.prefix(while: { $0 == " " }).count
                try line(String(codeLine.dropFirst(count)), count / 4)
            }
        }
    }
    private static let swiftDynamicHelper = """
    indirect enum ToolboxJSONValue: Codable {
        case null, bool(Bool), string(String), number(Decimal)
        case array([ToolboxJSONValue]), object([String: ToolboxJSONValue])

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if value.decodeNil() { self = .null; return }
            if let boolean = try? value.decode(Bool.self) { self = .bool(boolean); return }
            if let string = try? value.decode(String.self) { self = .string(string); return }
            if var array = try? decoder.unkeyedContainer() {
                var result: [ToolboxJSONValue] = []
                while !array.isAtEnd { result.append(try array.decode(ToolboxJSONValue.self)) }
                self = .array(result); return
            }
            if let object = try? decoder.container(keyedBy: Key.self) {
                var result: [String: ToolboxJSONValue] = [:]
                for key in object.allKeys { result[key.stringValue] = try object.decode(ToolboxJSONValue.self, forKey: key) }
                self = .object(result); return
            }
            self = .number(try value.decode(Decimal.self))
        }

        func encode(to encoder: Encoder) throws {
            var value = encoder.singleValueContainer()
            switch self {
            case .null: try value.encodeNil()
            case .bool(let item): try value.encode(item)
            case .string(let item): try value.encode(item)
            case .number(let item): try value.encode(item)
            case .array(let items): try value.encode(items)
            case .object(let items): try value.encode(items)
            }
        }

        private struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
    }
    """
}
