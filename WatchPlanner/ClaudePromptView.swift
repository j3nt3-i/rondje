import SwiftUI
import UIKit

// Builds the prompt for Claude from the event and a few answers, shows it, and copies it.

struct ClaudePromptView: View {
    let event: String
    let raceDate: Date?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // Remembered for next time on this phone.
    @AppStorage("prompt.perWeek") private var perWeek = 3
    @AppStorage("prompt.level") private var level = ""
    @State private var goal = ""
    @State private var wishes = ""
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Event", value: event.isEmpty ? "Nog geen naam" : event)
                    LabeledContent("Wedstrijd", value: raceDate.map { Format.shortDay($0) } ?? "Geen datum")
                } footer: {
                    Text("Uit het vorige scherm. Pas het daar aan als het niet klopt.")
                }

                Section("Over jou") {
                    Stepper("\(perWeek)x per week lopen", value: $perWeek, in: 1...7)
                    TextField("Niveau nu, bijv. 2x per week 5 km", text: $level, axis: .vertical)
                    TextField("Doel, bijv. uitlopen of onder 1:20", text: $goal, axis: .vertical)
                    TextField("Wensen, bijv. lange duurloop op zondag", text: $wishes, axis: .vertical)
                }

                Section {
                    Text(prompt)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } header: {
                    Text("De prompt")
                }
            }
            .navigationTitle("Prompt voor Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .onChange(of: prompt) { copied = false }
        }
    }

    private var prompt: String {
        WorkoutText.claudePrompt(event: event, raceDate: raceDate, perWeek: perWeek,
                                 level: level, goal: goal, wishes: wishes)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                UIPasteboard.general.string = prompt
                copied = true
            } label: {
                Label(copied ? "Gekopieerd" : "Kopieer prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: Capsule())
            }
            Button("Open Claude") {
                if let url = URL(string: "https://claude.ai/new") { openURL(url) }
            }
            .font(.subheadline.bold())
            if copied {
                Text("Plak hem in Claude, kopieer het antwoord en plak dat in Schema.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(.bar)
    }
}
