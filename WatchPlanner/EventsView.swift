import SwiftUI
import UIKit

// Home: next workout and all goals (stored as events), or a welcome screen when there are none.

struct EventsView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Planner.self) private var planner

    @State private var showNewEvent = false

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
            .sheet(isPresented: $showNewEvent) { NewEventView() }
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
                    }
                }

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

/// Shown when there are no goals yet: what the app does in three steps, and one button.
struct EmptyHome: View {
    let onNew: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.15)).frame(width: 140, height: 140)
                    Image(systemName: "figure.run")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.top, 24)
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Waar train je voor?")
                        .font(.system(.largeTitle, design: .rounded).bold())
                    Text("Maak een doel, zoals een wedstrijd. Rondje zet je trainingen op de juiste dag op je Watch.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 20) {
                    step("flag.checkered", "Kies je doel", "Bijvoorbeeld de Zevenheuvelenloop, met de datum erbij.")
                    step("sparkles", "Zet er een schema in", "Plak het van Claude, of typ het zelf.")
                    step("applewatch", "Elke ochtend op je pols", "De training van vandaag staat klaar in Workout.")
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))

                Button(action: onNew) {
                    Label("Nieuw doel", systemImage: "plus")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent, in: Capsule())
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private func step(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
