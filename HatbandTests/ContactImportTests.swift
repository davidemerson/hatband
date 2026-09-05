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
