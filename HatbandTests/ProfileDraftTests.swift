import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// `ProfileDraft.commit()` owns every message the profile editor shows and
/// the normalising that decides what is stored. It is the path every user
/// walks on first run, and both bugs found on a phone this week lived in it.
struct ProfileDraftTests {
    private func draft(name: String = "Leopold Bloom") -> ProfileDraft {
        var draft = ProfileDraft()
        draft.name = name
        return draft
    }

    private func field(_ label: String, _ value: String, kind: CustomKind = .text,
                       id: UUID = UUID()) -> ProfileDraft.CustomDraft {
        ProfileDraft.CustomDraft(id: id, label: label, value: value, kind: kind)
    }

    // MARK: - What commits

    @Test func aNameIsEnough() {
        let result = draft().commit()
        #expect(result.problems.isEmpty)
        #expect(result.profile?.name == "Leopold Bloom")
    }

    @Test func aMissingNameIsTheOneThingRefused() {
        var blank = ProfileDraft()
        blank.name = "   "
        let result = blank.commit()
        #expect(result.profile == nil)
        #expect(result.problems["name"] != nil)
    }

    /// Every channel is stored in its minimal form, and a pasted URL collapses
    /// to the slug the card carries.
    @Test func channelsAreStoredNormalised() {
        var d = draft()
        d.phone = "+353 87 123 4567"
        d.email = "D@Example.com"
        d.website = "https://nnix.com/~bloom"
        d.github = "https://github.com/lbloom"
        d.linkedin = "linkedin.com/in/leopold-bloom"
        d.calendly = "calendly.com/bloom/coffee"
        let profile = d.commit().profile
        #expect(profile?.phone == "+353871234567")
        #expect(profile?.email == "D@example.com")
        #expect(profile?.website == Website(address: "nnix.com/~bloom", insecure: false))
        #expect(profile?.github == "lbloom")
        #expect(profile?.linkedin == "leopold-bloom")
        #expect(profile?.calendly == "bloom/coffee")
    }

    /// A domestic number has no country code and cannot be E.164. The message
    /// says what to do rather than leaving the field to vanish.
    @Test func aNumberWithoutACountryCodeIsRefusedWithAdvice() {
        var d = draft()
        d.phone = "(555) 123-4567"
        let result = d.commit()
        #expect(result.profile == nil)
        #expect(result.problems["phone"] == "Start with + and the country code.")
    }

    @Test func anHttpWebsiteWarnsButStillCommits() {
        var d = draft()
        d.website = "http://example.org/~bloom"
        let result = d.commit()
        #expect(result.profile?.website == Website(address: "example.org/~bloom", insecure: true))
        #expect(result.warnings["website"] != nil)
        #expect(result.problems.isEmpty)
    }

    // MARK: - Custom fields

    /// A persona picks its custom fields by label and a card names them the
    /// same way, so two fields cannot share one.
    @Test func twoFieldsCannotShareALabel() {
        var d = draft()
        d.custom = [field("Desk", "3A"), field("Desk", "3B")]
        let result = d.commit()
        #expect(result.profile == nil)
        #expect(result.problems.values.contains("another field has this label"))
    }

    @Test func distinctLabelsCommitInOrder() {
        var d = draft()
        d.custom = [field("Desk", "3A"), field("Room", "12")]
        let fields = d.commit().profile?.custom
        #expect(fields?.map(\.label) == ["Desk", "Room"])
        #expect(fields?.map(\.value) == ["3A", "12"])
    }

    // MARK: - Preview

