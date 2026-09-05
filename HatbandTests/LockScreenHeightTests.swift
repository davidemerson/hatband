import CoreGraphics
import HatbandCore
import SwiftUI
import Testing
import UIKit
@testable import Hatband

/// Renders the Lock Screen presentation at the width of an iPhone and
/// checks it stays under the 160 pt Live Activity cap.
@MainActor struct LockScreenHeightTests {
    private let width: CGFloat = 393
    private let cap: CGFloat = 160

    /// Exactly 64 bytes, with spaces so it wraps onto a second line.
    private let twoLineName = "Leopold Paula Bloom of 7 Eccles Street, advertisement canvasser."

    private func height(of presentation: Presentation) throws -> CGFloat {
        let view = LockScreenCardView(presentation: presentation, color: 2)
            .frame(width: width)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        let image = try #require(renderer.uiImage)
        return image.size.height
    }

    private func code() throws -> QRCode {
        try #require(CardQR.code(for: try Vectors.url("compact-two-channels"), form: .lockScreen))
    }

    @Test func cardUnder160() throws {
        #expect(twoLineName.utf8.count == 64)
        let height = try height(of: .card(try code(), name: twoLineName))
        #expect(height <= cap)
        #expect(height >= LockScreenCardView.panelSide)
    }

    @Test func cardWithoutNameUnder160() throws {
        #expect(try height(of: .card(try code(), name: nil)) <= cap)
    }

    @Test func dimmedUnder160() throws {
        #expect(try height(of: .dimmed) <= cap)
    }

    @Test func expiredUnder160() throws {
        #expect(try height(of: .expired) <= cap)
    }

    @Test func unavailableUnder160() throws {
        #expect(try height(of: .unavailable) <= cap)
    }
}
