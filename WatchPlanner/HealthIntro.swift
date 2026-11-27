import SwiftUI

// Before a new goal: why Rondje would like to look in Apple Health, and then Apple's own sheet.
// Shown only while there is still something to ask and you have not said "Niet nu".

/// A new goal, with the Apple Health question first when it has not been asked yet.
struct NewGoalFlow: View {
    @Environment(HealthLog.self) private var health
    /// Decided once, when the sheet opens, so the screen does not swap under you.
    @State private var intro: Bool?

    var body: some View {
        Group {
            if intro ?? (health.canAskLevel && !health.declined) {
                HealthIntro { intro = false }
            } else {
                NewGoalView()
            }
        }
        .onAppear { if intro == nil { intro = health.canAskLevel && !health.declined } }
    }
}

struct HealthIntro: View {
    /// Called when you are done here, whatever you chose.
    let onDone: () -> Void

    @Environment(HealthLog.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var asking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.pink)
                            .frame(width: 64, height: 64)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityHidden(true)
                        Text("Een schema dat bij je past")
                            .font(.system(.largeTitle, design: .rounded).bold())
                        Text("Daarvoor kijkt Rondje graag even in Apple Health.")
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        row("figure.run", "Wat je nu loopt",
                            "Je kilometers, langste loop, tempo en VO2max. Je ziet ze eerst en zegt zelf of ze in je prompt komen.")
                        row("checkmark.circle.fill", "Vanzelf afgevinkt",
                            "Heb je gelopen, dan vinkt Rondje je training af.")
                        row("lock.fill", "Alleen lezen",
                            "Rondje zet niets in Health en bewaart er niets van.")
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 14) {
                    Button {
                        asking = true
                        Task {
                            await health.connect()
                            onDone()
                        }
                    } label: {
                        Text("Ga verder")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accent, in: Capsule())
                    }
                    .disabled(asking)
                    Button("Niet nu") {
                        health.declined = true
                        onDone()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .disabled(asking)
                    Text("Hierna vraagt Apple welke gegevens je deelt.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.background)
            }
            .navigationTitle("Nieuw doel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
            }
        }
    }

    private func row(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
