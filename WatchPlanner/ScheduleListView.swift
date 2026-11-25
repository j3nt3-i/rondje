import SwiftUI
import UIKit
import WorkoutKit

struct ScheduleListView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var onWatch: Set<String> = []
    @State private var isBusy = false
    @State private var message: Message?

    private let service = ScheduleService()

    var body: some View {
        NavigationStack {
            Group {
                if let schedule = store.schedule {
                    list(schedule)
                } else {
                    ContentUnavailableView(
                        "Geen schema",
                        systemImage: "exclamationmark.triangle",
                        description: Text(store.loadError ?? "Plak een nieuw schema om te beginnen.")
                    )
                }
            }
            .navigationTitle(store.schedule?.name ?? "Watch Planner")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Plak nieuw schema", systemImage: "doc.on.clipboard", action: paste)
                }
            }
            .safeAreaInset(edge: .bottom) { planButton }
            .alert(item: $message) { m in
                Alert(title: Text(m.title), message: Text(m.text))
            }
        }
        .task(id: store.schedule) { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    // MARK: - List

    private func list(_ schedule: TrainingSchedule) -> some View {
        List {
            ForEach(weeks(schedule.workouts), id: \.start) { week in
                Section(week.title) {
                    ForEach(week.workouts) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout, time: schedule.defaultTime)
                        } label: {
                            row(workout)
                        }
                    }
                }
            }
        }
    }

    private func row(_ workout: PlannedWorkout) -> some View {
        let status = status(of: workout)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name)
                    .foregroundStyle(status == .past ? .secondary : .primary)
                Text(Format.day(workout.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(status.label, systemImage: status.icon)
                .font(.caption)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(status.color)
        }
    }

    private var planButton: some View {
        Button(action: plan) {
            HStack {
                if isBusy { ProgressView().tint(.white) }
                Text(isBusy ? "Bezig..." : "Plan op Watch")
                    .bold()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isBusy || store.schedule == nil)
        .padding()
        .background(.bar)
    }

    // MARK: - Status

    enum Status {
        case planned, past, onWatch

        var label: String {
            switch self {
            case .planned: "Gepland"
            case .past: "Geweest"
            case .onWatch: "Op Watch"
            }
        }

        var icon: String {
            switch self {
            case .planned: "calendar"
            case .past: "clock.arrow.circlepath"
            case .onWatch: "applewatch"
            }
        }

        var color: Color {
            switch self {
            case .planned: .secondary
            case .past: .secondary
            case .onWatch: .green
            }
        }
    }

    private func status(of workout: PlannedWorkout) -> Status {
        if ScheduleDates.isPast(workout.date) { return .past }
        return onWatch.contains(workout.id) ? .onWatch : .planned
    }

    // MARK: - Actions

    private func refresh() async {
        guard let schedule = store.schedule else { onWatch = []; return }
        onWatch = await service.scheduledIDs(in: schedule)
    }

    private func plan() {
        guard let schedule = store.schedule else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let result = try await service.planOnWatch(schedule)
                await refresh()
                message = Message(result)
            } catch {
                message = Message(title: "Plannen lukt niet", text: error.localizedDescription)
            }
        }
    }

    private func paste() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            message = Message(title: "Klembord is leeg", text: "Kopieer eerst je schema als JSON.")
            return
        }
        do {
            try store.replace(with: text)
            let count = store.schedule?.workouts.count ?? 0
            message = Message(
                title: "Nieuw schema geladen",
                text: "\(count) trainingen. Tik op Plan op Watch om ze op je Watch te zetten."
            )
        } catch {
            message = Message(title: "Schema klopt niet", text: error.localizedDescription)
        }
    }

    // MARK: - Weeks

    struct Week {
        var start: Date
        var workouts: [PlannedWorkout]
        var title: String { "Week van \(Format.weekStart.string(from: start))" }
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

// MARK: - Alert message

struct Message: Identifiable {
    let id = UUID()
    var title: String
    var text: String
}

extension Message {
    init(_ r: ScheduleResult) {
        var lines = ["\(r.scheduled) trainingen staan op je Watch."]
        if r.skippedPast > 0 {
            lines.append("\(r.skippedPast) overgeslagen omdat ze al geweest zijn.")
        }
        if r.overLimit > 0 {
            lines.append("Let op: je Watch kan er maar \(r.limit) tegelijk hebben. De eerste \(r.limit) staan erop, \(r.overLimit) niet. Plan later opnieuw.")
        }
        if !r.missing.isEmpty {
            lines.append("Niet gelukt: \(r.missing.joined(separator: ", ")).")
        }
        self.init(title: r.missing.isEmpty ? "Gepland" : "Deels gepland", text: lines.joined(separator: "\n\n"))
    }
}

// MARK: - Formatting

enum Format {
    static let weekStart: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.dateFormat = "d MMMM"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    static func day(_ string: String) -> String {
        guard let date = ScheduleDates.day(string) else { return string }
        return dayFormatter.string(from: date).capitalized(with: Locale(identifier: "nl_NL"))
    }
}
