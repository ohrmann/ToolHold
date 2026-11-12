import SwiftUI

struct NumberConverterView: View {
  @Bindable var workspace: CalculationWorkspace<NumberCalculationRequest>
  @AppStorage("developerToolbox.number.uppercase") private var uppercase = true
  @AppStorage("developerToolbox.number.group") private var group = false
  var body: some View {
    CalculationPanels {
      VStack(alignment: .leading, spacing: 14) {
        Text("Exact integer bases 2–36, or a fixed-width bit pattern.").foregroundStyle(.secondary)
        Picker(
          "Mode",
          selection: Binding(
            get: { workspace.request.bitPattern },
            set: { bit in
              if workspace.request.bitPattern {
                workspace.request.patternDraft = workspace.request.input
              } else {
                workspace.request.integerDraft = workspace.request.input
              }
              workspace.request.bitPattern = bit
              workspace.request.encode = false
              workspace.request.input =
                bit ? workspace.request.patternDraft : workspace.request.integerDraft
              if bit && ![2, 8, 16].contains(workspace.request.radix) {
                workspace.request.radix = 16
              }
            })
        ) {
          Text("Integer").tag(false)
          Text("Bit Pattern").tag(true)
        }.pickerStyle(.segmented)
        UtilityLabeledField(
          title: "Input", text: $workspace.request.input, placeholder: "Enter an integer")
        Picker("Input base", selection: $workspace.request.radix) {
          ForEach(workspace.request.bitPattern ? [2, 8, 16] : Array(2...36), id: \.self) {
            Text(String($0)).tag($0)
          }
        }
        if !workspace.request.bitPattern {
          Picker("Additional output base", selection: $workspace.request.outputRadix) {
            ForEach(2...36, id: \.self) { Text(String($0)).tag($0) }
          }
          Toggle("Signed integer", isOn: $workspace.request.signed)
          Toggle("Uppercase digits", isOn: $workspace.request.uppercase).onChange(
            of: workspace.request.uppercase
          ) { _, v in uppercase = v }
          Toggle("Group displayed digits", isOn: $workspace.request.group).onChange(
            of: workspace.request.group
          ) { _, v in group = v }
          Toggle("Show base prefixes", isOn: $workspace.request.prefix)
        }
        HStack {
          Text("Bit width")
          UtilityField(title: "Bit width", text: $workspace.request.width).frame(minHeight: 30)
        }
        Text(
          "Width 1–4096. A pattern must fit exactly; no truncation or wraparound. Signed encoding uses two’s complement."
        ).font(.caption).foregroundStyle(.secondary)
        HStack {
          Button("Convert") {
            workspace.request.encode = false
            workspace.run()
          }.keyboardShortcut(.return, modifiers: .command)
          if !workspace.request.bitPattern {
            Button("Encode at Width") {
              workspace.request.encode = true
              workspace.run()
            }
          }
          Button("Clear") {
            workspace.request.input = ""
            workspace.cancel()
          }
        }
        Toggle("Calculate after editing", isOn: $workspace.automatic)
        Text(
          "Up to 4096 input digits. Prefixes are recognized only for their matching base. Underscores may separate digits. Fractions and exponent notation are not interpreted; letters are ordinary digits in bases that support them."
        ).font(.caption).foregroundStyle(.secondary)
      }
    } output: {
      CalculationResults(workspace: workspace)
    }

  }
}
