import SwiftUI

/// Full selected value is prepared only on explicit request, off the main actor.
struct JSONTreeNodeDetails: View {
    let document: JSONStructureDocument
    let nodeID: Int
    @Environment(\.dismiss) private var dismiss
    @State private var content: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                if let content {
                    JSONTextEditor(text: .constant(content), editable: false,
                        options: JSONEditorOptions(syntaxHighlighting: false, rainbowBrackets: false, matchingBrackets: false, wordWrap: true))
                    Text("Controls and directional formatting characters are shown as escapes. Copy Value preserves the exact decoded text.")
                        .font(.caption).foregroundStyle(.secondary)
                } else { ProgressView("Preparing selected value…") }
            }.padding()
            .navigationTitle("Selected Node")
            .toolbar { Button("Done") { dismiss() } }
        }
        .frame(minWidth: 300, idealWidth: 600, minHeight: 300, idealHeight: 450)
        .task(id: document.snapshotID) {
            let document = document, nodeID = nodeID
            let worker = Task.detached(priority: .userInitiated) {
                let node = document.nodes[nodeID], path = document.path(nodeID)
                let header = node.kind.rawValue + " · " + Self.safe(node.name) + "\n" + Self.safe(path.jsonPath)
                    + (path.ambiguous ? "\nAmbiguous path — duplicate field name." : "")
                return header + "\n\n" + Self.safe(node.scalar ?? node.summary)
            }
            let value = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            content = value
        }
    }
    nonisolated private static func safe(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if Task.isCancelled { return "" }
            switch scalar.value {
            case 0...31, 127...159, 0x061C, 0x200E...0x200F, 0x2028...0x202E, 0x2066...0x2069:
                result += String(format: "\\u{%04X}", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
