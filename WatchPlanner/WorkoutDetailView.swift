import SwiftUI
import UIKit
import WorkoutKit

struct WorkoutDetailView: View {
    let workout: PlannedWorkout
    let event: TrainingSchedule

    @Environment(Planner.self) private var planner
    @State private var showPreview = false
    @State private var copied = false

    var body: some View {
        let kind = WorkoutKind(workout, scheduleName: event.name)
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    KindIcon(kind: kind, size: 64)
                    Text(workout.name)
                        .font(.system(.title, design: .rounded).bold())
                    Text("\(Format.day(workout.date)) · \(event.defaultTime)")
                        .font(.headline)
                        .foregroundStyle(kind.color)
                    if planner.onWatchIDs.contains(workout.id) {
                        Label("Staat op je Watch", systemImage: "applewatch.radiowaves.left.and.right")
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                    } else if ScheduleDates.isPast(workout.date) {
                        Label("Geweest", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }

            Section("Opbouw") {
                ForEach(workout.stepLines) { StepLineView(line: $0) }
            }

            Section {
                Text(WorkoutText.text(for: workout))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Button(copied ? "Gekopieerd" : "Kopieer als tekst",
                       systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = WorkoutText.text(for: workout)
                    copied = true
                }
            } header: {
                Text("Als tekst")
            }

            Section {
                Button {
                    showPreview = true
                } label: {
                    Label("Bekijk Watch-voorbeeld", systemImage: "applewatch")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .listRowBackground(Theme.accent)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .workoutPreview(WorkoutBuilder.plan(for: workout), isPresented: $showPreview)
    }
}
