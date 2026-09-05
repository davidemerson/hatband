import CoreLocation
import HatbandCore
import MapKit
import SwiftUI

/// Where you met people: one circle per fixed meeting, sized by its
/// accuracy, over a map that loads nothing until this tab is chosen; and
/// a timeline grouped by day.
@MainActor struct WhereView: View {
    @Environment(AppModel.self) private var model
    @State private var position: MapCameraPosition = .automatic

    init() {}

    var body: some View {
        if model.locked {
            LockedView()
        } else if model.route.tab != .places {
            Color.clear
        } else {
            NavigationStack {
                content
                    .navigationTitle("Where")
            }
        }
    }

    @ViewBuilder private var content: some View {
        let stops = WhereView.stops(in: model.people)
        if stops.isEmpty {
            ContentUnavailableView("No fixed abode.", systemImage: "map",
                                   description: Text("Meetings appear here once you have scanned someone."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.ground)
        } else {
            VStack(spacing: 0) {
                if stops.contains(where: { $0.encounter.fix != nil }) {
                    map(stops)
                        .frame(height: 280)
                }
                timeline(stops)
            }
            .background(Theme.ground)
        }
    }

    private func map(_ stops: [Stop]) -> some View {
        Map(position: $position) {
            ForEach(WhereView.pins(of: stops)) { pin in
                MapCircle(center: pin.center, radius: pin.radius)
                    .foregroundStyle(Theme.accent.opacity(0.2))
                    .stroke(Theme.accent, lineWidth: 1)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    private func timeline(_ stops: [Stop]) -> some View {
        List {
            ForEach(WhereView.days(of: stops), id: \.day) { group in
                Section {
                    ForEach(group.stops) { stop in
                        Button {
                            model.route.person = stop.person.id
                            model.route.tab = .people
                        } label: {
                            PlusRow {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.person.card.name ?? "Unnamed")
                                    HStack(spacing: 6) {
                                        Text(stop.encounter.date, style: .time)
                                            .font(Theme.mono)
                                            .foregroundStyle(Theme.tertiary)
                                        if !stop.encounter.label.isEmpty {
                                            Text(stop.encounter.label)
                                        }
                                        if stop.encounter.fix == nil {
                                            Text("no location")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(Theme.ink)
                    }
                } header: {
                    Text(group.day, format: .dateTime.weekday(.wide).day().month().year())
                }
            }
        }
        .listStyle(.plain)
        .grounded()
    }

    // MARK: - Data

    nonisolated struct Stop: Identifiable {
        let person: Person
        let encounter: Encounter
        var id: UUID { encounter.id }
    }

    nonisolated struct DayGroup {
        let day: Date
        let stops: [Stop]
    }

    /// One circle per fixed meeting, the radius its accuracy in metres.
    nonisolated struct Pin: Identifiable {
        let id: UUID
        let center: CLLocationCoordinate2D
        let radius: CLLocationDistance
    }

    nonisolated static func pins(of stops: [Stop]) -> [Pin] {
        var pins: [Pin] = []
        for stop in stops {
            guard let fix = stop.encounter.fix else { continue }
            pins.append(Pin(id: stop.id, center: coordinate(of: fix), radius: Double(max(fix.accuracyMetres, 1))))
        }
        return pins
    }

    /// Every meeting, newest first.
    nonisolated static func stops(in people: [Person]) -> [Stop] {
        var stops: [Stop] = []
        for person in people {
            for encounter in person.encounters {
                stops.append(Stop(person: person, encounter: encounter))
            }
        }
        return stops.sorted { $0.encounter.date > $1.encounter.date }
    }

    nonisolated static func days(of stops: [Stop]) -> [DayGroup] {
        let calendar = Calendar.current
        var groups: [DayGroup] = []
        for stop in stops {
            let day = calendar.startOfDay(for: stop.encounter.date)
            if let index = groups.firstIndex(where: { $0.day == day }) {
                groups[index] = DayGroup(day: day, stops: groups[index].stops + [stop])
            } else {
                groups.append(DayGroup(day: day, stops: [stop]))
            }
        }
        return groups
    }

    nonisolated static func coordinate(of fix: Fix) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: Double(fix.latitudeHundredths) / 100,
                               longitude: Double(fix.longitudeHundredths) / 100)
    }
}
