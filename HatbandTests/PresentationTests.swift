import Foundation
import HatbandCore
import Testing
@testable import Hatband

struct PresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(url: String, name: String? = "Leopold Bloom", alwaysOn: Bool = false,
                       endsIn seconds: TimeInterval = 3600) -> HatbandAttributes.ContentState {
        HatbandAttributes.ContentState(url: url, name: name, alwaysOn: alwaysOn, endsAt: now.addingTimeInterval(seconds))
    }

    private func compactURL() throws -> String {
        try Vectors.url("compact-two-channels")
    }

    @Test func expiredWhenStale() throws {
        let decided = LiveActivityPresentation.decide(
            state: state(url: try compactURL()), isStale: true, isLuminanceReduced: false, now: now)
        #expect(decided == .expired)
    }

    @Test func expiredWhenPastEnd() throws {
        let atEnd = LiveActivityPresentation.decide(
            state: state(url: try compactURL(), endsIn: 0), isStale: false, isLuminanceReduced: false, now: now)
        #expect(atEnd == .expired)
        let past = LiveActivityPresentation.decide(
            state: state(url: try compactURL(), endsIn: -1), isStale: false, isLuminanceReduced: true, now: now)
        #expect(past == .expired)
        let before = LiveActivityPresentation.decide(
            state: state(url: try compactURL(), endsIn: 1), isStale: false, isLuminanceReduced: false, now: now)
        #expect(before != .expired)
    }

    @Test func dimmedWhenLuminanceReduced() throws {
        let decided = LiveActivityPresentation.decide(
            state: state(url: try compactURL(), alwaysOn: false), isStale: false, isLuminanceReduced: true, now: now)
        #expect(decided == .dimmed)
    }

    @Test func cardWhenAlwaysOn() throws {
        let decided = LiveActivityPresentation.decide(
            state: state(url: try compactURL(), alwaysOn: true), isStale: false, isLuminanceReduced: true, now: now)
        guard case .card = decided else {
            Issue.record("expected .card, got \(decided)")
            return
        }
    }

    @Test func nameRidesThrough() throws {
        let shown = LiveActivityPresentation.decide(
            state: state(url: try compactURL(), name: "Henry Flower"), isStale: false, isLuminanceReduced: false, now: now)
        guard case .card(_, let name) = shown else {
            Issue.record("expected .card, got \(shown)")
            return
        }
        #expect(name == "Henry Flower")

        let hidden = LiveActivityPresentation.decide(
            state: state(url: try compactURL(), name: nil), isStale: false, isLuminanceReduced: false, now: now)
        guard case .card(_, let none) = hidden else {
            Issue.record("expected .card, got \(hidden)")
            return
        }
        #expect(none == nil)
    }

    @Test func unavailableWhenURLTooLong() throws {
        let signed = LiveActivityPresentation.decide(
            state: state(url: try Vectors.url("typical-signed")), isStale: false, isLuminanceReduced: false, now: now)
        #expect(signed == .unavailable)
        let huge = LiveActivityPresentation.decide(
            state: state(url: String(repeating: "x", count: 5000)), isStale: false, isLuminanceReduced: false, now: now)
        #expect(huge == .unavailable)
    }

    @Test func compactVectorVersionAtMost10() throws {
        for name in ["compact-name-only", "compact-two-channels"] {
            let decided = LiveActivityPresentation.decide(
                state: state(url: try Vectors.url(name)), isStale: false, isLuminanceReduced: false, now: now)
            guard case .card(let code, _) = decided else {
                Issue.record("\(name): expected .card, got \(decided)")
                continue
            }
            #expect(code.version <= Budget.lockScreenMaxVersion)
            #expect(code.errorCorrection != .low)
        }
    }
}
