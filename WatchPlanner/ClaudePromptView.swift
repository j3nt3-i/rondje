import SwiftUI
import UIKit

// Make a schedule with AI in three steps: build and copy a prompt, open your own AI app
// (Claude, ChatGPT, Gemini), and paste the answer back into the new goal.

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
            Group {
                if flow == 0 { form } else { stepScreen }
            }
            .animation(.snappy, value: flow)
            .navigationTitle("Schema met AI")
            .keyboardDoneButton()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluit") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) { progress }
            .safeAreaInset(edge: .bottom) {
                if flow == 0 {
                    bigButton("Kopieer prompt", "doc.on.doc") {
                        UIPasteboard.general.string = prompt
                        flow = 1
                    }
                    .padding()
                    .background(.bar)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Back from the AI app: the next step is pasting the answer.
                if phase == .active && openedApp && flow == 1 { flow = 2 }
            }
        }
    }

    // MARK: - Step 1: about you and the prompt

    private var form: some View {
        Form {
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
            } footer: {
                Text("Hierna open je je eigen AI-app, plak je de prompt en plak je het antwoord hier terug.")
            }
        }
    }

    // MARK: - Steps 2 and 3: full screen

    private var stepScreen: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15)).frame(width: 150, height: 150)
                Image(systemName: flow == 1 ? "arrow.up.forward.app.fill" : "doc.on.clipboard.fill")
                    .font(.system(size: 60, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text(flow == 1 ? "Open je AI-app" : "Plak het antwoord")
                    .font(.system(.largeTitle, design: .rounded).bold())
                Text(flow == 1
                     ? "De prompt staat op je klembord. Open je AI-app, plak hem en verstuur."
                     : "Kopieer het hele antwoord van je AI-app en plak het hier. Je ziet meteen je trainingen.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            Spacer(minLength: 0)

            if flow == 1 {
                VStack(spacing: 12) {
                    ForEach(apps, id: \.name) { app in
                        bigButton(app.name, "arrow.up.right") {
                            if let url = URL(string: app.url) {
                                openedApp = true
                                openURL(url)
                            }
                        }
                    }
                    Button("Ik heb het antwoord al") { flow = 2 }
                        .font(.subheadline.bold())
                        .padding(.top, 4)
                }
            } else {
                VStack(spacing: 14) {
                    PasteButton(payloadType: String.self) { strings in
                        guard let answer = strings.first, !answer.isEmpty else { return }
                        Task { @MainActor in
                            onAnswer(answer)
                            dismiss()
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    .controlSize(.extraLarge)
                    .tint(Theme.accent)
                    Button("Prompt nog een keer kopiëren") {
                        UIPasteboard.general.string = prompt
                    }
                    .font(.subheadline.bold())
                }
            }

            Button("Terug") { flow -= 1 }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i <= flow ? Theme.accent : Color(white: 0.25))
                    .frame(height: 5)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .accessibilityElement()
        .accessibilityLabel("Stap \(flow + 1) van 3")
    }

    private var prompt: String {
        WorkoutText.claudePrompt(event: event, raceDate: raceDate, perWeek: perWeek,
                                 level: level, goal: goal, wishes: wishes)
    }

    private let apps: [(name: String, url: String)] = [
        ("Claude", "https://claude.ai/new"),
        ("ChatGPT", "https://chatgpt.com/"),
        ("Gemini", "https://gemini.google.com/app"),
    ]

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
