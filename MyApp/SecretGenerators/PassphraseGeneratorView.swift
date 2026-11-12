import SwiftUI

struct PassphraseGeneratorView: View {
    let workspace: SecretGeneratorWorkspaceSession
    var body: some View { SecretGeneratorView(workspace: workspace).navigationTitle("Passphrase Generator") }
}
