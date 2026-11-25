import SwiftUI
import WorkoutKit

struct WorkoutDetailView: View {
    let workout: PlannedWorkout
    let time: String

    @State private var showPreview = false

    var body: some View {
        List {
            Section {
                LabeledContent("Datum", value: Format.day(workout.date))
                LabeledContent("Tijd", value: time)
            }

            if let warmup = workout.warmup {
                Section("Warming-up") { stepRow(goal: warmup.goal, zone: warmup.zone) }
            }

            ForEach(Array((workout.blocks ?? []).enumerated()), id: \.offset) { index, block in
                Section(blockTitle(block, index: index)) {
                    ForEach(Array(block.steps.enumerated()), id: \.offset) { _, step in
                        stepRow(
                            title: step.purpose == .work ? "Hard" : "Herstel",
                            goal: step.goal,
                            zone: step.zone
                        )
                    }
                }
            }

            if let cooldown = workout.cooldown {
                Section("Cooling-down") { stepRow(goal: cooldown.goal, zone: cooldown.zone) }
            }

            Section {
                Button("Bekijk op Watch-voorbeeld", systemImage: "applewatch") {
                    showPreview = true
                }
            }
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .workoutPreview(WorkoutBuilder.plan(for: workout), isPresented: $showPreview)
    }

    private func blockTitle(_ block: BlockSpec, index: Int) -> String {
        let blocks = workout.blocks ?? []
        if blocks.count == 1, block.iterations == 1, block.steps.count == 1, workout.warmup == nil {
            return "Rustige loop"
        }
        let name = blocks.count > 1 ? "Blok \(index + 1)" : "Blok"
        return "\(name), \(block.iterations)x"
    }

    private func stepRow(title: String? = nil, goal: GoalSpec, zone: Int?) -> some View {
        HStack {
            if let title { Text(title).bold() }
            Text(goal.label)
            Spacer()
            Text(zone.map { "Zone \($0)" } ?? "Geen alert")
                .foregroundStyle(.secondary)
        }
    }
}
