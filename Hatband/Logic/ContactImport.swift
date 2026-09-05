import Contacts
import Foundation
import HatbandCore

/// A picked contact into a profile. Every value goes through `Normalize`;
/// one that does not normalise is skipped and the base value kept. Only
/// keys the picker made available are read.
nonisolated enum ContactImport {
    static func profile(from contact: CNContact, into base: Profile) -> Profile {
        var profile = base
        if contact.isKeyAvailable(CNContactGivenNameKey), contact.isKeyAvailable(CNContactFamilyNameKey) {
            let parts = [contact.givenName, contact.familyName].map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let name = parts.filter { !$0.isEmpty }.joined(separator: " ")
            if !name.isEmpty {
                profile.name = name
            }
        }
        if contact.isKeyAvailable(CNContactOrganizationNameKey) {
            let company = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !company.isEmpty {
                profile.company = company
            }
        }
        if contact.isKeyAvailable(CNContactPhoneNumbersKey) {
            for labeled in contact.phoneNumbers {
                if let phone = try? Normalize.phone(labeled.value.stringValue) {
                    profile.phone = phone
                    break
                }
            }
        }
        if contact.isKeyAvailable(CNContactEmailAddressesKey) {
            for labeled in contact.emailAddresses {
                if let email = try? Normalize.email(labeled.value as String) {
                    profile.email = email
                    break
                }
            }
        }
        if contact.isKeyAvailable(CNContactUrlAddressesKey) {
            for labeled in contact.urlAddresses {
                apply(url: labeled.value as String, to: &profile)
            }
        }
        return profile
    }

    /// Known hosts go to their own field; anything else is the website.
    private static func apply(url: String, to profile: inout Profile) {
        let lower = url.lowercased()
        if lower.contains("github.com") {
            if profile.github == nil, let user = try? Normalize.github(url) {
                profile.github = user
            }
            return
        }
        if lower.contains("linkedin.com") {
            if profile.linkedin == nil, let slug = try? Normalize.linkedin(url) {
                profile.linkedin = slug
            }
            return
        }
        if lower.contains("calendly.com") {
            if profile.calendly == nil, let path = try? Normalize.calendly(url) {
                profile.calendly = path
            }
            return
        }
        if profile.website == nil, let site = try? Normalize.website(url) {
            profile.website = Website(address: site.address, insecure: site.insecure)
        }
    }
}
