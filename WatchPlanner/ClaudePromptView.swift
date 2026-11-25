import SwiftUI
import UIKit

// Make a schedule with AI: build a prompt from the event and a few answers,
// copy it to Claude, and paste the answer back into the new event.

struct ClaudePromptView: View {
    let event: String
    let raceDate: Date?
    let onAnswer: (String) -> Void

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
                    step(1, "Vertel hieronder iets over jezelf. Wij maken daar een prompt van.")
                    step(2, "Kopieer de prompt en plak hem in Claude. Een andere AI kan ook.")
                    step(3, "Kopieer het antwoord van Claude en tik hier onderaan op Plak. Je ziet meteen het schema.")
                } header: {
                    Text("Zo werkt het")
                }

                Section {
                    LabeledContent("Doel", value: event.isEmpty ? "Nog geen naam" : event)
                    LabeledContent("De grote dag", value: raceDate.map { Format.shortDay($0) } ?? "Geen datum")
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
            .navigationTitle("Schema met AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluit") { dismiss() }
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

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.caption.bold())
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Theme.accent, in: Circle())
            Text(text)
                .font(.subheadline)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
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
            HStack {
                Button("Open Claude", systemImage: "arrow.up.right") {
                    if let url = URL(string: "https://claude.ai/new") { openURL(url) }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                Spacer()
                PasteButton(payloadType: String.self) { strings in
                    guard let answer = strings.first, !answer.isEmpty else { return }
                    Task { @MainActor in
                        onAnswer(answer)
                        dismiss()
                    }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(Theme.accent)
            }
            Text("Plak zet het antwoord van Claude in je nieuwe doel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.bar)
    }
}
