import Foundation
import Testing

/// `GENERATE_INFOPLIST_FILE` is off, so xcodegen writes the Info.plist itself and
/// defaults the version keys to a literal 1.0 unless `project.yml` names them.
/// `AboutView` reads the first of these and App Store Connect reads both, so a
/// regression here is invisible until an upload carries the wrong version.
struct BundleInfoTests {
    private let info = Bundle.main.infoDictionary ?? [:]

    @Test func versionComesFromTheBuildSetting() {
        #expect(info["CFBundleShortVersionString"] as? String == "0.4.0")
        // Not pinned: every upload needs a build number above the last, so
        // pinning one here would fail the release this test exists to protect.
        // What matters is that the setting reaches the bundle at all.
        let build = info["CFBundleVersion"] as? String
        #expect(build?.isEmpty == false)
        #expect(build.map { $0.allSatisfy(\.isNumber) } == true, "a build number, not $(CURRENT_PROJECT_VERSION)")
    }

    /// Declared false on the publicly-available-source exemption. Without the key
    /// App Store Connect asks the compliance questions on every upload.
    @Test func exportComplianceIsDeclared() {
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    }

    /// Every permission the app can prompt for needs its string, or the prompt
    /// is a crash rather than a refusal. Contacts is asked for only when someone
    /// taps "Add to Contacts" on a person they already scanned.
    @Test func everyPromptHasItsUsageDescription() {
        for key in ["NSCameraUsageDescription", "NSLocationWhenInUseUsageDescription",
                    "NSFaceIDUsageDescription", "NSContactsUsageDescription"] {
            #expect((info[key] as? String)?.isEmpty == false, "missing \(key)")
        }
    }

    /// The app is iPhone-only; the iPad orientations exist only to answer Xcode's
    /// "all interface orientations must be supported" check without the deprecated
    /// `UIRequiresFullScreen`. `infoDictionary` resolves `~device` suffixes and so
    /// cannot see the iPad key on an iPhone — the file itself has to be read.
    @Test func portraitOnlyOnIPhoneAndDeclaredForIPad() throws {
        #expect(info["UISupportedInterfaceOrientations"] as? [String] == ["UIInterfaceOrientationPortrait"])

        let url = Bundle.main.bundleURL.appending(path: "Info.plist")
        let raw = try PropertyListSerialization.propertyList(
            from: try Data(contentsOf: url), format: nil) as? [String: Any]
        #expect((raw?["UISupportedInterfaceOrientations~ipad"] as? [String])?.count == 4)
    }
}
