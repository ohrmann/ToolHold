import SwiftUI

struct QRCodeDecodedResultView: View {
    let item: QRDecodedItem?
    @Binding var showsBytes: Bool
    @Binding var wordWrap: Bool
    @Binding var detailsExpanded: Bool
    let canOutput: Bool
    let copy: (QRDecodeOutput) -> Void
    let export: (Bool) -> Void
    let reveal: () -> Void
    private var displayed: String {
        guard let item else { return "" }
        return showsBytes ? item.bytes.map(QRDecodedPresentation.hexDump) ?? "" : item.text.map(QRDecodedPresentation.safeText) ?? ""
    }
    private var editorOptions: JSONEditorOptions {
        var options = JSONEditorOptions(); options.syntax = .plainText; options.syntaxHighlighting = false
        options.rainbowBrackets = false; options.matchingBrackets = false; options.wordWrap = wordWrap; return options
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text(item.map { "Code \($0.id+1) · \($0.kind)" } ?? "Decoded content").font(.headline).lineLimit(1)
                Spacer()
                Toggle("Bytes",isOn:$showsBytes).toggleStyle(.button).disabled(item?.bytes == nil)
                    .accessibilityIdentifier("qr-decoder-bytes")
                Toggle("Wrap",isOn:$wordWrap).toggleStyle(.button)
            }
            // This native editor remains in the same structural position across phase/selection/layout changes.
            JSONTextEditor(text:.constant(displayed),editable:false,options:editorOptions,contentName:"Decoded QR",showsLineNumbers:false)
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                .overlay(RoundedRectangle(cornerRadius:6).stroke(.separator.opacity(0.6)))
                .overlay(alignment:.topLeading) {
                    if item == nil { Text("Select a QR code to inspect its content").foregroundStyle(.secondary).padding(10).allowsHitTesting(false) }
                    else if item?.readable == false { Text("Possible QR code, but content is unreadable. Try a clearer image.").foregroundStyle(.secondary).padding(10).allowsHitTesting(false) }
                    else if !showsBytes && item?.text == nil { Text("Text interpretation is unavailable. Choose Bytes.").foregroundStyle(.secondary).padding(10).allowsHitTesting(false) }
                }
            ViewThatFits(in:.horizontal) {
                HStack { actions }
                VStack(alignment:.leading,spacing:8) { actions }
            }
            if let item {
                Text("\(item.bytes?.count ?? 0) decoded bytes · \(item.interpretation)").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if let text = item.text, QRDecodedPresentation.safeText(text) != text {
                    Text("Control and direction characters are shown as visible escapes. Copy Text and text export preserve the decoded text.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Details",isExpanded:$detailsExpanded) {
                    VStack(alignment:.leading,spacing:4) {
                        if item.readable {
                        if !item.version.isEmpty { Text("QR version \(item.version) · Correction \(item.correction)") }
                        if item.sequenceCount >= 0 { Text("Segment \(item.sequenceIndex+1) of \(item.sequenceCount) · Sequence \(item.sequenceID). This is not an assembled message.") }
                        Text("ECI marker: \(item.hasECI ? "Yes" : "No") · Mirrored: \(item.mirrored ? "Yes" : "No") · Inverted: \(item.inverted ? "Yes" : "No")")
                        Text("Bytes are the decoder’s standard content, without text transcoding. Text may use an inferred encoding.")
                        } else { Text("No verified payload or encoding metadata is available for this candidate.") }
                    }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.top,4)
                }
            }
        }
    }
    @ViewBuilder private var actions: some View {
        Menu("Copy",systemImage:"doc.on.doc") {
            Button("Copy Text") { copy(.text) }.disabled(item?.text == nil)
            Button("Copy Hex") { copy(.hex) }
            Button("Copy Base64") { copy(.base64) }
        }.disabled(!canOutput).accessibilityIdentifier("qr-decoder-copy")
        Menu("Export…",systemImage:"square.and.arrow.up") {
            Button("Text (.txt)") { export(true) }.disabled(item?.text == nil)
            Button("Decoded Bytes (.bin)") { export(false) }
        }.disabled(!canOutput).accessibilityIdentifier("qr-decoder-export")
        Button("Show in Image",systemImage:"viewfinder") { reveal() }.disabled(item == nil)
            .accessibilityIdentifier("qr-decoder-reveal")
    }
}
