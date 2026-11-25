import SwiftUI
import UIKit

// One event: its workouts grouped by week.

struct EventView: View {
    @State private var eventName: String

    init(eventName: String) {
        _eventName = State(initialValue: eventName)
    }

    @Environment(ScheduleStore.self) private var store
    @Environment(Planner.self) private var planner
    @Environment(\.dismiss) private var dismiss

    @State private var showAdd = false
    @State private var showEdit = false
    @State private var showEditSchedule = false
    @State private var confirmDelete = false
    @State private var message: Message?

    var body: some View {
        Group {
            if let event = store.event(named: eventName) {
                content(event)
            } else {
                ContentUnavailableView("Doel bestaat niet meer", systemImage: "flag.slash")
            }
        }
        .navigationTitle(eventName)
        .navigationBarTitleDisplayMode(.large)
        .alert(item: $message) { m in Alert(title: Text(m.title), message: Text(m.text)) }
    }

    private func content(_ event: TrainingSchedule) -> some View {
        List {
            if let raceDay = event.raceDate.flatMap(ScheduleDates.day) {
                HStack(spacing: 12) {
                    KindIcon(kind: .race)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("De grote dag").font(.caption).foregroundStyle(.secondary)
                        Text(Format.day(event.raceDate ?? "")).font(.headline)
                    }
                    Spacer()
                    Text(Format.countdown(to: raceDay))
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundStyle(Theme.accent)
                }
            }
            if event.workouts.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.accent)
                    Text("Nog geen trainingen")
                        .font(.title3.bold())
                    Text("Plak een schema, bijvoorbeeld van je eigen AI, of voeg zelf een training toe.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        showEditSchedule = true
                    } label: {
                        Label("Plak een schema", systemImage: "doc.on.clipboard")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button("Training toevoegen", systemImage: "plus") { showAdd = true }
                        .font(.subheadline.bold())
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .listRowBackground(Color.clear)
            }
            ForEach(weeks(event.workouts), id: \.start) { week in
                Section {
                    ForEach(week.workouts) { w in
                        NavigationLink {
                            WorkoutDetailView(workout: w, event: event)
                        } label: {
                            WorkoutRow(
                                workout: w,
                                kind: WorkoutKind(w, scheduleName: event.name, raceDate: event.raceDate),
                                isPast: ScheduleDates.isPast(w.date),
                                onWatch: planner.onWatchIDs.contains(w.id),
                                custom: planner.customIDs.contains(w.id)
                            )
                        }
                        .swipeActions {
                            Button("Verwijder", systemImage: "trash", role: .destructive) {
                                delete(w, from: event)
                            }
                            if planner.onWatchIDs.contains(w.id) {
                                Button("Van Watch", systemImage: "applewatch.slash") {
                                    Task { await planner.remove([w], time: event.defaultTime, events: store.events) }
                                }
                                .tint(.gray)
                            } else if !ScheduleDates.isPast(w.date) {
                                Button("Op Watch", systemImage: "applewatch") {
                                    Task { await planner.put([w], time: event.defaultTime, title: "Toegevoegd", events: store.events) }
                                }
                                .tint(Theme.accent)
                            }
                        }
                    }
                } header: {
                    weekHeader(week, event: event)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Zet alles op Watch", systemImage: "applewatch") {
                        Task { await planner.put(event.workouts, time: event.defaultTime, title: "\(event.name) toegevoegd", events: store.events) }
                    }
                    .disabled(event.workouts.allSatisfy { ScheduleDates.isPast($0.date) || planner.onWatchIDs.contains($0.id) })
                    Button("Wijzig schema", systemImage: "list.bullet.rectangle") { showEditSchedule = true }
                    Button("Wijzig naam en datum", systemImage: "pencil") { showEdit = true }
                    Button("Kopieer als tekst", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = WorkoutText.programText(for: event)
                        message = Message(title: "Gekopieerd",
                                          text: "Het hele schema staat op je klembord. Handig om aan je eigen AI te geven om het aan te passen.")
                    }
                    Button("Verwijder doel", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button("Training toevoegen", systemImage: "plus") { showAdd = true }
            }
        }
        .sheet(isPresented: $showEditSchedule) {
            EditScheduleView(event: event)
        }
        .sheet(isPresented: $showEdit) {
            EditEventView(original: event) { newName in eventName = newName }
        }
        .sheet(isPresented: $showAdd) {
            AddWorkoutView(
                existingIDs: Set(event.workouts.map(\.id)),
                busyDays: Dictionary(grouping: store.events.flatMap(\.workouts), by: \.date).mapValues { $0.map(\.name) }
            ) { workout, planNow in
                add(workout, to: event, planNow: planNow)
            }
        }
        .alert("\(event.name) verwijderen?", isPresented: $confirmDelete) {
            Button("Verwijder", role: .destructive) { deleteEvent(event) }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("Alle trainingen van dit doel gaan weg, ook van je Watch.")
        }
    }

    // MARK: - Week header

    private func weekHeader(_ week: Week, event: TrainingSchedule) -> some View {
        Text("Week van \(Format.dayMonth(week.start))")
    }

    // MARK: - Actions

    private func add(_ workout: PlannedWorkout, to event: TrainingSchedule, planNow: Bool) {
        do {
            try store.add(workout, to: event.name)
            if planNow {
                Task { await planner.put([workout], time: event.defaultTime, title: "Op je Watch gezet", events: store.events) }
            }
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
