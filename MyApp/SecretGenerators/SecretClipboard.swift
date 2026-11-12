#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor enum SecretClipboard {
    static func copy(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.prepareForNewContents(with: .currentHostOnly)
        NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: value]], options: [.localOnly: true])
        #endif
    }
}
