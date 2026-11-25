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
    /// Where you are in the flow at the bottom: 0 copy the prompt, 1 open an AI app, 2 paste the answer.
    @State private var flow = 0
    @State private var openedApp = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    step(1, "Vertel hieronder iets over jezelf. Wij maken daar een prompt van.")
                    step(2, "Kopieer de prompt en plak hem in je AI-app, zoals Claude, ChatGPT of Gemini.")
                    step(3, "Kopieer het antwoord en tik hier op Plak. Je ziet meteen het schema.")
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
            .keyboardDoneButton()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluit") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .onChange(of: prompt) { if flow > 0 { flow = 0 } }
            .onChange(of: scenePhase) { _, phase in
                // Back from the AI app: the next step is pasting the answer.
                if phase == .active && openedApp { withAnimation { flow = 2 } }
            }
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

    private let apps: [(name: String, url: String)] = [
        ("Claude", "https://claude.ai/new"),
        ("ChatGPT", "https://chatgpt.com/"),
        ("Gemini", "https://gemini.google.com/app"),
    ]

    private var actions: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Stap \(flow + 1) van 3")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if flow > 0 {
                    Button("Terug") { withAnimation { flow -= 1 } }
                        .font(.caption.bold())
                }
            }

            switch flow {
            case 0:
                bigButton("Kopieer prompt", "doc.on.doc") {
                    UIPasteboard.general.string = prompt
                    withAnimation { flow = 1 }
                }
            case 1:
                Text("Gekopieerd. Open je AI-app en plak de prompt.")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    ForEach(apps, id: \.name) { app in
                        Button {
                            if let url = URL(string: app.url) {
                                openedApp = true
                                openURL(url)
                            }
                        } label: {
                            Text(app.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.accent, in: Capsule())
                        }
                    }
                }
                Button("Ik heb het antwoord al") { withAnimation { flow = 2 } }
                    .font(.footnote.bold())
            default:
                Text("Kopieer het antwoord van je AI-app en plak het hier.")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PasteButton(payloadType: String.self) { strings in
                    guard let answer = strings.first, !answer.isEmpty else { return }
                    Task { @MainActor in
                        onAnswer(answer)
                        dismiss()
                    }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(Theme.accent)
            }
        }
        .padding()
        .background(.bar)
    }

    private func bigButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent, in: Capsule())
        }
    }

}
