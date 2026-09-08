import Foundation
import Testing
import VisionKit
@testable import Hatband

struct ScanViewTests {
    /// The scanner's refusals reach the sheet as sentences that point at
    /// the photo path, never as case names.
    /// A poster, a ticket, a Wi-Fi code: the sheet says so and the camera
    /// stays up. It used to close and raise an alert on the Card tab, which
    /// made a mis-aimed scan a four-tap detour back to where you were.
    @Test func onlyACardEndsTheScan() throws {
        #expect(ScanView.isCard(try Vectors.url("typical-signed")))
        #expect(ScanView.isCard(try Vectors.url("compact-name-only")))
        for other in ["WIFI:S:Davy Byrne;T:WPA;P:gorgonzola;;",
                      "https://example.org/",
                      "https://hatband.link/",
                      "https://hatband.link/#2NOTAFORMAT",
                      "", "   "] {
            #expect(!ScanView.isCard(other), "\(other) is not a card")
        }
    }

    @Test func scannerRefusalsReadAsSentences() {
        let restricted = ScanView.unavailableText(DataScannerViewController.ScanningUnavailable.cameraRestricted)
        #expect(restricted == "The camera is restricted on this iPhone. Pick a photo of the code instead.")
        let unsupported = ScanView.unavailableText(DataScannerViewController.ScanningUnavailable.unsupported)
        #expect(unsupported == "The camera scanner is not available here. Pick a photo of the code instead.")
        let other = ScanView.unavailableText(CocoaError(.fileNoSuchFile))
        #expect(other == "The camera could not start. Pick a photo of the code instead.")
        for text in [restricted, unsupported, other] {
            #expect(!text.contains("Error"))
            #expect(!text.contains("cameraRestricted"))
            #expect(text.hasSuffix("Pick a photo of the code instead."))
        }
    }
}
