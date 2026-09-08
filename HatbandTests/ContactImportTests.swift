import Contacts
import HatbandCore
import Testing
@testable import Hatband

struct ContactImportTests {
    @Test func mapsContactThroughNormalize() {
        let contact = CNMutableContact()
        contact.givenName = "Leopold"
        contact.familyName = "Bloom"
        contact.organizationName = "Freeman's Journal"
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+353 87 123 4567"))]
        contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: "D@Example.com" as NSString)]
        contact.urlAddresses = [
            CNLabeledValue(label: CNLabelURLAddressHomePage, value: "https://github.com/lbloom" as NSString),
            CNLabeledValue(label: CNLabelOther, value: "https://nnix.com/~bloom" as NSString),
        ]
        let profile = ContactImport.profile(from: contact, into: Profile())
        #expect(profile.name == "Leopold Bloom")
        #expect(profile.company == "Freeman's Journal")
        #expect(profile.phone == "+353871234567")
        #expect(profile.email == "D@example.com")
        #expect(profile.github == "lbloom")
        #expect(profile.website == Website(address: "nnix.com/~bloom", insecure: false))
    }

    /// Contacts holds domestic numbers in national form, which is not E.164,
    /// so the profile keeps nothing and the raw number is what onboarding
    /// shows. Found on a phone: the name and website imported, the number
    /// vanished without a word.
    @Test func nationalNumbersAreKeptRawForTheReader() {
        for national in ["(555) 123-4567", "555-123-4567", "020 7946 0958", "087 123 4567"] {
            let contact = CNMutableContact()
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile,
                                                   value: CNPhoneNumber(stringValue: national))]
            #expect(ContactImport.profile(from: contact, into: Profile()).phone == nil)
            #expect(ContactImport.rawPhone(from: contact) == national)
        }
    }

    /// An E.164 number needs no rescuing, and an absent one offers nothing.
    @Test func rawPhoneIsTheFirstNonEmptyNumberOrNothing() {
        let good = CNMutableContact()
        good.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile,
                                            value: CNPhoneNumber(stringValue: "+353 87 123 4567"))]
        #expect(ContactImport.profile(from: good, into: Profile()).phone == "+353871234567")
        #expect(ContactImport.rawPhone(from: good) == "+353 87 123 4567")

        #expect(ContactImport.rawPhone(from: CNMutableContact()) == nil)

        let blank = CNMutableContact()
        blank.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "  "))]
        #expect(ContactImport.rawPhone(from: blank) == nil)
    }

    @Test func invalidValuesSkipped() {
        var base = Profile()
        base.name = "Henry Flower"
        base.email = "henry@flower.ie"
        let contact = CNMutableContact()
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "12345"))]
        contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: "not an address" as NSString)]
        contact.urlAddresses = [CNLabeledValue(label: CNLabelOther, value: "javascript:alert(1)" as NSString)]
        let profile = ContactImport.profile(from: contact, into: base)
        #expect(profile.phone == nil)
        #expect(profile.name == "Henry Flower")
        #expect(profile.email == "henry@flower.ie")
        #expect(profile.website == nil)
        #expect(profile == base)
    }
}
