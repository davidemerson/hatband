import ActivityKit
import Foundation
import HatbandCore
import WidgetKit

/// Live Activity and Home Screen widget. Every `Activity` instance stays
/// inside `ActivityDriver`, off the main actor; the model only ever sees
/// persona ids and dates.
extension AppModel {
    /// Test hook, nil in production: fires after every widget reload.
    static var onWidgetReload: (() -> Void)?
    /// Test hook, nil in production: stands in for ActivityKit's request
    /// and its authorization check, so the paths after a refusal run
    /// without a Lock Screen.
    static var activityRequest: (@MainActor (HatbandAttributes, HatbandAttributes.ContentState) throws -> Void)?

    /// The ActivityKit-free half of `startSharing`: the compact card as a
    /// URL, the name when shown, and the end time.
    func sharingContent(for persona: Persona, minutes: Int, now: Date) throws
        -> (attributes: HatbandAttributes, state: HatbandAttributes.ContentState) {
        let endsAt = now.addingTimeInterval(TimeInterval(minutes) * 60)
        let state = try lockScreenState(for: persona, endsAt: endsAt)
        let attributes = HatbandAttributes(personaID: Hex.string(persona.id), color: persona.color)
        return (attributes, state)
    }

    /// Requests the Live Activity for `minutes`, ending any other first.
    /// Once the other has ended, `sharing` is nil until the request
    /// succeeds: a refusal leaves no session behind, and reads as a
    /// sentence rather than ActivityKit's description.
    func startSharing(persona: Persona, minutes: Int) async throws {
        guard AppModel.activityRequest != nil || ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw AppError.activitiesDisabled
        }
        let content = try sharingContent(for: persona, minutes: minutes, now: Date())
        await ActivityDriver.endAll()
        sharing = nil
        do {
            if let request = AppModel.activityRequest {
                try request(content.attributes, content.state)
            } else {
                _ = try Activity<HatbandAttributes>.request(
                    attributes: content.attributes,
                    content: ActivityContent(state: content.state, staleDate: content.state.endsAt, relevanceScore: 100),
                    pushType: nil)
            }
        } catch {
            throw AppModel.sharingError(error)
        }
        sharing = Sharing(personaID: persona.id, endsAt: content.state.endsAt)
        if settings.durationMinutes != minutes {
            settings.durationMinutes = minutes
            try saveOwner()
        }
    }

    /// ActivityKit's refusals as one line each; anything else through
    /// `AppError.init`.
    nonisolated static func sharingError(_ error: any Error) -> AppError {
        guard let refusal = error as? ActivityAuthorizationError else { return AppError(error) }
        switch refusal {
        case .denied:
            return .activitiesDisabled
        case .unsupported, .unentitled, .unsupportedTarget:
            return .storage("Live Activities are not available on this iPhone.")
        case .attributesTooLarge:
            return .storage("The card is too large for the Lock Screen.")
        case .globalMaximumExceeded, .targetMaximumExceeded:
            return .storage("Too many Live Activities are running. End one and try again.")
        case .visibility:
            return .storage("Bring Hatband to the front and try again.")
        case .persistenceFailure, .reconnectNotPermitted, .malformedActivityIdentifier, .missingProcessIdentifier:
            return .storage("The Lock Screen card could not start. Try again.")
        @unknown default:
            return .storage("The Lock Screen card could not start. Try again.")
        }
    }

    /// Ends every activity immediately.
    func stopSharing() async {
        await ActivityDriver.endAll()
        sharing = nil
    }

    /// Ends activities past their end time or gone stale; `sharing`
    /// reflects whatever is still running.
    func reconcileActivities() async {
        let running = await ActivityDriver.reconcile(now: Date())
        var current: Sharing?
        for item in running {
            if let personaID = Hex.bytes(item.personaID) {
                current = Sharing(personaID: personaID, endsAt: item.endsAt)
                break
            }
        }
        sharing = current
    }

    /// After `showNameOnLockScreen` or `alwaysOnQR` changes: the running
    /// activity, if any, is rebuilt from the new settings, so a name the
    /// user just hid leaves the Lock Screen now rather than at the end time.
    func updateSharingActivity() async {
        guard let sharing, let persona = personas.first(where: { $0.id == sharing.personaID }) else { return }
        await updateActivity(for: persona)
    }

    /// Pushes the persona's current card into its running activity, if any,
    /// keeping the end time.
    func updateActivity(for persona: Persona) async {
        let personaID = Hex.string(persona.id)
        guard let endsAt = await ActivityDriver.endsAt(personaID: personaID) else { return }
        do {
            let state = try lockScreenState(for: persona, endsAt: endsAt)
            let content = ActivityContent(state: state, staleDate: endsAt, relevanceScore: 100)
            await ActivityDriver.update(personaID: personaID, content: content)
        } catch {
            Log.failure("updateActivity", error)
        }
    }

    /// Persists the Lock Screen preferences (name, Always-On, duration) and
    /// pushes them into the running activity and the widget feed, both of
    /// which carry the name.
    func applyLockScreenPreferences() async throws {
        try saveOwner()
        refreshFeeds()
        if let sharing, let persona = personas.first(where: { $0.id == sharing.personaID }) {
            await updateActivity(for: persona)
        }
    }

    /// Writes the feed for the selected persona when the widget is on,
    /// removes it otherwise, then asks WidgetKit to reload. Returns what went
    /// wrong, so a caller turning the widget on can say so instead of leaving
    /// the setting and the widget disagreeing.
    @discardableResult func refreshWidget() -> (any Error)? {
        let directory = widgetDirectory ?? WidgetFeed.container
        let persona = personas.first { $0.id == selectedPersonaID }
        var failure: (any Error)?
        if settings.homeWidget, let persona {
            do {
                let state = try lockScreenState(for: persona, endsAt: Date())
                let feed = WidgetFeed(url: state.url, name: state.name, color: persona.color, writtenAt: Date())
                try feed.write(to: directory)
            } catch {
                WidgetFeed.remove(from: directory)
                Log.failure("refreshWidget", error)
                failure = error
            }
        } else {
            WidgetFeed.remove(from: directory)
        }
        reloadWidgetTimelines()
        return failure
    }

    /// Both feeds. Everything that changes what a card says calls this; the
    /// widget's own on/off toggle still calls `refreshWidget` alone, because
    /// it reverts itself on that failure and a share-feed failure is not its
    /// business.
    func refreshFeeds() {
        refreshWidget()
        refreshShareFeed()
    }

    /// Every persona as a finished, signed card, for the Messages extension
    /// to offer. It cannot sign — the seed is the app's alone — so what it
    /// can send is what is written here.
    ///
    /// Written whole or not at all: a half-list would offer some personas and
    /// silently drop others.
    @discardableResult func refreshShareFeed() -> (any Error)? {
        let directory = widgetDirectory ?? AppGroup.container
        guard phase == .ready, !personas.isEmpty else {
            ShareFeed.remove(from: directory)
            return nil
        }
        do {
            let day = issuedDay()
            let cards = try personas.map { persona -> ShareFeed.Card in
                let file = try card(for: persona, form: .file)
                let full = try card(for: persona, form: .fullQR)
                return ShareFeed.Card(
                    personaID: persona.id, label: persona.label, name: file.name,
                    company: file.company, color: persona.color,
                    fileURL: HB1.url(for: file), fullQRURL: HB1.url(for: full))
            }
            try ShareFeed(cards: cards, issuedDay: day, writtenAt: Date()).write(to: directory)
            return nil
        } catch {
            ShareFeed.remove(from: directory)
            Log.failure("refreshShareFeed", error)
            return error
        }
    }

    /// The signature covers the issued day, so yesterday's file names
    /// yesterday. It still verifies and still saves; the app rewrites it
    /// rather than leaving the extension to send a date it cannot correct.
    func refreshShareFeedIfStale() {
        guard phase == .ready else { return }
        let feed = ShareFeed.read(from: widgetDirectory ?? AppGroup.container)
        if feed == nil || feed?.isStale(on: issuedDay()) == true {
            refreshShareFeed()
        }
    }

    /// Removes the feed and tells WidgetKit, so a widget on a `.never`
    /// policy stops showing a card the phone no longer holds.
    func clearWidget() {
        let directory = widgetDirectory ?? AppGroup.container
        WidgetFeed.remove(from: directory)
        ShareFeed.remove(from: directory)
        reloadWidgetTimelines()
    }

    private func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetFeed.kind)
        AppModel.onWidgetReload?()
    }

    /// The compact card as Lock Screen content. `.tooBigForLockScreen`
    /// when it does not draw at the Lock Screen version limit.
    private func lockScreenState(for persona: Persona, endsAt: Date) throws -> HatbandAttributes.ContentState {
        let card = try card(for: persona, form: .lockScreen)
        let url = HB1.url(for: card)
        guard CardQR.code(for: url, form: .lockScreen) != nil else { throw AppError.tooBigForLockScreen }
        let name = settings.showNameOnLockScreen ? card.name : nil
        return HatbandAttributes.ContentState(url: url, name: name, alwaysOn: settings.alwaysOnQR, endsAt: endsAt)
    }
}

