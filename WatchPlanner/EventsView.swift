import SwiftUI
import UIKit

// Home: next workout and all events.

struct EventsView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Planner.self) private var planner

    @State private var showNewEvent = false

    var body: some View {
        NavigationStack {
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

                Section("Events") {
                    if store.events.isEmpty {
                        Text("Nog geen events. Tik op + om er een te maken.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.events, id: \.name) { event in
                        NavigationLink {
                            EventView(eventName: event.name)
                        } label: {
                            eventRow(event)
                        }
                    }
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
                    .accessibilityLabel("Nieuw event")
                }
            }
            .sheet(isPresented: $showNewEvent) { NewEventView() }
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
