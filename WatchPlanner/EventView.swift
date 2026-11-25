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

    // Sending workouts without a date, one Apple preview at a time.
    @State private var sendQueue: [PlannedWorkout] = []
    @State private var sendTotal = 0
    @State private var showSend = false
    @State private var confirmSend = false

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
                Section {
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
                } header: {
                    weekHeader(week, event: event)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Stuur alles naar Watch", systemImage: "applewatch.and.arrow.forward") {
                        confirmSend = true
                    }
                    .disabled(upcoming(event).isEmpty)
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
        .sheet(isPresented: $showAdd) {
            AddWorkoutView(
                existingIDs: Set(event.workouts.map(\.id)),
                busyDays: Dictionary(grouping: store.events.flatMap(\.workouts), by: \.date).mapValues { $0.map(\.name) }
            ) { workout, planNow in
                add(workout, to: event, planNow: planNow)
            }
        }
        .confirmationDialog("Stuur \(upcoming(event).count) trainingen naar je Watch?", isPresented: $confirmSend, titleVisibility: .visible) {
            Button("Start") { startSending(upcoming(event)) }
        } message: {
            Text("Ze komen zonder datum bij je eigen workouts onder Hardlopen buiten, en blijven daar staan. Je krijgt per training het venster van Apple: tik daar op toevoegen, en daarna onderaan op Volgende.")
        }
        .workoutPreview(WorkoutBuilder.plan(for: sendQueue.first ?? placeholder), isPresented: $showSend)
        .onChange(of: showSend) { _, shown in
            if !shown, !sendQueue.isEmpty { sendQueue.removeFirst() }
            if !shown, sendQueue.isEmpty, sendTotal > 0 {
                message = Message(title: "Klaar", text: "Kijk op je Watch in Workout, bij Hardlopen buiten. Je eigen workouts staan onder de ... knop.")
                sendTotal = 0
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !sendQueue.isEmpty && !showSend { sendBar }
        }
        .confirmationDialog("\(event.name) verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder event", role: .destructive) { deleteEvent(event) }
        } message: {
            Text("Alle trainingen van dit event gaan weg, ook van je Watch.")
        }
    }

    // MARK: - Send without date

    private func upcoming(_ event: TrainingSchedule) -> [PlannedWorkout] {
        event.workouts.filter { !ScheduleDates.isPast($0.date) }
    }

    private var placeholder: PlannedWorkout {
        PlannedWorkout(date: "2026-01-01", name: "", warmup: nil, blocks: [], cooldown: nil)
    }

    private func startSending(_ workouts: [PlannedWorkout]) {
        sendQueue = workouts
        sendTotal = workouts.count
        showSend = true
    }

    private var sendBar: some View {
        let done = sendTotal - sendQueue.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(done) van \(sendTotal) gedaan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Volgende: \(sendQueue.first?.name ?? "")")
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            Spacer()
            Button("Stop") {
                sendQueue = []
                sendTotal = 0
            }
            .buttonStyle(.bordered)
            Button("Volgende") { showSend = true }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Week header

    @ViewBuilder
    private func weekHeader(_ week: Week, event: TrainingSchedule) -> some View {
        let upcoming = week.workouts.filter { !ScheduleDates.isPast($0.date) }
        let onWatch = upcoming.filter { planner.onWatchIDs.contains($0.id) }
        let title = "Week van \(Format.dayMonth(week.start))"

        HStack {
            Text(title)
            Spacer()
            if !upcoming.isEmpty {
                if onWatch.count == upcoming.count {
                    Menu {
                        Button("Opnieuw klaarzetten", systemImage: "arrow.clockwise") {
                            Task { await planner.put(upcoming, time: event.defaultTime, title: "\(title) klaargezet", events: store.events) }
                        }
                        Button("Haal week van Watch", systemImage: "applewatch.slash", role: .destructive) {
                            Task { await planner.remove(upcoming, time: event.defaultTime, events: store.events) }
                        }
                    } label: {
                        Label("Week op Watch", systemImage: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.accent)
                    }
                } else {
                    Button {
                        Task { await planner.put(upcoming, time: event.defaultTime, title: "\(title) klaargezet", events: store.events) }
                    } label: {
                        Text(onWatch.isEmpty ? "Zet week op Watch" : "Zet rest op Watch")
                            .font(.caption.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.accent, in: Capsule())
                    }
                    .disabled(planner.isBusy)
                }
            } else {
                Text("Geweest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
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