/// ActivityKit calls, run off the main actor so that `Activity` values
/// never cross an isolation boundary. Returns only ids and dates.
nonisolated enum ActivityDriver {
    struct Running: Sendable, Equatable {
        let personaID: String
        let endsAt: Date
    }

    @concurrent nonisolated static func endAll() async {
        for activity in Activity<HatbandAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends activities whose `endsAt` has passed or whose state is stale,
    /// ended or dismissed; lists the rest.
    @concurrent nonisolated static func reconcile(now: Date) async -> [Running] {
        var running: [Running] = []
        for activity in Activity<HatbandAttributes>.activities {
            let endsAt = activity.content.state.endsAt
            let state = activity.activityState
            let finished = state == .stale || state == .ended || state == .dismissed
            if finished || endsAt <= now {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                running.append(Running(personaID: activity.attributes.personaID, endsAt: endsAt))
            }
        }
        return running
    }

    /// The end time of the active activity for a persona, or nil.
    @concurrent nonisolated static func endsAt(personaID: String) async -> Date? {
        for activity in Activity<HatbandAttributes>.activities
        where activity.attributes.personaID == personaID && activity.activityState == .active {
            return activity.content.state.endsAt
        }
        return nil
    }

    @concurrent nonisolated static func update(personaID: String, content: ActivityContent<HatbandAttributes.ContentState>) async {
        for activity in Activity<HatbandAttributes>.activities
        where activity.attributes.personaID == personaID && activity.activityState == .active {
            await activity.update(content)
        }
    }
}
