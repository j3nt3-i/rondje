import SwiftUI
import UIKit
import WorkoutKit

struct WorkoutDetailView: View {
    let workout: PlannedWorkout
    let event: TrainingSchedule

    @Environment(Planner.self) private var planner
    @State private var showPreview = false
    @State private var askAdded = false
    @State private var copied = false

    var body: some View {
        let kind = WorkoutKind(workout, scheduleName: event.name, raceDate: event.raceDate)
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    KindIcon(kind: kind, size: 64)
                    Text(workout.name)
                        .font(.system(.title, design: .rounded).bold())
                    Text("\(Format.day(workout.date)) · \(event.defaultTime)")
                        .font(.headline)
                        .foregroundStyle(kind.color)
                    if planner.customIDs.contains(workout.id) {
                        HStack {
                            Label("Bij je eigen workouts op je Watch", systemImage: "applewatch")
                                .font(.subheadline)
                                .foregroundStyle(Theme.accent)
                            Spacer()
                            Button("Weg") { planner.setCustom(workout.id, false) }
                                .font(.caption.bold())
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                        }
                    }
                    if planner.onWatchIDs.contains(workout.id) {
                        Label(ScheduleDates.watchVisibleFrom(workout.date).map {
                                  "Toegevoegd, op je Watch vanaf \(Format.shortDay($0).lowercased())"
                              } ?? "Staat op je Watch",
                              systemImage: "applewatch")
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
                    Label("Voeg toe aan je workouts", systemImage: "applewatch")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .listRowBackground(Theme.accent)
            } footer: {
                Text("Komt direct bij je eigen workouts op je Watch, zonder datum.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .workoutPreview(WorkoutBuilder.plan(for: workout), isPresented: $showPreview)
        .onChange(of: showPreview) { wasShown, shown in
            // Apple's preview does not tell whether "add" was tapped, so ask.
            if wasShown && !shown && !planner.customIDs.contains(workout.id) { askAdded = true }
        }
        .confirmationDialog("Heb je hem toegevoegd aan je Watch?", isPresented: $askAdded, titleVisibility: .visible) {
            Button("Ja, toegevoegd") { planner.setCustom(workout.id, true) }
            Button("Nee", role: .cancel) {}
        } message: {
            Text("Dan zie je in de lijst dat hij bij je eigen workouts staat.")
        }
    }
}
