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

    /// `CNContactPickerDelegate` is not main-actor annotated, so its methods
    /// are `nonisolated` here and hop back explicitly; the picker calls them
    /// on the main thread.
    @MainActor final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onPick: (CNContact) -> Void
        private let onDone: () -> Void

        init(onPick: @escaping (CNContact) -> Void, onDone: @escaping () -> Void) {
            self.onPick = onPick
            self.onDone = onDone
        }

        nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            // Delivered on the main thread; CNContact is immutable but not Sendable.
            nonisolated(unsafe) let picked = contact
            MainActor.assumeIsolated {
                self.onPick(picked)
                self.onDone()
            }
        }

        nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            MainActor.assumeIsolated {
                self.onDone()
            }
        }
    }
}
