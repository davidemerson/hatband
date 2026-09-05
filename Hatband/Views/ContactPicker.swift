import Contacts
import ContactsUI
import SwiftUI
import UIKit

/// `CNContactPickerViewController`: one contact, no Contacts permission.
@MainActor struct ContactPicker: UIViewControllerRepresentable {
    let onPick: (CNContact) -> Void
    @Environment(\.dismiss) private var dismiss

    init(onPick: @escaping (CNContact) -> Void) {
        self.onPick = onPick
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onDone: { dismiss() })
    }

    @MainActor final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onPick: (CNContact) -> Void
        private let onDone: () -> Void

        init(onPick: @escaping (CNContact) -> Void, onDone: @escaping () -> Void) {
            self.onPick = onPick
            self.onDone = onDone
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(contact)
            onDone()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onDone()
        }
    }
}
