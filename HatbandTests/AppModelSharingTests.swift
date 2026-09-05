import ActivityKit
import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// Cross-package: `card(for:form:)` and `url(for:form:)` are package B's,
/// so these are red until B merges.
@MainActor struct AppModelSharingTests {
    private func sampleProfile() -> Profile {
        var profile = Profile()
        profile.name = "Leopold Bloom"
        profile.email = "bloom@example.ie"
        profile.phone = "+353871234567"
        return profile
    }

    private func onboarded() async throws -> AppModel {
        let model = try AppModel.inMemory()
        await model.load()
        try model.finishOnboarding(profile: sampleProfile(), appLock: false)
        return model
    }

    @Test func sharingContentBuildsCompactState() async throws {
        let model = try await onboarded()
        let persona = try #require(model.personas.first)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let content = try model.sharingContent(for: persona, minutes: 30, now: now)

        let card = try HB1.decode(url: content.state.url)
        #expect(card.isCompact)
        #expect(card.personaID == persona.id)
        #expect(card.publicKey == nil)
        #expect(card.keyFingerprint?.count == 8)
        #expect(Budget(card: card).fitsLockScreen)
        #expect(CardQR.code(for: content.state.url, form: .lockScreen) != nil)
        #expect(content.state.name == "Leopold Bloom")
        #expect(content.state.alwaysOn == model.settings.alwaysOnQR)
        #expect(content.state.endsAt == now.addingTimeInterval(30 * 60))
        #expect(content.attributes.personaID == Hex.string(persona.id))
        #expect(content.attributes.personaID.count == 16)
        #expect(content.attributes.color == persona.color)

        model.settings.showNameOnLockScreen = false
        model.settings.alwaysOnQR = true
        let hidden = try model.sharingContent(for: persona, minutes: 480, now: now)
        #expect(hidden.state.name == nil)
        #expect(hidden.state.alwaysOn)
        #expect(hidden.state.endsAt == now.addingTimeInterval(480 * 60))
    }

    @Test func refreshWidgetWritesWhenEnabled() async throws {
        let model = try await onboarded()
        let directory = try #require(model.widgetDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persona = try #require(model.personas.first)
        #expect(WidgetFeed.read(from: directory) == nil)

        model.settings.homeWidget = true
        model.refreshWidget()
        let feed = try #require(WidgetFeed.read(from: directory))
        #expect(feed.url == (try model.url(for: persona, form: .lockScreen)))
        #expect(feed.name == "Leopold Bloom")
        #expect(feed.color == persona.color)
        #expect(try HB1.decode(url: feed.url).isCompact)
    }

    @Test func removesWhenDisabled() async throws {
        let model = try await onboarded()
        let directory = try #require(model.widgetDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        model.settings.homeWidget = true
        model.refreshWidget()
        #expect(WidgetFeed.read(from: directory) != nil)

        model.settings.homeWidget = false
        model.refreshWidget()
        #expect(WidgetFeed.read(from: directory) == nil)
        #expect(!FileManager.default.fileExists(atPath: WidgetFeed.fileURL(in: directory).path))
    }

    @Test func reconcileWithNoActivitiesClearsSharing() async throws {
        let model = try await onboarded()
        let persona = try #require(model.personas.first)
        await model.stopSharing()
        model.sharing = AppModel.Sharing(personaID: persona.id, endsAt: Date().addingTimeInterval(600))
        await model.reconcileActivities()
        #expect(model.sharing == nil)
        await model.reconcileActivities()
        #expect(model.sharing == nil)
    }

    @Test func startAndStopWhenEnabled() async throws {
        let model = try await onboarded()
        let persona = try #require(model.personas.first)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await #expect(throws: AppError.activitiesDisabled) {
                try await model.startSharing(persona: persona, minutes: 30)
            }
            #expect(model.sharing == nil)
            return
        }
        let before = Date()
        try await model.startSharing(persona: persona, minutes: 30)
        let sharing = try #require(model.sharing)
        #expect(sharing.personaID == persona.id)
        #expect(sharing.endsAt >= before.addingTimeInterval(30 * 60))
        #expect(model.settings.durationMinutes == 30)

        await model.reconcileActivities()
        #expect(model.sharing?.personaID == persona.id)

        await model.stopSharing()
        #expect(model.sharing == nil)
        await model.reconcileActivities()
        #expect(model.sharing == nil)
    }
}
