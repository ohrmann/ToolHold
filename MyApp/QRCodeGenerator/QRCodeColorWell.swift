import SwiftUI

/// Local controls avoid NSColorPanel's shared responder-chain color actions,
/// which can also recolor the text view that was editing the QR payload.
struct QRCodeColorWell: View {
    @Binding var color: QRColor
    let label: String
    let identifier: String
    @State private var choosing = false
    var body: some View {
        Button { choosing.toggle() } label: {
            RoundedRectangle(cornerRadius:6)
                .fill(Color(.sRGB,red:color.r,green:color.g,blue:color.b,opacity:1))
                .overlay { RoundedRectangle(cornerRadius:6).strokeBorder(.secondary,lineWidth:1) }
                .padding(3).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(label).accessibilityValue(color.hex)
            .accessibilityIdentifier(identifier)
            .popover(isPresented:$choosing) {
                QRCodeColorPalette(color:$color,label:label,identifier:identifier)
                    .presentationCompactAdaptation(.popover)
            }
    }
}

struct QRCodeColorPalette: View {
    @Binding var color: QRColor
    let label: String
    let identifier: String
    private static let colors: [(String,QRColor)] = [
        ("Black",.init(0,0,0)),("Charcoal",.init(0.22,0.22,0.22)),("Gray",.init(0.5,0.5,0.5)),("Silver",.init(0.75,0.75,0.75)),("Light gray",.init(0.9,0.9,0.9)),("White",.init(1,1,1)),
        ("Red",.init(0.8,0.12,0.16)),("Orange",.init(0.95,0.4,0.08)),("Yellow",.init(0.95,0.75,0.1)),("Green",.init(0.12,0.6,0.3)),("Blue",.init(0.12,0.32,0.65)),("Purple",.init(0.5,0.2,0.7)),
        ("Dark red",.init(0.4,0.05,0.1)),("Brown",.init(0.4,0.22,0.08)),("Olive",.init(0.35,0.35,0.08)),("Dark green",.init(0.04,0.3,0.18)),("Navy",.init(0.04,0.12,0.32)),("Dark purple",.init(0.25,0.08,0.38)),
        ("Pink",.init(1,0.65,0.7)),("Peach",.init(1,0.75,0.55)),("Cream",.init(1,0.94,0.65)),("Mint",.init(0.65,0.9,0.75)),("Light blue",.init(0.65,0.8,1)),("Lavender",.init(0.82,0.7,0.95))
    ]
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(label).font(.headline)
            // Explicit sRGB fills stay colorful even when the selected color is black.
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:6),spacing:4) {
                ForEach(Self.colors.indices,id:\.self) { index in
                    let swatch = Self.colors[index]
                    Button { color = swatch.1 } label: {
                        RoundedRectangle(cornerRadius:4)
                            .fill(Color(.sRGB,red:swatch.1.r,green:swatch.1.g,blue:swatch.1.b,opacity:1))
                            .overlay { RoundedRectangle(cornerRadius:4).strokeBorder(.secondary,lineWidth:1) }
                            .padding(3).frame(minHeight:40).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(swatch.0)
                        .accessibilityValue(swatch.1.hex)
                        .accessibilityIdentifier(identifier+"-swatch-\(index)")
                }
            }
            channel("Red",\QRColor.r,tint:.red)
            channel("Green",\QRColor.g,tint:.green)
            channel("Blue",\QRColor.b,tint:.blue)
            Text(color.hex).font(.caption.monospaced()).textSelection(.enabled)
        }.padding(16).frame(width:300)
    }
    private func channel(_ name: String,_ key: WritableKeyPath<QRColor,Double>,tint: Color) -> some View {
        HStack {
            Text(name).font(.caption).frame(width:42,alignment:.leading)
            Slider(value:Binding(get:{color[keyPath:key]},set:{color[keyPath:key]=$0}),in:0...1)
                .tint(tint).accessibilityLabel(label+" "+name)
                .accessibilityIdentifier(identifier+"-"+name.lowercased())
            Text("\(Int((color[keyPath:key]*255).rounded()))").font(.caption.monospacedDigit()).frame(width:26,alignment:.trailing)
        }
    }
}
