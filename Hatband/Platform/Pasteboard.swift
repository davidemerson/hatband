import UIKit
import UniformTypeIdentifiers

/// The only pasteboard access: local to this device, gone after a minute.
@MainActor enum Pasteboard {
    static func copy(_ text: String) {
        let item: [String: Any] = [UTType.utf8PlainText.identifier: text]
        let options: [UIPasteboard.OptionsKey: Any] = [
            .localOnly: true,
            .expirationDate: Date().addingTimeInterval(60),
        ]
        UIPasteboard.general.setItems([item], options: options)
    }
}
