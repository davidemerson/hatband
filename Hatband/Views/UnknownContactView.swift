import Contacts
import ContactsUI
import HatbandCore
import SwiftUI
import UIKit

/// `CNContactViewController(forUnknownContact:)` in a navigation controller:
/// the system offers "Create New Contact" and "Add to Existing Contact".
/// The contact carries the card's name (split as `VCard` does), company,
/// phone, email, labelled links, image and an optional "Met" date. Never
/// an address, a note or coordinates.
@MainActor struct UnknownContactView: UIViewControllerRepresentable {
    let person: Person
    let met: Date?
    @Environment(\.dismiss) private var dismiss

    init(person: Person, met: Date?) {
        self.person = person
        self.met = met
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CNContactViewController(forUnknownContact: UnknownContactView.contact(for: person, met: met))
        controller.allowsActions = false
        controller.allowsEditing = true
        controller.delegate = context.coordinator
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.finish))
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: { dismiss() })
    }

    static func contact(for person: Person, met: Date?) -> CNContact {
        let card = person.card
        let contact = CNMutableContact()
        if let name = card.name {
            let split = VCard(formattedName: name)
            contact.givenName = split.givenName
            contact.familyName = split.familyName
        }
        if let company = card.company {
            contact.organizationName = company
        }
        if let phone = card.phone {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))]
        }
        if let email = card.email {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)]
        }
        var urls: [CNLabeledValue<NSString>] = []
        for row in Links.rows(for: card) {
            guard let url = row.url, url.lowercased().hasPrefix("http") else { continue }
            urls.append(CNLabeledValue(label: row.label, value: url as NSString))
        }
        contact.urlAddresses = urls
        if let photo = card.photo {
            contact.imageData = Data(photo)
        }
        if let met {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: met)
            contact.dates = [CNLabeledValue(label: "Met", value: components as NSDateComponents)]
        }
        return contact
    }

    /// `CNContactViewControllerDelegate` is not main-actor annotated, so the
    /// method is `nonisolated` and hops back; the controller calls it on
    /// the main thread.
    @MainActor final class Coordinator: NSObject, CNContactViewControllerDelegate {
        private let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        /// The Done button's target; UIKit sends it on the main thread.
        @objc func finish() {
            onDone()
        }

        nonisolated func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            MainActor.assumeIsolated {
                self.onDone()
            }
        }
    }
}
