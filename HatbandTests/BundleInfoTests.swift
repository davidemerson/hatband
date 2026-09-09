import Foundation
import Testing
import UIKit

/// `GENERATE_INFOPLIST_FILE` is off, so xcodegen writes the Info.plist itself and
/// defaults the version keys to a literal 1.0 unless `project.yml` names them.
/// `AboutView` reads the first of these and App Store Connect reads both, so a
/// regression here is invisible until an upload carries the wrong version.
struct BundleInfoTests {
    private let info = Bundle.main.infoDictionary ?? [:]

    @Test func versionComesFromTheBuildSetting() {
        #expect(info["CFBundleShortVersionString"] as? String == "1.0.0")
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

    /// iPhone only, and said where it holds. `project.yml` set the device
    /// family at project level for months while xcodegen wrote "1,2" at
    /// target level, which wins — so every build declared iPad support, and
    /// the "all interface orientations" warning that came with it was
    /// answered by declaring iPad orientations rather than by finding this.
    @Test func theBundleIsIPhoneOnly() {
        #expect(info["UISupportedInterfaceOrientations"] as? [String] == ["UIInterfaceOrientationPortrait"])
        #expect(info["UIDeviceFamily"] as? [Int] == [1], "iPad support crept back into the bundle")
        #expect(info["UISupportedInterfaceOrientations~ipad"] == nil, "no iPad orientations to declare")
    }
}

/// The v0.5.0 upload was rejected eight times over for a missing iMessage app
/// icon. The icon set was there; the target was a plain `app-extension`, and
/// actool compiles a stickers icon set only for the messages product type, so
/// the eight device sizes were dropped without a warning. These read the built
/// extension rather than `project.yml`, because reading the yaml is what hid it.
struct MessagesExtensionBundleTests {
    private var appex: Bundle? {
        guard let plugIns = Bundle.main.builtInPlugInsURL else { return nil }
        return Bundle(url: plugIns.appendingPathComponent("HatbandMessages.appex"))
    }

    @Test func theExtensionIsEmbedded() throws {
        let bundle = try #require(appex, "HatbandMessages.appex is not in the app's PlugIns")
        #expect(bundle.bundleIdentifier == "link.hatband.ios.messages")
        #expect(bundle.infoDictionary?["UIDeviceFamily"] as? [Int] == [1])
    }

    /// Five base names, each of which the packager expands to the @2x and @3x
    /// files Apple's validator asks for. Absent this key the icon is missing
    /// however many PNGs sit in the catalog.
    @Test func theStoreIconIsCompiledIntoTheExtension() throws {
        let bundle = try #require(appex)
        let info = try #require(bundle.infoDictionary)
        #expect(info["MSMessagesExtensionStoreIconName"] as? String == "iMessage App Icon")

        let icons = info["CFBundleIcons"] as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let files = try #require(primary?["CFBundleIconFiles"] as? [String],
                                 "no CFBundleIconFiles: the target is not a messages extension")
        for size in ["27x20", "32x24", "60x45", "67x50", "74x55"] {
            #expect(files.contains("iMessage App Icon\(size)"), "missing the \(size) icon")
        }
    }

    /// Every name in that list has to reach the bundle as a real file, at the
    /// pixel size its name and scale imply. The eight the validator names are
    /// 54×40, 64×48, 81×60, 96×72, 120×90, 134×100, 148×110 and 180×135.
    @Test func everyDeclaredIconIsOnDiskAtItsStatedSize() throws {
        let bundle = try #require(appex)
        let expected: [(String, Int, CGSize)] = [
            ("iMessage App Icon27x20", 2, CGSize(width: 54, height: 40)),
            ("iMessage App Icon27x20", 3, CGSize(width: 81, height: 60)),
            ("iMessage App Icon32x24", 2, CGSize(width: 64, height: 48)),
            ("iMessage App Icon32x24", 3, CGSize(width: 96, height: 72)),
            ("iMessage App Icon60x45", 2, CGSize(width: 120, height: 90)),
            ("iMessage App Icon60x45", 3, CGSize(width: 180, height: 135)),
            ("iMessage App Icon67x50", 2, CGSize(width: 134, height: 100)),
            ("iMessage App Icon74x55", 2, CGSize(width: 148, height: 110)),
        ]
        for (base, scale, size) in expected {
            let name = "\(base)@\(scale)x"
            let url = try #require(bundle.url(forResource: name, withExtension: "png"),
                                   "\(name).png is not in the extension")
            let image = try #require(UIImage(contentsOfFile: url.path))
            let pixels = CGSize(width: image.size.width * image.scale,
                                height: image.size.height * image.scale)
            #expect(pixels == size, "\(name).png is \(pixels), not \(size)")
        }
    }
}
