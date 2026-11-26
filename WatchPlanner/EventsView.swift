import SwiftUI
import UIKit

// Home: next workout and all goals (stored as events), or a welcome screen when there are none.

struct EventsView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Planner.self) private var planner

    @State private var showNewEvent = false
    @State private var toDelete: TrainingSchedule?

    var body: some View {
        NavigationStack {
            Group {
                if store.events.isEmpty && store.loadError == nil {
                    EmptyHome { showNewEvent = true }
                } else {
                    list
                }
            }
            .navigationTitle("Rondje")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.events.isEmpty {
                    Button {
                        showNewEvent = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Nieuw doel")
                    }
                }
            }
            .sheet(isPresented: $showNewEvent) { NewGoalView() }
        }
    }

    private var list: some View {
            List {
                if let loadError = store.loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                if let (event, workout) = nextWorkout {
                    Section("Volgende training") {
                        NavigationLink {
                            WorkoutDetailView(workout: workout, event: event)
                        } label: {
                            nextCard(workout, event: event)
                        }
                    }
                }

                Section("Doelen") {
                    ForEach(store.events, id: \.name) { event in
                        NavigationLink {
                            EventView(eventName: event.name)
                        } label: {
                            eventRow(event)
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            // Asks first: a whole goal with all its workouts is a lot to lose by accident.
                            Button("Verwijder", systemImage: "trash") { toDelete = event }
                                .tint(.red)
                        }
                    }
                }

            }
            .alert("\(toDelete?.name ?? "Doel") verwijderen?", isPresented: Binding(
                get: { toDelete != nil },
                set: { if !$0 { toDelete = nil } }
            ), presenting: toDelete) { event in
                Button("Verwijder", role: .destructive) { delete(event) }
                Button("Annuleer", role: .cancel) {}
            } message: { _ in
                Text("Alle trainingen van dit doel gaan weg, ook van je Watch.")
            }
    }

    private func delete(_ event: TrainingSchedule) {
        do {
            try store.deleteEvent(named: event.name)
            Task { await planner.remove(event.workouts, time: event.defaultTime, events: store.events) }
        } catch {
            planner.message = Message(title: "Lukt niet", text: error.localizedDescription)
        }
    }

    // MARK: - Rows

    private var nextWorkout: (TrainingSchedule, PlannedWorkout)? {
        store.events
            .flatMap { e in e.workouts.map { (e, $0) } }
            .filter { !ScheduleDates.isPast($0.1.date) }
            .min { $0.1.date < $1.1.date }
    }

    private func nextCard(_ w: PlannedWorkout, event: TrainingSchedule) -> some View {
        let kind = WorkoutKind(w, scheduleName: event.name, raceDate: event.raceDate)
        return HStack(spacing: 14) {
            KindIcon(kind: kind, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(relativeDay(w.date))
                    .font(.subheadline.bold())
                    .foregroundStyle(kind.color)
                Text(w.name)
                    .font(.system(.title3, design: .rounded).bold())
                Text(WorkoutText.text(for: w, zones: false, separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private func eventRow(_ e: TrainingSchedule) -> some View {
        let total = e.workouts.count
        let done = e.workouts.filter { ScheduleDates.isPast($0.date) }.count
        let onWatch = e.workouts.filter { planner.onWatchIDs.contains($0.id) }.count
        let race = e.raceDate.flatMap(ScheduleDates.day)

        return HStack(spacing: 14) {
            KindIcon(kind: .race)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.name).font(.headline)
                if let race {
                    Text("\(Format.shortDay(race)) · \(Format.countdown(to: race))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                }
                Text([
                    "\(total) trainingen",
                    onWatch > 0 ? "\(onWatch) op Watch" : nil,
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                if total > 0 {
                    ProgressView(value: Double(done), total: Double(total))
                        .tint(Theme.accent)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func relativeDay(_ day: String) -> String {
        guard let date = ScheduleDates.day(day) else { return day }
        let cal = ScheduleDates.calendar
        if cal.isDateInToday(date) { return "Vandaag" }
        if cal.isDateInTomorrow(date) { return "Morgen" }
        return Format.shortDay(date)
    }
}

// MARK: - Welcome

/// Shown when there are no goals yet: three swipeable pages on what the app does, and one button.
struct EmptyHome: View {
    let onNew: () -> Void
    @State private var page = 0

    private struct Page {
        let title: String
        let text: String
    }

    private let pages = [
        Page(title: "Waar train je voor?", text: "Kies een doel, zoals een wedstrijd of je eerste 10\u{00A0}km. Rondje telt met je af."),
        Page(title: "Zet er een schema in", text: "Laat je eigen AI, zoals Claude of ChatGPT, een schema maken. Of typ je trainingen zoals je ze zegt."),
        Page(title: "Elke ochtend op je pols", text: "De training van vandaag staat klaar in Workout op je Watch, met hartslagzones."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 28) {
                        Spacer(minLength: 0)
                        art(i)
                            .accessibilityHidden(true)
                        VStack(spacing: 10) {
                            Text(pages[i].title)
                                .font(.system(.largeTitle, design: .rounded).bold())
                            Text(pages[i].text)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 44)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            Button(action: onNew) {
                Label("Nieuw doel", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent, in: Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func art(_ i: Int) -> some View {
        switch i {
        case 0: GoalArt()
        case 1: ScheduleArt()
        default: WatchArt()
        }
    }
}
