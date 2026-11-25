import SwiftUI
import UIKit

// One event: its workouts grouped by week.

struct EventView: View {
    let eventName: String

    @Environment(ScheduleStore.self) private var store
    @Environment(Planner.self) private var planner
    @Environment(\.dismiss) private var dismiss

    @State private var showAdd = false
    @State private var confirmDelete = false
    @State private var message: Message?

    var body: some View {
        Group {
            if let event = store.event(named: eventName) {
                content(event)
            } else {
                ContentUnavailableView("Event bestaat niet meer", systemImage: "flag.slash")
            }
        }
        .navigationTitle(eventName)
        .navigationBarTitleDisplayMode(.large)
        .alert(item: $message) { m in Alert(title: Text(m.title), message: Text(m.text)) }
    }

    private func content(_ event: TrainingSchedule) -> some View {
        List {
            if event.workouts.isEmpty {
                Text("Nog geen trainingen. Tik op + om er een toe te voegen.")
                    .foregroundStyle(.secondary)
            }
            ForEach(weeks(event.workouts), id: \.start) { week in
                Section("Week van \(Format.dayMonth(week.start))") {
                    ForEach(week.workouts) { w in
                        NavigationLink {
                            WorkoutDetailView(workout: w, event: event)
                        } label: {
                            WorkoutRow(
                                workout: w,
                                kind: WorkoutKind(w, scheduleName: event.name),
                                isPast: ScheduleDates.isPast(w.date),
                                onWatch: planner.onWatchIDs.contains(w.id)
                            )
                        }
                        .swipeActions {
                            Button("Verwijder", systemImage: "trash", role: .destructive) {
                                delete(w, from: event)
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Kopieer als tekst", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = WorkoutText.programText(for: event)
                        message = Message(title: "Gekopieerd",
                                          text: "Het hele schema staat op je klembord. Handig om aan Claude te geven om het aan te passen.")
                    }
                    Button("Verwijder event", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button("Training toevoegen", systemImage: "plus") { showAdd = true }
            }
        }
        .safeAreaInset(edge: .bottom) { PlanButton() }
        .sheet(isPresented: $showAdd) {
            AddWorkoutView(existingIDs: Set(event.workouts.map(\.id))) { workout, planNow in
                add(workout, to: event, planNow: planNow)
            }
        }
        .confirmationDialog("\(event.name) verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder event", role: .destructive) { deleteEvent(event) }
        } message: {
            Text("Alle trainingen van dit event gaan weg, ook van je Watch.")
        }
    }

    // MARK: - Actions

    private func add(_ workout: PlannedWorkout, to event: TrainingSchedule, planNow: Bool) {
        do {
            try store.add(workout, to: event.name)
            if planNow { Task { await planner.plan(store.events) } }
        } catch {
            message = Message(title: "Lukt niet", text: error.localizedDescription)
        }
    }

    private func delete(_ workout: PlannedWorkout, from event: TrainingSchedule) {
        do {
            try store.delete(workout, from: event.name)
            Task { await planner.remove([workout], time: event.defaultTime, events: store.events) }
        } catch {
            message = Message(title: "Lukt niet", text: error.localizedDescription)
        }
    }

    private func deleteEvent(_ event: TrainingSchedule) {
        do {
            try store.deleteEvent(named: event.name)
            Task { await planner.remove(event.workouts, time: event.defaultTime, events: store.events) }
            dismiss()
        } catch {
            message = Message(title: "Lukt niet", text: error.localizedDescription)
        }
    }

    // MARK: - Weeks

    private struct Week {
        var start: Date
        var workouts: [PlannedWorkout]
    }

    private func weeks(_ workouts: [PlannedWorkout]) -> [Week] {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let grouped = Dictionary(grouping: workouts.sorted { $0.date < $1.date }) { w -> Date in
            let day = ScheduleDates.day(w.date) ?? .distantPast
            return cal.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        }
        return grouped.keys.sorted().map { Week(start: $0, workouts: grouped[$0] ?? []) }
    }
}
