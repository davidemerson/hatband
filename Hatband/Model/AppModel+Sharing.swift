import ActivityKit
import Foundation
import HatbandCore
import WidgetKit

/// Live Activity and Home Screen widget. Every `Activity` instance stays
/// inside `ActivityDriver`, off the main actor; the model only ever sees
/// persona ids and dates.
extension AppModel {
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
    func startSharing(persona: Persona, minutes: Int) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw AppError.activitiesDisabled }
        let content = try sharingContent(for: persona, minutes: minutes, now: Date())
        await ActivityDriver.endAll()
        _ = try Activity<HatbandAttributes>.request(
            attributes: content.attributes,
            content: ActivityContent(state: content.state, staleDate: content.state.endsAt, relevanceScore: 100),
            pushType: nil)
        sharing = Sharing(personaID: persona.id, endsAt: content.state.endsAt)
        if settings.durationMinutes != minutes {
            settings.durationMinutes = minutes
            try saveOwner()
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

    /// Writes the feed for the selected persona when the widget is on,
    /// removes it otherwise, then asks WidgetKit to reload.
    func refreshWidget() {
        let directory = widgetDirectory ?? WidgetFeed.container
        let persona = personas.first { $0.id == selectedPersonaID }
        if settings.homeWidget, let persona {
            do {
                let state = try lockScreenState(for: persona, endsAt: Date())
                let feed = WidgetFeed(url: state.url, name: state.name, color: persona.color, writtenAt: Date())
                try feed.write(to: directory)
            } catch {
                WidgetFeed.remove(from: directory)
                Log.failure("refreshWidget", error)
            }
        } else {
            WidgetFeed.remove(from: directory)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetFeed.kind)
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