    /// The editor stores a bare slug and the card expands it, so the reader
    /// needs to see what it becomes while typing.
    @Test func slugsPreviewAsTheURLTheyBecome() {
        #expect(ProfileDraft.preview(key: "github", text: "lbloom") == "https://github.com/lbloom")
        #expect(ProfileDraft.preview(key: "github", text: "https://github.com/lbloom") == "https://github.com/lbloom")
        #expect(ProfileDraft.preview(key: "calendly", text: "bloom/coffee") == "https://calendly.com/bloom/coffee")
        #expect(ProfileDraft.preview(key: "mastodon", text: "@bloom@merveilles.town")
                == "https://merveilles.town/@bloom")
    }

    /// The branch nobody guesses: a person goes under `/in/`, a company keeps
    /// the prefix it was stored with.
    @Test func linkedInPreviewsPeopleAndCompaniesDifferently() {
        #expect(ProfileDraft.preview(key: "linkedin", text: "leopold-bloom")
                == "https://www.linkedin.com/in/leopold-bloom")
        #expect(ProfileDraft.preview(key: "linkedin", text: "company/hatband")
                == "https://www.linkedin.com/company/hatband")
    }

    /// A website shows its scheme, which is the only place the reader learns
    /// that what they typed is not encrypted.
    @Test func websitePreviewShowsTheScheme() {
        #expect(ProfileDraft.preview(key: "website", text: "nnix.com/~bloom") == "https://nnix.com/~bloom")
        #expect(ProfileDraft.preview(key: "website", text: "http://example.org") == "http://example.org")
    }

    /// Nothing to show for an empty field, a field that does not normalise, or
    /// one whose stored form is already what it looks like.
    @Test func nothingToPreviewIsNothingShown() {
        #expect(ProfileDraft.preview(key: "github", text: "   ") == nil)
        #expect(ProfileDraft.preview(key: "github", text: "not a user/////") == nil)
        #expect(ProfileDraft.preview(key: "name", text: "Leopold Bloom") == nil)
        #expect(ProfileDraft.preview(key: "phone", text: "+353871234567") == nil)
    }

    // MARK: - Keys

    /// The refusal has to reach the field, not just the scanner: these boxes
    /// are next to each other and a card carries what is in them.
    @Test func aPrivateKeyIsRefusedInEveryBoxThatTakesOne() {
        var ssh = draft()
        ssh.ssh = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEA\n-----END OPENSSH PRIVATE KEY-----"
        let sshResult = ssh.commit()
        #expect(sshResult.profile == nil)
        #expect(sshResult.problems["ssh"] == PrivateKeyScan.refusal)

        var gpg = draft()
        gpg.gpgKey = "-----BEGIN PGP PRIVATE KEY BLOCK-----\n\nlQVYBGY=\n-----END PGP PRIVATE KEY BLOCK-----"
        let gpgResult = gpg.commit()
        #expect(gpgResult.profile == nil)
        #expect(gpgResult.problems["gpgKey"] == PrivateKeyScan.refusal)

        var custom = draft()
        custom.custom = [field("Backup", "-----BEGIN RSA PRIVATE KEY-----\nMIIEow==\n-----END RSA PRIVATE KEY-----",
                               kind: .key)]
        let customResult = custom.commit()
        #expect(customResult.profile == nil)
        #expect(customResult.problems.values.contains(PrivateKeyScan.refusal))
    }

    // MARK: - Renames

    /// A rename has to be carried to every persona that shared the field, or
    /// the field silently leaves their cards. Row ids are what tell a rename
    /// from a delete plus an add.
    @Test func aRenamedLabelIsReportedAsARename() {
        let desk = UUID()
        let original = [desk: "Desk"]
        let renamed = ProfileDraft.renamedLabels(from: original, to: [field("Desk phone", "3A", id: desk)])
        #expect(renamed == ["Desk": "Desk phone"])
    }

    @Test func anUntouchedLabelIsNotARename() {
        let desk = UUID()
        #expect(ProfileDraft.renamedLabels(from: [desk: "Desk"], to: [field("Desk", "3A", id: desk)]).isEmpty)
    }

    /// A row the editor did not load is new, whatever it is called, and a
    /// blank label is on its way to being refused rather than renamed.
    @Test func newAndBlankRowsAreNotRenames() {
        let desk = UUID()
        #expect(ProfileDraft.renamedLabels(from: [desk: "Desk"], to: [field("Room", "12")]).isEmpty)
        #expect(ProfileDraft.renamedLabels(from: [desk: "Desk"], to: [field("  ", "3A", id: desk)]).isEmpty)
    }

    @Test func renamesAreTrimmedAndCollectedTogether() {
        let desk = UUID(), room = UUID()
        let renamed = ProfileDraft.renamedLabels(
            from: [desk: "Desk", room: "Room"],
            to: [field("  Desk phone  ", "3A", id: desk), field("Room 12", "12", id: room)])
        #expect(renamed == ["Desk": "Desk phone", "Room": "Room 12"])
    }
}
