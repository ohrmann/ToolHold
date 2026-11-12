import Foundation

extension JSONModelEmitter {
    func renderTypeScript(root: String) throws {
        if graph.shapes[0].object == nil || graph.objects[graph.shapes[0].object!].fields.isEmpty {
            try line("export type \(options.rootName) = \(root);"); try line()
        }
        try renderObjects { id, object in
            guard !object.fields.isEmpty else { return }
            try line("export interface \(names[id]) {")
            for field in object.fields {
                let optional = field.presentCount < object.sampleCount ? "?" : ""
                try line("\(literal(field.key))\(optional): \(type(field.shape));", 1)
            }
            try line("}"); try line()
        }
    }
}
