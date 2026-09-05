import ActivityKit
import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// Cross-package: `card(for:form:)` and `url(for:form:)` are package B's,
/// so these are red until B merges. Serialized because `Activity.activities`
/// is process-wide state shared by every test in the host.
@MainActor @Suite(.serialized) struct AppModelSharingTests {
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

    /// The Lock Screen sheet's toggles persist, reach the widget feed at
    /// once (it carries the name too), and survive a reload.
    @Test func applyLockScreenPreferencesPersistsAndRefeedsWidget() async throws {
        let model = try await onboarded()
        let directory = try #require(model.widgetDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persona = try #require(model.personas.first)
        model.settings.homeWidget = true
        model.refreshWidget()
        let before = try #require(WidgetFeed.read(from: directory))
        #expect(before.name == "Leopold Bloom")

        model.settings.showNameOnLockScreen = false
        model.settings.alwaysOnQR = true
        model.settings.durationMinutes = 30
        try await model.applyLockScreenPreferences()
        let after = try #require(WidgetFeed.read(from: directory))
        #expect(after.name == nil)
        #expect(after.url == before.url)

        let store = try #require(model.store)
        let reloaded = AppModel(keys: model.keys, makeStore: { store })
        reloaded.protectedDataAvailable = { true }
        reloaded.widgetDirectory = directory
        await reloaded.load()
        #expect(reloaded.settings.showNameOnLockScreen == false)
        #expect(reloaded.settings.alwaysOnQR)
        #expect(reloaded.settings.durationMinutes == 30)
        let content = try reloaded.sharingContent(for: persona, minutes: 30, now: Date())
        #expect(content.state.name == nil)
        #expect(content.state.alwaysOn)
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
        do {
            try await model.startSharing(persona: persona, minutes: 30)
        } catch is AppError {
            // The simulator reports activities enabled, but the test host
            // may still be refused; there is nothing to prove then but
            // that no session was left behind.
            #expect(model.sharing == nil)
            return
        }
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

    /// A refusal from ActivityKit lands after the previous session has
    /// been ended, so nothing is sharing any more: `sharing` is nil, the
    /// duration is not saved, and the error is a sentence. A request that
    /// goes through sets both.
    @Test func refusedRequestLeavesNoSharing() async throws {
        let model = try await onboarded()
        let persona = try #require(model.personas.first)
        defer { AppModel.activityRequest = nil }
        model.sharing = AppModel.Sharing(personaID: persona.id, endsAt: Date().addingTimeInterval(600))
        AppModel.activityRequest = { _, _ in throw ActivityAuthorizationError.denied }
        await #expect(throws: AppError.activitiesDisabled) {
            try await model.startSharing(persona: persona, minutes: 30)
        }
        #expect(model.sharing == nil)
        #expect(model.settings.durationMinutes == 120)

        model.sharing = AppModel.Sharing(personaID: persona.id, endsAt: Date().addingTimeInterval(600))
        AppModel.activityRequest = { _, _ in throw ActivityAuthorizationError.targetMaximumExceeded }
        await #expect(throws: AppError.storage("Too many Live Activities are running. End one and try again.")) {
            try await model.startSharing(persona: persona, minutes: 30)
        }
        #expect(model.sharing == nil)

        var requested: [HatbandAttributes.ContentState] = []
        AppModel.activityRequest = { _, state in requested.append(state) }
        let before = Date()
        try await model.startSharing(persona: persona, minutes: 30)
        let sharing = try #require(model.sharing)
        #expect(sharing.personaID == persona.id)
        #expect(sharing.endsAt >= before.addingTimeInterval(30 * 60))
        #expect(requested.count == 1)
        #expect(requested.first?.endsAt == sharing.endsAt)
        #expect(model.settings.durationMinutes == 30)
    }

    /// Every ActivityKit refusal reads as one line for the alert, never as
    /// the case name or a description; other errors map as they always did.
    @Test func sharingErrorsReadAsSentences() {
        #expect(AppModel.sharingError(ActivityAuthorizationError.denied) == .activitiesDisabled)
        #expect(AppModel.sharingError(ActivityAuthorizationError.unsupported)
            == .storage("Live Activities are not available on this iPhone."))
        #expect(AppModel.sharingError(ActivityAuthorizationError.unentitled)
            == .storage("Live Activities are not available on this iPhone."))
        #expect(AppModel.sharingError(ActivityAuthorizationError.attributesTooLarge)
            == .storage("The card is too large for the Lock Screen."))
        #expect(AppModel.sharingError(ActivityAuthorizationError.globalMaximumExceeded)
            == .storage("Too many Live Activities are running. End one and try again."))
        #expect(AppModel.sharingError(ActivityAuthorizationError.visibility)
            == .storage("Bring Hatband to the front and try again."))
        #expect(AppModel.sharingError(ActivityAuthorizationError.persistenceFailure)
            == .storage("The Lock Screen card could not start. Try again."))
        #expect(AppModel.sharingError(AppError.tooBigForLockScreen) == .tooBigForLockScreen)
        #expect(AppModel.sharingError(KeyStoreError.cancelled) == .cancelled)
        let refusals: [ActivityAuthorizationError] = [
            .denied, .unsupported, .unentitled, .unsupportedTarget, .attributesTooLarge, .globalMaximumExceeded,
            .targetMaximumExceeded, .visibility, .persistenceFailure, .reconnectNotPermitted,
            .malformedActivityIdentifier, .missingProcessIdentifier,
        ]
        for refusal in refusals {
            let message = AppModel.sharingError(refusal).message
            #expect(message.hasSuffix("."))
            #expect(!message.contains("Error"))
            #expect(!message.contains(String(describing: refusal)))
        }
    }
}
