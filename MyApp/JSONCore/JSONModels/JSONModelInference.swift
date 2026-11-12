import Foundation

enum JSONModelInference {
    static func infer(_ document: JSONStructureDocument) throws -> JSONModelGraph {
        for node in document.nodes {
            if node.id & 255 == 0 { try Task.checkCancellation() }
            if node.occurrence > 1 {
                let first = node.parent.flatMap { parent in
                    document.nodes[parent].children.first { id in
                        document.nodes[id].occurrence == 1 && Data((document.nodes[id].key ?? "").utf8) == Data((node.key ?? "").utf8)
                    }
                }
                throw JSONModelFailure(status: .unsupported, code: "MODEL-DUPLICATE-KEY",
                    message: "Duplicate member names cannot be represented reliably by these models.",
                    range: node.keyRange, related: first.flatMap { document.nodes[$0].keyRange })
            }
        }
        var builder = Builder(document: document)
        builder.shapes.append(JSONModelShape(path: [], sourceNode: 0))
        try builder.add(0, to: 0)
        return JSONModelGraph(document: document, shapes: builder.shapes, objects: builder.objects)
    }

    private struct Builder {
        let document: JSONStructureDocument
        var shapes: [JSONModelShape] = []
        var objects: [JSONModelObject] = []
        mutating func newShape(path: [String], node: Int) -> Int {
            let id = shapes.count
            shapes.append(JSONModelShape(path: path, sourceNode: node))
            return id
        }
        mutating func add(_ nodeID: Int, to shapeID: Int) throws {
            try Task.checkCancellation()
            let node = document.nodes[nodeID]
            switch node.kind {
            case .null: shapes[shapeID].nullable = true
            case .boolean: shapes[shapeID].boolean = true
            case .string: shapes[shapeID].string = true
            case .number: shapes[shapeID].numbers.append(nodeID)
            case .array:
                let element: Int
                if let existing = shapes[shapeID].element { element = existing }
                else {
                    element = newShape(path: shapes[shapeID].path + ["Item"], node: nodeID)
                    shapes[shapeID].element = element
                }
                for child in node.children { try add(child, to: element) }
            case .object:
                let object: Int
                if let existing = shapes[shapeID].object { object = existing }
                else {
                    object = objects.count
                    objects.append(JSONModelObject(shape: shapeID))
                    shapes[shapeID].object = object
                }
                objects[object].sampleCount += 1
                for childID in node.children {
                    let child = document.nodes[childID], key = child.key ?? ""
                    let identity = Data(key.utf8)
                    let field: Int
                    if let existing = objects[object].keyIndices[identity] { field = existing }
                    else {
                        let valueShape = newShape(path: shapes[shapeID].path + [key], node: childID)
                        field = objects[object].fields.count
                        objects[object].fields.append(JSONModelField(key: key, shape: valueShape, sourceNode: childID, presentCount: 0))
                        objects[object].keyIndices[identity] = field
                    }
                    objects[object].fields[field].presentCount += 1
                    try add(childID, to: objects[object].fields[field].shape)
                }
            }
        }
    }
}
