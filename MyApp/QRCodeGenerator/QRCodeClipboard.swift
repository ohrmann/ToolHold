import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor enum QRCodeClipboard {
    static func copy(_ data: Data) {
        #if os(macOS)
        NSPasteboard.general.prepareForNewContents(with:.currentHostOnly)
        NSPasteboard.general.setData(data,forType:.png)
        #else
        UIPasteboard.general.setItems([[UTType.png.identifier:data]],options:[.localOnly:true])
        #endif
    }
}
