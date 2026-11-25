import SwiftUI
import UIKit

// Home: next workout, all events, and what is on the Watch.

struct EventsView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Planner.self) private var planner

    @State private var showImport = false
    @State private var showNewEvent = false
    @State private var newEventName = ""
    @State private var error: Message?

    var body: some View {
        @Bindable var planner = planner
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
                        Text("Nog geen events. Tik op + om er een te maken of een schema te importeren.")
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

                Section {
                    if planner.watchItems.isEmpty {
                        Text("Nog niets. Tik op Plan op Watch.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(planner.watchItems) { item in
                        watchRow(item)
                    }
                } header: {
                    Text("Op je Watch")
                } footer: {
                    Text("Alleen trainingen die deze app heeft ingepland. Andere apps zie je hier niet.")
                }
            }
            .navigationTitle("Rondje")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Importeer schema", systemImage: "square.and.arrow.down") { showImport = true }
                        Button("Nieuw leeg event", systemImage: "flag") {
                            newEventName = ""
                            showNewEvent = true
                        }
                        Divider()
                        Button("Kopieer prompt voor Claude", systemImage: "sparkles") {
                            UIPasteboard.general.string = WorkoutText.claudePrompt
                            error = Message(title: "Prompt gekopieerd",
                                            text: "Plak hem in Claude, zet je doel eronder en plak het antwoord terug via Importeer schema.")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Toevoegen")
                }
            }
            .safeAreaInset(edge: .bottom) { PlanButton() }
            .sheet(isPresented: $showImport) { ImportView() }
            .alert("Nieuw event", isPresented: $showNewEvent) {
                TextField("Naam, bijvoorbeeld Zevenheuvelenloop", text: $newEventName)
                Button("Annuleer", role: .cancel) {}
                Button("Maak") {
                    do { try store.createEvent(named: newEventName) } catch {
                        self.error = Message(title: "Lukt niet", text: error.localizedDescription)
                    }
                }
            }
            .alert(item: $planner.message) { m in Alert(title: Text(m.title), message: Text(m.text)) }
            .alert(item: $error) { m in Alert(title: Text(m.title), message: Text(m.text)) }
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
        let kind = WorkoutKind(w, scheduleName: event.name)
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
        let last = e.workouts.last.map { Format.shortDay($0.date) }

        return HStack(spacing: 14) {
            KindIcon(kind: .race)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.name).font(.headline)
                Text([
                    "\(total) trainingen",
                    last.map { "t/m \($0)" },
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

    private func watchRow(_ item: WatchItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.complete ? "checkmark.circle.fill" : "applewatch")
                .font(.title3)
                .foregroundStyle(item.complete ? Theme.accent : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(item.date.map(Format.shortDay) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.complete {
                Text("Gedaan").font(.caption.bold()).foregroundStyle(Theme.accent)
            } else if item.workoutID == nil {
                Text("Niet meer in schema").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func relativeDay(_ day: String) -> String {
        guard let date = ScheduleDates.day(day) else { return day }
        let cal = ScheduleDates.calendar
        if cal.isDateInToday(date) { return "Vandaag" }
        if cal.isDateInTomorrow(date) { return "Morgen" }
        return Format.shortDay(date)
    }
}
