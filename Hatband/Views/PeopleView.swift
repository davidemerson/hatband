import HatbandCore
import SwiftUI

/// The people you have scanned: search, a tag filter, `+` rows, and the
/// undo banner after a Forget.
@MainActor struct PeopleView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var tag: String?

    init() {}

    var body: some View {
        if model.locked {
            LockedView()
        } else {
            NavigationStack(path: path) {
                content
                    .navigationTitle("People")
                    .navigationDestination(for: String.self) { id in
                        PersonView(personID: id)
                    }
                    .safeAreaInset(edge: .bottom) {
                        if let person = model.undo {
                            undoBanner(person)
                        }
                    }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if model.people.isEmpty {
            ContentUnavailableView("No fixed abode.", systemImage: "person.2",
                                   description: Text("Scan a card and the person appears here."))
        } else {
            List {
                if !model.tagNames.isEmpty {
                    tagFilter
                }
                let shown = people
                if shown.isEmpty {
                    Text("No one matches.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { person in
                    NavigationLink(value: person.id) {
                        row(person)
                    }
                }
            }
            .searchable(text: $query, prompt: "Name, company, tag, place")
        }
    }

    private var people: [Person] {
        let matching = model.people(matching: query)
        guard let tag else { return matching }
        return matching.filter { $0.tags.contains(tag) }
    }

    private var tagFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(model.tagNames, id: \.self) { name in
                    Button(name) {
                        tag = tag == name ? nil : name
                    }
                    .buttonStyle(.bordered)
                    .tint(tag == name ? Theme.accent : Theme.tertiary)
                }
            }
        }
        .listRowSeparator(.hidden)
    }

    private func row(_ person: Person) -> some View {
        PlusRow {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.personaColor(person.card.color))
                        .frame(width: 8, height: 8)
                    Text(person.card.name ?? "Unnamed")
                        .font(.body)
                    if person.card.flags.contains(.alias) {
                        Image(systemName: Theme.flower)
                            .foregroundStyle(Theme.tertiary)
                            .accessibilityLabel("Alias")
                    }
                }
                Text(PeopleView.subtitle(for: person))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func undoBanner(_ person: Person) -> some View {
        HStack {
            Text("Forgot \(person.card.name ?? "a person").")
            Spacer()
            Button("Undo") {
                do {
                    try model.restoreForgotten()
                } catch {
                    model.error = AppError(error)
                }
            }
        }
        .padding()
        .background(Theme.secondary, in: RoundedRectangle(cornerRadius: Theme.radius))
        .padding()
    }

    private var path: Binding<[String]> {
        Binding(
            get: { model.route.person.map { [$0] } ?? [] },
            set: { model.route.person = $0.last })
    }

    /// Company, or the most recent meeting.
    nonisolated static func subtitle(for person: Person) -> String {
        if let company = person.card.company {
            return company
        }
        guard let last = person.encounters.max(by: { $0.date < $1.date }) else { return "" }
        let day = last.date.formatted(date: .abbreviated, time: .omitted)
        return last.label.isEmpty ? "Met " + day : "Met " + day + " · " + last.label
    }
}
